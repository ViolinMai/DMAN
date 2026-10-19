import base64
import json
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Dict, List, Optional

from PySide6.QtCore import QThread, Signal

from core.config import AppConfig
from core.formatters import is_metadata_only_task
from core.settings import SettingsManager


class Aria2RPCClient:
    def __init__(self, settings: SettingsManager) -> None:
        self.settings = settings
        self.rpc_url = AppConfig.RPC_URL
        self.secret_token = f"token:{AppConfig.RPC_SECRET}"
        self._process: Optional[subprocess.Popen] = None

    def ensure_daemon_running(self) -> bool:
        if self.ping():
            self.apply_global_settings()
            return True

        aria2_bin = shutil.which("aria2c")
        if not aria2_bin:
            return False

        session_path = str(AppConfig.get_session_file())
        default_dir = self.settings.get("default_download_dir", AppConfig.get_default_download_dir())
        max_concurrent = int(self.settings.get("max_concurrent_downloads", 5))
        split_count = int(self.settings.get("split_count", 16))
        max_conn = int(self.settings.get("max_connection_per_server", 16))
        min_split = str(self.settings.get("min_split_size", "1M"))
        speed_limit_mb = int(self.settings.get("max_overall_download_limit_mb", 0))
        speed_limit_arg = f"{speed_limit_mb}M" if speed_limit_mb > 0 else "0"

        cmd = [
            aria2_bin,
            "--enable-rpc=true",
            "--rpc-listen-all=false",
            f"--rpc-listen-port={AppConfig.RPC_PORT}",
            f"--rpc-secret={AppConfig.RPC_SECRET}",
            "--rpc-allow-origin-all=true",
            f"--dir={default_dir}",
            f"--input-file={session_path}",
            f"--save-session={session_path}",
            "--save-session-interval=5",
            "--force-save=true",
            "--continue=true",
            "--auto-file-renaming=false",
            "--allow-overwrite=true",
            f"--max-concurrent-downloads={max_concurrent}",
            f"--max-connection-per-server={max_conn}",
            f"--split={split_count}",
            f"--min-split-size={min_split}",
            f"--max-overall-download-limit={speed_limit_arg}",
            "--bt-save-metadata=false",
            "--bt-remove-unselected-file=true",
            "--file-allocation=none",
            "--quiet=true",
        ]

        popen_kwargs: dict[str, Any] = {
            "stdout": subprocess.DEVNULL,
            "stderr": subprocess.DEVNULL,
            "stdin": subprocess.DEVNULL,
        }
        if sys.platform == "win32":
            popen_kwargs["creationflags"] = subprocess.CREATE_NO_WINDOW

        try:
            self._process = subprocess.Popen(cmd, **popen_kwargs)
        except OSError:
            return False

        for _ in range(15):
            if self.ping():
                return True
            QThread.msleep(100)

        return False

    def apply_global_settings(self) -> None:
        if not self.ping():
            return
        max_concurrent = str(self.settings.get("max_concurrent_downloads", 5))
        split_count = str(self.settings.get("split_count", 16))
        max_conn = str(self.settings.get("max_connection_per_server", 16))
        min_split = str(self.settings.get("min_split_size", "1M"))
        speed_limit_mb = int(self.settings.get("max_overall_download_limit_mb", 0))
        speed_limit_bytes = str(speed_limit_mb * 1024 * 1024) if speed_limit_mb > 0 else "0"

        options = {
            "max-concurrent-downloads": max_concurrent,
            "split": split_count,
            "max-connection-per-server": max_conn,
            "min-split-size": min_split,
            "max-overall-download-limit": speed_limit_bytes,
            "bt-save-metadata": "false",
            "force-save": "true",
            "continue": "true",
        }
        try:
            self.call("aria2.changeGlobalOption", [options])
        except Exception:
            pass

    def shutdown_daemon(self) -> None:
        if self._process is not None and self._process.poll() is None:
            try:
                self.call("aria2.saveSession")
                self.call("aria2.shutdown")
            except Exception:
                pass
            try:
                self._process.terminate()
            except Exception:
                pass

    def call(self, method: str, params: Optional[List[Any]] = None) -> Any:
        full_params: List[Any] = [self.secret_token]
        if params:
            full_params.extend(params)

        payload = {
            "jsonrpc": "2.0",
            "id": "dman_rpc",
            "method": method,
            "params": full_params,
        }

        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            self.rpc_url,
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=2.0) as response:
            body = json.loads(response.read().decode("utf-8"))
            if "error" in body:
                raise RuntimeError(body["error"].get("message", "Unknown RPC Error"))
            return body.get("result")

    def multicall(self, calls: List[dict]) -> List[Any]:
        formatted_calls = []
        for call_spec in calls:
            params = [self.secret_token]
            params.extend(call_spec.get("params", []))
            formatted_calls.append(
                {
                    "methodName": call_spec["methodName"],
                    "params": params,
                }
            )

        payload = {
            "jsonrpc": "2.0",
            "id": "dman_multicall",
            "method": "system.multicall",
            "params": [formatted_calls],
        }

        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            self.rpc_url,
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=2.0) as response:
            body = json.loads(response.read().decode("utf-8"))
            return body.get("result", [])

    def ping(self) -> bool:
        try:
            res = self.call("aria2.getVersion")
            return isinstance(res, dict) and "version" in res
        except Exception:
            return False

    def add_uri(
        self,
        uris: List[str],
        save_dir: str,
        custom_filename: str = "",
    ) -> str:
        split_count = int(self.settings.get("split_count", 16))
        max_conn = int(self.settings.get("max_connection_per_server", 16))
        min_split = str(self.settings.get("min_split_size", "1M"))

        options: Dict[str, str] = {
            "dir": save_dir,
            "max-connection-per-server": str(max_conn),
            "split": str(split_count),
            "min-split-size": min_split,
        }
        if custom_filename:
            options["out"] = custom_filename

        first_uri = uris[0] if uris else ""
        if first_uri.lower().endswith(".torrent") and Path(first_uri).exists():
            raw_torrent = Path(first_uri).read_bytes()
            b64_torrent = base64.b64encode(raw_torrent).decode("ascii")
            res_gid = self.call("aria2.addTorrent", [b64_torrent, [], options])
        else:
            res_gid = self.call("aria2.addUri", [uris, options])

        self.save_session()
        return res_gid

    def save_session(self) -> None:
        try:
            self.call("aria2.saveSession")
        except Exception:
            pass

    def change_item_dir(self, gid: str, new_dir: str) -> None:
        self.call("aria2.changeOption", [gid, {"dir": new_dir}])
        self.save_session()

    def pause(self, gid: str) -> Any:
        res = self.call("aria2.forcePause", [gid])
        self.save_session()
        return res

    def unpause(self, gid: str) -> Any:
        res = self.call("aria2.unpause", [gid])
        self.save_session()
        return res

    def remove(self, gid: str, status: str) -> Any:
        if status in ("complete", "error", "removed"):
            return self.call("aria2.removeDownloadResult", [gid])
        return self.call("aria2.forceRemove", [gid])

    def pause_all(self) -> Any:
        return self.call("aria2.pauseAll")

    def unpause_all(self) -> Any:
        return self.call("aria2.unpauseAll")


class Aria2PollerThread(QThread):
    snapshotReady = Signal(list, dict, bool)

    def __init__(self, client: Aria2RPCClient, parent=None) -> None:
        super().__init__(parent)
        self.client = client
        self._running = True

    def stop(self) -> None:
        self._running = False
        self.wait(1500)

    def run(self) -> None:
        self.client.ensure_daemon_running()

        keys = [
            "gid",
            "status",
            "totalLength",
            "completedLength",
            "downloadSpeed",
            "connections",
            "dir",
            "files",
            "bittorrent",
            "infoHash",
            "followedBy",
            "following",
            "errorCode",
            "errorMessage",
        ]

        while self._running:
            try:
                results = self.client.multicall(
                    [
                        {"methodName": "aria2.tellActive", "params": [keys]},
                        {"methodName": "aria2.tellWaiting", "params": [0, 1000, keys]},
                        {"methodName": "aria2.tellStopped", "params": [0, 1000, keys]},
                        {"methodName": "aria2.getGlobalStat", "params": []},
                    ]
                )

                if len(results) == 4:
                    active = results[0][0] if isinstance(results[0], list) else []
                    waiting = results[1][0] if isinstance(results[1], list) else []
                    stopped = results[2][0] if isinstance(results[2], list) else []
                    global_stat = results[3][0] if isinstance(results[3], list) else {}

                    # Automatically purge finished [METADATA] tasks so they never clutter the download table
                    clean_stopped = []
                    for item in stopped:
                        if is_metadata_only_task(item) and item.get("status") == "complete":
                            try:
                                self.client.call("aria2.removeDownloadResult", [item.get("gid", "")])
                            except Exception:
                                pass
                            continue
                        clean_stopped.append(item)

                    combined = active + waiting + clean_stopped
                    self.snapshotReady.emit(combined, global_stat, True)
                else:
                    self.snapshotReady.emit([], {}, False)
            except Exception:
                self.snapshotReady.emit([], {}, False)

            self.msleep(AppConfig.POLL_INTERVAL_MS)
