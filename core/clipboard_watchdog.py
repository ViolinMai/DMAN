import shutil
import subprocess
import sys
from typing import Callable, List, Set
from urllib.parse import urlparse

from PySide6.QtCore import QObject, QTimer, Signal
from PySide6.QtGui import QGuiApplication

from core.link_parser import extract_smart_links


class ClipboardWatchdog(QObject):
    """
    Monitors the system clipboard on Wayland/Hyprland and Windows.
    Modes:
      - 'disabled': Off
      - 'all': Captures any valid download link, magnet, or .torrent path
      - 'alldebrid_only': Captures only links matching AllDebrid supported domains or magnets
    """

    linksCaptured = Signal(str, int)  # newline-joined links, count

    def __init__(
        self,
        get_mode_fn: Callable[[], str],
        get_ad_domains_fn: Callable[[], List[str]],
        parent=None,
    ) -> None:
        super().__init__(parent)
        self._get_mode = get_mode_fn
        self._get_ad_domains = get_ad_domains_fn
        self._seen_links: Set[str] = set()
        self._last_raw_text = ""

        self._clipboard = QGuiApplication.clipboard()
        self._clipboard.dataChanged.connect(self._check_clipboard)

        self._wl_paste_bin = shutil.which("wl-paste") if sys.platform.startswith("linux") else None

        # Ultra-fast 250ms poll so background daemon catches links instantaneously
        self._poll_timer = QTimer(self)
        self._poll_timer.setInterval(250)
        self._poll_timer.timeout.connect(self._check_clipboard)
        self._poll_timer.start()

    def clear_seen_links(self) -> None:
        self._seen_links.clear()
        self._last_raw_text = ""

    def _read_clipboard_fast(self) -> str:
        try:
            text = self._clipboard.text() or ""
            if text:
                return text
        except Exception:
            pass
        if self._wl_paste_bin:
            try:
                res = subprocess.run(
                    [self._wl_paste_bin, "--no-newline"],
                    capture_output=True,
                    text=True,
                    timeout=0.15,
                )
                if res.returncode == 0 and res.stdout:
                    return res.stdout
            except Exception:
                pass
        return ""

    def _is_alldebrid_link(self, link: str, supported_domains: List[str]) -> bool:
        low = link.lower()
        if low.startswith("magnet:?") or low.endswith(".torrent"):
            return True
        parsed = urlparse(low)
        host = (parsed.hostname or "").lower()
        if not host:
            return False
        if host.endswith(".debrid.it") or host.endswith(".alldeb.ovh") or "alldebrid." in host:
            return True
        for dom in supported_domains:
            d = dom.lower()
            if host == d or host.endswith("." + d):
                return True
        return False

    def _check_clipboard(self) -> None:
        mode = self._get_mode()
        if mode == "disabled":
            return

        text = self._read_clipboard_fast()

        if not text or text == self._last_raw_text or len(text) > 32768:
            return
        self._last_raw_text = text

        extracted = extract_smart_links(text)
        if not extracted:
            return

        if mode == "alldebrid_only":
            domains = self._get_ad_domains()
            extracted = [l for l in extracted if self._is_alldebrid_link(l, domains)]

        # Ignore plain web browsing URLs unless they look like files, magnets, or AllDebrid hosts
        valid_candidates: List[str] = []
        ad_domains = self._get_ad_domains()
        file_exts = (
            ".zip", ".rar", ".7z", ".tar", ".gz", ".xz", ".iso", ".bin", ".exe",
            ".msi", ".deb", ".rpm", ".appimage", ".dmg", ".apk", ".mkv", ".mp4",
            ".avi", ".mov", ".mp3", ".flac", ".wav", ".pdf", ".epub", ".torrent",
        )
        for link in extracted:
            if link in self._seen_links:
                continue
            low = link.lower()
            path_part = urlparse(low).path
            if (
                low.startswith("magnet:?")
                or any(path_part.endswith(ext) for ext in file_exts)
                or self._is_alldebrid_link(link, ad_domains)
            ):
                valid_candidates.append(link)
                self._seen_links.add(link)

        if valid_candidates:
            self.linksCaptured.emit("\n".join(valid_candidates), len(valid_candidates))
