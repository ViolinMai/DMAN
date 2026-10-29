import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional, Set

from PySide6.QtCore import QMetaObject, QObject, Property, Qt, QThread, QUrl, Signal, Slot
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import QApplication, QFileDialog, QSystemTrayIcon

import logging
from cli.logger import GLOBAL_MEMORY_HANDLER
from backend.alldebrid_api import (
    AllDebridClient,
    AllDebridError,
    AllDebridPinAuthWorker,
    AllDebridResolverWorker,
)

_ctrl_logger = logging.getLogger("DMAN.Controller")
from backend.aria2_rpc import Aria2PollerThread, Aria2RPCClient
from backend.remote_server import RemoteAPIServer
from core.clipboard_watchdog import ClipboardWatchdog
from core.config import AppConfig
from core.formatters import format_bytes, format_eta, format_speed
from core.link_parser import classify_links, extract_smart_links
from core.settings import SettingsManager
from core.system_integration import SystemIntegration
from models.download_model import DownloadFilterProxyModel, DownloadModel


class _ClipboardPreResolveWorker(QThread):
    preResolved = Signal(str, int, str)  # links_text, count, summary_str

    def __init__(self, ad_client: AllDebridClient, links: List[str], use_ad: bool, parent=None) -> None:
        super().__init__(parent)
        self.ad_client = ad_client
        self.links = links
        self.use_ad = use_ad

    def run(self) -> None:
        if not self.use_ad or not self.ad_client.api_key:
            self.preResolved.emit("\n".join(self.links), len(self.links), f"Ready ({len(self.links)} link(s))")
            return
        try:
            meta = self.ad_client.probe_links_metadata(self.links)
            total_b = int(meta.get("totalBytes", 0))
            items = meta.get("items", [])
            first_name = items[0].get("filename", "") if items else ""
            size_part = f" • {format_bytes(total_b)}" if total_b > 0 else ""
            label = f"AllDebrid Ready: {first_name}{size_part}" if len(items) == 1 else f"AllDebrid Ready: {len(items)} files{size_part}"
            self.preResolved.emit("\n".join(self.links), len(self.links), label)
        except Exception:
            self.preResolved.emit("\n".join(self.links), len(self.links), f"Ready ({len(self.links)} link(s))")


class AppController(QObject):
    overviewChanged = Signal()
    selectionChanged = Signal()
    settingsChanged = Signal()
    alldebridChanged = Signal()
    pinDataReady = Signal(str, str, int)
    notificationEmitted = Signal(str, bool)
    clipboardLinksDetected = Signal(str, int)
    stagedClipboardChanged = Signal()
    remoteAddRequested = Signal(str, str, bool)
    requestShowMainWindow = Signal()
    logsChanged = Signal()

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self._settings = SettingsManager()
        self._rpc_client = Aria2RPCClient(self._settings)
        self._ad_client = AllDebridClient(self._settings.get("alldebrid_api_key", ""))

        self._source_model = DownloadModel(self)
        self._proxy_model = DownloadFilterProxyModel(self)
        self._proxy_model.setSourceModel(self._source_model)

        self._tray_icon: Optional[QSystemTrayIcon] = None
        self._rpc_connected = False

        self._total_packages = 0
        self._active_downloads = 0
        self._open_connections = 0
        self._total_bytes_str = "0 B"
        self._loaded_bytes_str = "0 B"
        self._remaining_bytes_str = "0 B"
        self._global_speed_str = "0 B/s"
        self._global_eta_str = "~"

        self._selected_gid = ""
        self._selected_item: Dict = {}

        # Track status transitions for notifications & post-download actions
        self._known_statuses: Dict[str, str] = {}
        self._had_active_downloads = False

        # AllDebrid account state
        self._ad_username = ""
        self._ad_is_premium = False
        self._ad_status_text = "Not Connected"
        self._ad_domains: List[str] = []

        self._pin_worker: Optional[AllDebridPinAuthWorker] = None
        self._active_resolvers: List[AllDebridResolverWorker] = []
        self._pre_resolve_worker: Optional[_ClipboardPreResolveWorker] = None

        # Pre-staged clipboard links waiting for user path confirmation
        self._staged_links_text = ""
        self._staged_links_count = 0
        self._staged_summary = ""

        self.remoteAddRequested.connect(self._on_remote_add_requested)

        self._poller = Aria2PollerThread(self._rpc_client, self)
        self._poller.snapshotReady.connect(self._on_snapshot_ready)
        self._poller.start()

        # Clipboard Watchdog
        self._clipboard_watchdog = ClipboardWatchdog(
            get_mode_fn=lambda: str(self._settings.get("clipboard_mode", "all")),
            get_ad_domains_fn=lambda: self._ad_domains,
            parent=self,
        )
        self._clipboard_watchdog.linksCaptured.connect(self._on_clipboard_links_captured)

        # Built-in Remote Web API Server for GitHub Pages PWA
        self._remote_server = RemoteAPIServer(
            get_state_fn=self._build_remote_state,
            probe_links_fn=self._remote_probe_links,
            enqueue_fn=self._remote_enqueue_links,
            action_fn=self._remote_execute_action,
            get_token_fn=lambda: str(self._settings.get("remote_api_token", "dman_remote_2026")),
            port=int(self._settings.get("remote_api_port", AppConfig.REMOTE_HTTP_PORT)),
        )
        if self._settings.get("remote_api_enabled", True):
            self._remote_server.start()

        if self._settings.get("alldebrid_enabled") and self._ad_client.api_key:
            self.verifyAllDebridAccount(silent=True)

    def set_tray_icon(self, tray: QSystemTrayIcon) -> None:
        self._tray_icon = tray
        if self._tray_icon is not None:
            self._tray_icon.messageClicked.connect(self.openStagedLinksFromNotification)

    @Slot()
    def openStagedLinksFromNotification(self) -> None:
        if self._staged_links_text:
            self.clipboardLinksDetected.emit(self._staged_links_text, self._staged_links_count)
        else:
            self.requestShowMainWindow.emit()

    def shutdown(self) -> None:
        self._remote_server.stop()
        if self._pin_worker:
            self._pin_worker.stop()
        for worker in self._active_resolvers:
            worker.stop()
        self._poller.stop()
        self._rpc_client.shutdown_daemon()

    # --- System Lifecycle Actions ---
    @Slot()
    def shutdownApp(self) -> None:
        self.shutdown()
        QApplication.quit()

    @Slot()
    def restartApp(self) -> None:
        self.shutdown()
        python_exe = sys.executable
        main_script = str(Path(__file__).resolve().parent.parent / "main.py")
        subprocess.Popen([python_exe, main_script])
        QApplication.quit()

    # --- Models & Connection Properties ---
    @Property(QObject, constant=True)
    def downloadModel(self) -> QObject:
        return self._proxy_model

    @Property(bool, notify=overviewChanged)
    def rpcConnected(self) -> bool:
        return self._rpc_connected

    # --- Engine & General Settings Properties ---
    @Property(str, notify=settingsChanged)
    def defaultSaveDir(self) -> str:
        return str(self._settings.get("default_download_dir", ""))

    @Property(int, notify=settingsChanged)
    def maxConcurrentDownloads(self) -> int:
        return int(self._settings.get("max_concurrent_downloads", 5))

    @Property(int, notify=settingsChanged)
    def splitCount(self) -> int:
        return int(self._settings.get("split_count", 16))

    @Property(int, notify=settingsChanged)
    def maxConnectionPerServer(self) -> int:
        return int(self._settings.get("max_connection_per_server", 16))

    @Property(str, notify=settingsChanged)
    def minSplitSize(self) -> str:
        return str(self._settings.get("min_split_size", "1M"))

    @Property(int, notify=settingsChanged)
    def speedLimitMb(self) -> int:
        return int(self._settings.get("max_overall_download_limit_mb", 0))

    @Property(bool, notify=settingsChanged)
    def startWithSystem(self) -> bool:
        return bool(self._settings.get("start_with_system", False))

    @Property(bool, notify=settingsChanged)
    def startMinimized(self) -> bool:
        return bool(self._settings.get("start_minimized", False))

    @Property(bool, notify=settingsChanged)
    def closeToTray(self) -> bool:
        return bool(self._settings.get("close_to_tray", True))

    @Property(str, notify=settingsChanged)
    def postDownloadAction(self) -> str:
        return str(self._settings.get("post_download_action", "nothing"))

    @Slot(str)
    def setPostDownloadAction(self, action: str) -> None:
        self._settings.set("post_download_action", action)
        self.settingsChanged.emit()

    # --- Clipboard Settings Properties ---
    @Property(str, notify=settingsChanged)
    def clipboardMode(self) -> str:
        return str(self._settings.get("clipboard_mode", "all"))

    @Property(bool, notify=settingsChanged)
    def clipboardAutoPopup(self) -> bool:
        return bool(self._settings.get("clipboard_auto_popup", True))

    # --- Notification Customization Properties ---
    @Property(bool, notify=settingsChanged)
    def notifyOnComplete(self) -> bool:
        return bool(self._settings.get("notify_on_complete", True))

    @Property(bool, notify=settingsChanged)
    def notifyOnError(self) -> bool:
        return bool(self._settings.get("notify_on_error", True))

    @Property(bool, notify=settingsChanged)
    def notifyOnClipboard(self) -> bool:
        return bool(self._settings.get("notify_on_clipboard", True))

    @Property(str, notify=settingsChanged)
    def notifyTitleTemplate(self) -> str:
        return str(self._settings.get("notify_title_template", "DMAN - {event}"))

    @Property(str, notify=settingsChanged)
    def notifyCompleteTemplate(self) -> str:
        return str(self._settings.get("notify_complete_template", "Finished downloading: {name} ({dir})"))

    @Property(str, notify=settingsChanged)
    def notifyErrorTemplate(self) -> str:
        return str(self._settings.get("notify_error_template", "Download failed: {name} - {error}"))

    @Property(str, notify=settingsChanged)
    def notifyClipboardTemplate(self) -> str:
        return str(self._settings.get("notify_clipboard_template", "Captured {count} download link(s) from clipboard"))

    # --- AllDebrid Settings & Status Properties ---
    @Property(bool, notify=settingsChanged)
    def alldebridEnabled(self) -> bool:
        return bool(self._settings.get("alldebrid_enabled", False))

    @Property(str, notify=settingsChanged)
    def alldebridApiKey(self) -> str:
        return str(self._settings.get("alldebrid_api_key", ""))

    @Property(bool, notify=settingsChanged)
    def alldebridCloudMagnets(self) -> bool:
        return bool(self._settings.get("alldebrid_cloud_magnets", True))

    @Property(str, notify=alldebridChanged)
    def alldebridUsername(self) -> str:
        return self._ad_username

    @Property(bool, notify=alldebridChanged)
    def alldebridIsPremium(self) -> bool:
        return self._ad_is_premium

    @Property(str, notify=alldebridChanged)
    def alldebridStatusText(self) -> str:
        return self._ad_status_text

    @Property(str, notify=stagedClipboardChanged)
    def stagedSummary(self) -> str:
        return self._staged_summary

    @Property(bool, notify=settingsChanged)
    def remoteApiEnabled(self) -> bool:
        return bool(self._settings.get("remote_api_enabled", True))

    @Property(int, notify=settingsChanged)
    def remoteApiPort(self) -> int:
        return int(self._settings.get("remote_api_port", AppConfig.REMOTE_HTTP_PORT))

    @Property(str, notify=settingsChanged)
    def remoteApiToken(self) -> str:
        return str(self._settings.get("remote_api_token", "dman_remote_2026"))

    @Property("QVariantList", notify=settingsChanged)
    def recentDownloadDirs(self) -> List[str]:
        saved = list(self._settings.get("recent_download_dirs", []))
        default_d = self.defaultSaveDir
        if default_d and default_d not in saved:
            saved.insert(0, default_d)
        return saved[:8]

    @Slot(str, result=str)
    def getDiskFreeSpaceStr(self, folder_path: str) -> str:
        free_b = SystemIntegration.get_disk_free_bytes(folder_path or self.defaultSaveDir)
        return format_bytes(free_b) if free_b > 0 else "Unknown"

    # --- Overview Metrics Properties ---
    @Property(int, notify=overviewChanged)
    def totalPackages(self) -> int:
        return self._total_packages

    @Property(int, notify=overviewChanged)
    def activeDownloads(self) -> int:
        return self._active_downloads

    @Property(int, notify=overviewChanged)
    def openConnections(self) -> int:
        return self._open_connections

    @Property(str, notify=overviewChanged)
    def totalBytesStr(self) -> str:
        return self._total_bytes_str

    @Property(str, notify=overviewChanged)
    def loadedBytesStr(self) -> str:
        return self._loaded_bytes_str

    @Property(str, notify=overviewChanged)
    def remainingBytesStr(self) -> str:
        return self._remaining_bytes_str

    @Property(str, notify=overviewChanged)
    def globalSpeedStr(self) -> str:
        return self._global_speed_str

    @Property(str, notify=overviewChanged)
    def globalEtaStr(self) -> str:
        return self._global_eta_str

    @Property(str, notify=selectionChanged)
    def selectedGid(self) -> str:
        return self._selected_gid

    @Property("QVariantMap", notify=selectionChanged)
    def selectedItem(self) -> Dict:
        return self._selected_item

    # --- Native File/Folder Browsers ---
    @Slot(str, result=str)
    def browseFolder(self, current_dir: str = "") -> str:
        start_dir = current_dir.strip() or self.defaultSaveDir
        chosen = QFileDialog.getExistingDirectory(
            None,
            "Select Download Directory",
            start_dir,
            QFileDialog.ShowDirsOnly | QFileDialog.DontResolveSymlinks,
        )
        return chosen if chosen else ""

    @Slot(result=str)
    def browseTorrentFile(self) -> str:
        chosen, _ = QFileDialog.getOpenFileName(
            None,
            "Select .torrent File",
            self.defaultSaveDir,
            "Torrent Files (*.torrent)",
        )
        return chosen if chosen else ""

    @Slot(str, result="QVariantMap")
    def analyzeLinksText(self, raw_text: str) -> Dict:
        links = extract_smart_links(raw_text)
        classified = classify_links(links)
        return {
            "total": len(links),
            "httpCount": len(classified["urls"]),
            "magnetCount": len(classified["magnets"]) + len(classified.get("torrents", [])),
            "links": links,
        }

    # --- Save Settings ---
    @Slot("QVariantMap")
    def saveSettings(self, new_settings: Dict) -> None:
        updates = {
            "default_download_dir": str(new_settings.get("defaultSaveDir", self.defaultSaveDir)).strip(),
            "max_concurrent_downloads": max(1, int(new_settings.get("maxConcurrentDownloads", 5))),
            "split_count": max(1, min(64, int(new_settings.get("splitCount", 16)))),
            "max_connection_per_server": max(1, min(16, int(new_settings.get("maxConnectionPerServer", 16)))),
            "min_split_size": str(new_settings.get("minSplitSize", "1M")).strip() or "1M",
            "max_overall_download_limit_mb": max(0, int(new_settings.get("speedLimitMb", 0))),
            "alldebrid_enabled": bool(new_settings.get("alldebridEnabled", False)),
            "alldebrid_api_key": str(new_settings.get("alldebridApiKey", "")).strip(),
            "alldebrid_cloud_magnets": bool(new_settings.get("alldebridCloudMagnets", True)),
            "start_with_system": bool(new_settings.get("startWithSystem", False)),
            "start_minimized": bool(new_settings.get("startMinimized", False)),
            "close_to_tray": bool(new_settings.get("closeToTray", True)),
            "post_download_action": str(new_settings.get("postDownloadAction", "nothing")),
            "clipboard_mode": str(new_settings.get("clipboardMode", "all")),
            "clipboard_auto_popup": bool(new_settings.get("clipboardAutoPopup", True)),
            "notify_on_complete": bool(new_settings.get("notifyOnComplete", True)),
            "notify_on_error": bool(new_settings.get("notifyOnError", True)),
            "notify_on_clipboard": bool(new_settings.get("notifyOnClipboard", True)),
            "notify_title_template": str(new_settings.get("notifyTitleTemplate", "DMAN - {event}")).strip(),
            "notify_complete_template": str(new_settings.get("notifyCompleteTemplate", "")).strip(),
            "notify_error_template": str(new_settings.get("notifyErrorTemplate", "")).strip(),
            "notify_clipboard_template": str(new_settings.get("notifyClipboardTemplate", "")).strip(),
        }

        old_key = self._ad_client.api_key
        self._settings.update_many(updates)
        SystemIntegration.set_autostart(updates["start_with_system"])
        self._ad_client.set_api_key(updates["alldebrid_api_key"])
        self._rpc_client.apply_global_settings()
        self.settingsChanged.emit()

        if updates["alldebrid_enabled"] and updates["alldebrid_api_key"]:
            if updates["alldebrid_api_key"] != old_key or not self._ad_username:
                self.verifyAllDebridAccount(silent=False)
        elif not updates["alldebrid_enabled"]:
            self._ad_status_text = "Disabled"
            self.alldebridChanged.emit()

        self.notificationEmitted.emit("Settings saved and applied live.", False)

    @Slot()
    def testCustomNotification(self) -> None:
        title = SystemIntegration.format_template(
            self.notifyTitleTemplate,
            {"event": "Test Notification", "name": "Ubuntu.iso", "dir": self.defaultSaveDir, "count": "1", "error": "None"},
        )
        body = SystemIntegration.format_template(
            self.notifyCompleteTemplate,
            {"event": "Completed", "name": "Ubuntu.iso", "dir": self.defaultSaveDir, "count": "1", "error": "None"},
        )
        SystemIntegration.send_os_notification(title, body, self._tray_icon)
        self.notificationEmitted.emit(f"{title}: {body}", False)

    # --- Clipboard Event Handler & Instant Pre-Stage ---
    def _on_clipboard_links_captured(self, links_text: str, count: int) -> None:
        self._staged_links_text = links_text
        self._staged_links_count = count
        self._staged_summary = f"Analyzing {count} captured link(s)..."
        self.stagedClipboardChanged.emit()

        links = extract_smart_links(links_text)
        self._pre_resolve_worker = _ClipboardPreResolveWorker(
            self._ad_client,
            links,
            self.alldebridEnabled,
            self,
        )
        self._pre_resolve_worker.preResolved.connect(self._on_clipboard_pre_resolved)
        self._pre_resolve_worker.start()

        if self.notifyOnClipboard:
            title = SystemIntegration.format_template(
                self.notifyTitleTemplate,
                {"event": "Links Ready", "count": str(count), "name": "", "dir": self.defaultSaveDir, "error": ""},
            )
            body = SystemIntegration.format_template(
                self.notifyClipboardTemplate,
                {"event": "Links Ready", "count": str(count), "name": "", "dir": self.defaultSaveDir, "error": ""},
            )
            SystemIntegration.send_os_notification(title, body, self._tray_icon)

        if self.clipboardAutoPopup:
            self.clipboardLinksDetected.emit(links_text, count)

    def _on_clipboard_pre_resolved(self, links_text: str, count: int, summary: str) -> None:
        self._staged_summary = summary
        self.stagedClipboardChanged.emit()

    # --- AllDebrid Authentication ---
    @Slot()
    def verifyAllDebridAccount(self, silent: bool = False) -> None:
        if not self._ad_client.api_key:
            self._ad_username = ""
            self._ad_is_premium = False
            self._ad_status_text = "No API Key"
            self.alldebridChanged.emit()
            if not silent:
                self.notificationEmitted.emit("Please enter an AllDebrid API key first.", True)
            return

        try:
            user = self._ad_client.get_user_info(force_refresh=True)
            self._ad_domains = self._ad_client.get_supported_domains()
            self._ad_username = user.get("username", "User")
            self._ad_is_premium = bool(user.get("isPremium", False))
            tier = "Premium" if self._ad_is_premium else ("Trial" if user.get("isTrial") else "Free")
            self._ad_status_text = f"{self._ad_username} ({tier})"
            self.alldebridChanged.emit()
            if not silent:
                self.notificationEmitted.emit(f"AllDebrid connected: {self._ad_status_text}", False)
        except AllDebridError as exc:
            self._ad_username = ""
            self._ad_is_premium = False
            self._ad_status_text = f"Auth Error ({exc.code})"
            self.alldebridChanged.emit()
            if not silent:
                self.notificationEmitted.emit(f"AllDebrid Error: {exc.message}", True)

    @Slot()
    def startAllDebridPinAuth(self) -> None:
        if self._pin_worker and self._pin_worker.isRunning():
            self._pin_worker.stop()

        self._pin_worker = AllDebridPinAuthWorker(self._ad_client, self)
        self._pin_worker.pinGenerated.connect(self._on_pin_generated)
        self._pin_worker.pinAuthenticated.connect(self._on_pin_authenticated)
        self._pin_worker.pinError.connect(lambda msg: self.notificationEmitted.emit(msg, True))
        self._pin_worker.start()

    def _on_pin_generated(self, pin: str, user_url: str, expires_in: int) -> None:
        self.pinDataReady.emit(pin, user_url, expires_in)
        SystemIntegration.open_url_safe(user_url)

    def _on_pin_authenticated(self, apikey: str) -> None:
        self._settings.update_many({"alldebrid_api_key": apikey, "alldebrid_enabled": True})
        self._ad_client.set_api_key(apikey)
        self.settingsChanged.emit()
        self.verifyAllDebridAccount(silent=False)

    # --- Selection & Package / Item Actions ---
    @Slot(str)
    def selectDownload(self, gid: str) -> None:
        if self._selected_gid != gid:
            self._selected_gid = gid
        self._selected_item = self._source_model.get_by_gid(gid) if gid else {}
        self.selectionChanged.emit()

    @Slot(str, str, bool, bool)
    def addLinks(
        self,
        raw_links_text: str,
        save_dir: str,
        save_as_default_dir: bool = False,
        use_alldebrid: bool = False,
    ) -> None:
        links = extract_smart_links(raw_links_text)
        if not links:
            self.notificationEmitted.emit("No valid HTTP/FTP/Magnet/Torrent links found.", True)
            return

        target_dir = save_dir.strip() or self.defaultSaveDir
        Path(target_dir).mkdir(parents=True, exist_ok=True)

        # Save into recent directories list for 1-click path selection
        recent = list(self._settings.get("recent_download_dirs", []))
        if target_dir in recent:
            recent.remove(target_dir)
        recent.insert(0, target_dir)
        self._settings.set("recent_download_dirs", recent[:8])

        if save_as_default_dir and target_dir != self.defaultSaveDir:
            self._settings.set("default_download_dir", target_dir)
        self.settingsChanged.emit()

        if use_alldebrid and self.alldebridEnabled and self._ad_client.api_key:
            direct_cdn_links: List[str] = []
            hoster_links: List[str] = []

            for l in links:
                if AllDebridClient.is_direct_cdn_link(l):
                    direct_cdn_links.append(l)
                else:
                    hoster_links.append(l)

            if direct_cdn_links:
                _ctrl_logger.info("Fast-tracking %d direct Debrid CDN link(s) straight to aria2c.", len(direct_cdn_links))
                for dlink in direct_cdn_links:
                    fn = AllDebridClient.extract_url_filename(dlink)
                    self._enqueue_direct_aria2(dlink, target_dir, fn)
                if not hoster_links:
                    self.notificationEmitted.emit(f"Added {len(direct_cdn_links)} direct Debrid download(s).", False)
                    return

            _ctrl_logger.info("Dispatching %d link(s) to AllDebridResolverWorker.", len(hoster_links))
            self.notificationEmitted.emit(
                f"Routing {len(hoster_links)} item(s) safely through AllDebrid...",
                False,
            )
            worker = AllDebridResolverWorker(
                client=self._ad_client,
                links=hoster_links,
                save_dir=target_dir,
                use_cloud_magnets=self.alldebridCloudMagnets,
                parent=self,
            )
            worker.directLinkReady.connect(self._enqueue_direct_aria2)
            worker.fallbackToAria2.connect(lambda u, d: self._enqueue_direct_aria2(u, d, ""))
            worker.statusMessage.connect(self._on_worker_status_message)
            self._active_resolvers.append(worker)
            worker.start()
            return

        added_count = 0
        for url in links:
            if self._enqueue_direct_aria2(url, target_dir, ""):
                added_count += 1

        if added_count > 0:
            self.notificationEmitted.emit(f"Added {added_count} download(s) to aria2 queue.", False)

    def _on_worker_status_message(self, message: str, is_error: bool) -> None:
        if is_error:
            _ctrl_logger.error(message)
        else:
            _ctrl_logger.info(message)
        self.logsChanged.emit()
        self.notificationEmitted.emit(message, is_error)

    def _enqueue_direct_aria2(self, url: str, target_dir: str, custom_filename: str = "") -> bool:
        try:
            Path(target_dir).mkdir(parents=True, exist_ok=True)
            gid = self._rpc_client.add_uri([url], target_dir, custom_filename=custom_filename)
            _ctrl_logger.info("aria2c addUri OK -> GID=%s | File='%s' | Dir='%s'", gid, custom_filename or "(auto)", target_dir)
            if gid:
                self._source_model.register_source_uri(gid, url)
            self.logsChanged.emit()
            return True
        except Exception as exc:
            _ctrl_logger.error("Failed to enqueue link '%s' to aria2c: %s", url, exc)
            self.logsChanged.emit()
            self.notificationEmitted.emit(f"Failed to enqueue link: {exc}", True)
            return False

    @Property(str, notify=logsChanged)
    def debugLogsText(self) -> str:
        return GLOBAL_MEMORY_HANDLER.get_logs_text()

    @Slot()
    def refreshDebugLogs(self) -> None:
        self.logsChanged.emit()

    @Slot()
    def clearDebugLogs(self) -> None:
        GLOBAL_MEMORY_HANDLER.clear()
        self.logsChanged.emit()

    @Slot(str)
    def copyLogsToClipboard(self, text: str) -> None:
        QApplication.clipboard().setText(text)
        self.notificationEmitted.emit("Debug logs copied to clipboard.", False)

    def _target_items_for_gid(self, gid: str) -> List[Dict]:
        if gid.startswith("PKG::"):
            pkg_key = gid.split("PKG::", 1)[1]
            return self._source_model.get_children_for_package(pkg_key)
        item = self._source_model.get_by_gid(gid)
        return [item] if item else []

    @Slot(str)
    def pauseDownload(self, gid: str) -> None:
        for item in self._target_items_for_gid(gid):
            if item.get("status") in ("active", "waiting"):
                try:
                    self._rpc_client.pause(item["gid"])
                except Exception:
                    pass

    @Slot(str)
    def resumeDownload(self, gid: str) -> None:
        for item in self._target_items_for_gid(gid):
            st = item.get("status")
            if st == "paused":
                try:
                    self._rpc_client.unpause(item["gid"])
                except Exception:
                    pass
            elif st in ("error", "missing"):
                self._retry_single_item(item)

    @Slot(str)
    def retryDownload(self, gid: str) -> None:
        retried = 0
        for item in self._target_items_for_gid(gid):
            if item.get("status") in ("error", "missing", "removed") or not item.get("fileExists", True):
                if self._retry_single_item(item):
                    retried += 1
        if retried > 0:
            self.notificationEmitted.emit(f"Retrying {retried} download(s)...", False)

    def _retry_single_item(self, item: Dict) -> bool:
        uri = item.get("sourceUri", "")
        save_dir = item.get("saveDir", self.defaultSaveDir)
        old_gid = item.get("gid", "")
        if not uri:
            self.notificationEmitted.emit("Cannot retry: original source URI unavailable.", True)
            return False
        try:
            self._rpc_client.remove(old_gid, item.get("status", "error"))
        except Exception:
            pass
        return self._enqueue_direct_aria2(uri, save_dir, "")

    @Slot(str, str)
    def changeDownloadPath(self, gid: str, new_dir: str) -> None:
        cleaned_dir = new_dir.strip()
        if not cleaned_dir:
            return
        Path(cleaned_dir).mkdir(parents=True, exist_ok=True)
        targets = self._target_items_for_gid(gid)
        updated = 0
        for item in targets:
            c_gid = item.get("gid", "")
            st = item.get("status", "")
            try:
                if st in ("active", "waiting", "paused"):
                    self._rpc_client.change_item_dir(c_gid, cleaned_dir)
                    updated += 1
            except Exception:
                pass
        if updated > 0:
            self.notificationEmitted.emit(f"Updated path for {updated} item(s) to {cleaned_dir}", False)

    @Slot(str, str)
    def removeDownload(self, gid: str, status: str) -> None:
        for item in self._target_items_for_gid(gid):
            c_gid = item.get("gid", "")
            try:
                st = "complete" if item.get("status") == "missing" else item.get("status", status)
                self._rpc_client.remove(c_gid, st)
            except Exception:
                pass
            if c_gid:
                self._source_model.remove_from_history(c_gid)
                self._known_statuses.pop(c_gid, None)
        if self._selected_gid == gid:
            self.selectDownload("")

    # --- Remote Web API Handlers (GitHub Pages Remote Companion) ---
    def _on_remote_add_requested(self, raw_links: str, target_dir: str, use_alldebrid: bool) -> None:
        self.addLinks(raw_links, target_dir, False, use_alldebrid)

    def _build_remote_state(self) -> Dict:
        children = self._source_model.get_all_child_items()
        default_dir = self.defaultSaveDir
        free_b = SystemIntegration.get_disk_free_bytes(default_dir)
        return {
            "rpcConnected": self._rpc_connected,
            "alldebridEnabled": self.alldebridEnabled,
            "alldebridStatus": self.alldebridStatusText,
            "defaultSaveDir": default_dir,
            "recentDirs": self.recentDownloadDirs,
            "freeBytes": free_b,
            "freeSpaceStr": format_bytes(free_b),
            "globalSpeedStr": self._global_speed_str,
            "globalEtaStr": self._global_eta_str,
            "totalBytesStr": self._total_bytes_str,
            "loadedBytesStr": self._loaded_bytes_str,
            "activeDownloads": self._active_downloads,
            "totalPackages": self._total_packages,
            "downloads": children,
        }

    def _remote_probe_links(self, raw_links: str, save_dir: str) -> Dict:
        links = extract_smart_links(raw_links)
        target_dir = save_dir.strip() or self.defaultSaveDir
        free_b = SystemIntegration.get_disk_free_bytes(target_dir)
        meta = self._ad_client.probe_links_metadata(links) if links else {"totalBytes": 0, "items": []}
        req_b = int(meta.get("totalBytes", 0))
        return {
            "count": len(links),
            "links": links,
            "items": meta.get("items", []),
            "requiredBytes": req_b,
            "requiredStr": format_bytes(req_b) if req_b > 0 else "Unknown",
            "freeBytes": free_b,
            "freeStr": format_bytes(free_b),
            "hasEnoughSpace": (free_b > req_b) if (free_b > 0 and req_b > 0) else True,
            "targetDir": target_dir,
        }

    def _remote_enqueue_links(self, raw_links: str, save_dir: str, subfolder: str, use_ad: bool) -> Dict:
        links = extract_smart_links(raw_links)
        if not links:
            return {"status": "error", "message": "No valid links detected"}
        base_dir = Path(save_dir.strip() or self.defaultSaveDir)
        if subfolder.strip():
            safe_sub = subfolder.strip().strip("/\\")
            base_dir = base_dir / safe_sub
        target_dir = str(base_dir)
        self.remoteAddRequested.emit("\n".join(links), target_dir, use_ad)
        return {
            "status": "ok",
            "message": f"Queued {len(links)} link(s) into {target_dir}",
            "targetDir": target_dir,
            "count": len(links),
        }

    def _remote_execute_action(self, action: str, gid: str) -> Dict:
        act = action.lower().strip()
        if act == "pause" and gid:
            self.pauseDownload(gid)
        elif act == "resume" and gid:
            self.resumeDownload(gid)
        elif act == "remove" and gid:
            self.removeDownload(gid, "")
        elif act == "pause_all":
            self.pauseAll()
        elif act == "resume_all":
            self.resumeAll()
        else:
            return {"status": "error", "message": f"Unknown action: {action}"}
        return {"status": "ok", "action": act, "gid": gid}

    @Slot()
    def pauseAll(self) -> None:
        try:
            self._rpc_client.pause_all()
            self._rpc_client.save_session()
        except Exception as exc:
            self.notificationEmitted.emit(f"Pause all error: {exc}", True)

    @Slot()
    def resumeAll(self) -> None:
        try:
            self._rpc_client.unpause_all()
            self._rpc_client.save_session()
        except Exception as exc:
            self.notificationEmitted.emit(f"Resume all error: {exc}", True)

    @Slot(str)
    def openFolder(self, folder_path: str) -> None:
        path = folder_path.strip() or self.defaultSaveDir
        if Path(path).exists():
            QDesktopServices.openUrl(QUrl.fromLocalFile(path))

    # --- Live Aria2 Snapshot & Event Detection ---
    def _on_snapshot_ready(self, items: List[Dict], global_stat: Dict, connected: bool) -> None:
        self._rpc_connected = connected
        self._source_model.sync_items(items)

        child_items = self._source_model.get_all_child_items()

        total_bytes = 0
        loaded_bytes = 0
        connections = 0
        active_count = 0

        for child in child_items:
            gid = child["gid"]
            new_status = child["status"]
            old_status = self._known_statuses.get(gid)
            self._known_statuses[gid] = new_status

            # Fire custom OS notifications on status transition
            if old_status in ("active", "waiting") and new_status == "complete":
                if self.notifyOnComplete:
                    ctx = {
                        "event": "Download Complete",
                        "name": child["name"],
                        "dir": child["saveDir"],
                        "count": "1",
                        "error": "",
                    }
                    title = SystemIntegration.format_template(self.notifyTitleTemplate, ctx)
                    body = SystemIntegration.format_template(self.notifyCompleteTemplate, ctx)
                    SystemIntegration.send_os_notification(title, body, self._tray_icon)

            elif old_status in ("active", "waiting") and new_status == "error":
                if self.notifyOnError:
                    ctx = {
                        "event": "Download Error",
                        "name": child["name"],
                        "dir": child["saveDir"],
                        "count": "1",
                        "error": child.get("errorMsg") or "Failed",
                    }
                    title = SystemIntegration.format_template(self.notifyTitleTemplate, ctx)
                    body = SystemIntegration.format_template(self.notifyErrorTemplate, ctx)
                    SystemIntegration.send_os_notification(title, body, self._tray_icon)

            total_bytes += child["rawTotalBytes"]
            loaded_bytes += child["rawCompletedBytes"]
            if new_status == "active":
                active_count += 1
                connections += child["connections"]

        # Trigger Post-Download Action if queue transitioned from active -> all finished
        if active_count > 0:
            self._had_active_downloads = True
        elif self._had_active_downloads and active_count == 0:
            waiting_count = sum(1 for c in child_items if c["status"] == "waiting")
            if waiting_count == 0:
                self._had_active_downloads = False
                self._trigger_post_download_action()

        remaining_bytes = max(0, total_bytes - loaded_bytes)
        global_speed = int(global_stat.get("downloadSpeed", 0))

        self._total_packages = len(child_items)
        self._active_downloads = active_count
        self._open_connections = connections
        self._total_bytes_str = format_bytes(total_bytes)
        self._loaded_bytes_str = format_bytes(loaded_bytes)
        self._remaining_bytes_str = format_bytes(remaining_bytes)
        self._global_speed_str = format_speed(global_speed)
        self._global_eta_str = format_eta(total_bytes, loaded_bytes, global_speed)

        if self._selected_gid:
            updated_sel = self._source_model.get_by_gid(self._selected_gid)
            if updated_sel != self._selected_item:
                self._selected_item = updated_sel
                self.selectionChanged.emit()

        self.overviewChanged.emit()

    def _trigger_post_download_action(self) -> None:
        action = self.postDownloadAction
        if action == "nothing":
            return
        if action == "quit":
            self.shutdownApp()
        elif action in ("sleep", "shutdown"):
            SystemIntegration.execute_power_action(action)
