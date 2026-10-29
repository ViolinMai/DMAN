import json
from typing import Any, Dict

from core.config import AppConfig


class SettingsManager:
    DEFAULT_SETTINGS: Dict[str, Any] = {
        "default_download_dir": AppConfig.get_default_download_dir(),
        "max_concurrent_downloads": 5,
        "split_count": 16,
        "max_connection_per_server": 16,
        "min_split_size": "1M",
        "max_overall_download_limit_mb": 0,  # 0 = Unlimited (in MB/s)
        "alldebrid_enabled": False,
        "alldebrid_api_key": "",
        "alldebrid_cloud_magnets": True,
        # System Integration & Power
        "start_with_system": False,
        "start_minimized": False,
        "close_to_tray": True,
        "post_download_action": "nothing",  # nothing | sleep | shutdown | quit
        # Clipboard Watchdog
        "clipboard_mode": "all",  # disabled | all | alldebrid_only
        "clipboard_auto_popup": True,
        # Notifications Customization
        "notify_on_complete": True,
        "notify_on_error": True,
        "notify_on_clipboard": True,
        "notify_title_template": "DMAN - {event}",
        "notify_complete_template": "Finished downloading: {name} ({dir})",
        "notify_error_template": "Download failed: {name} - {error}",
        "notify_clipboard_template": "Captured {count} download link(s) — Click to choose path & start",
        # Remote Web API Server
        "remote_api_enabled": True,
        "remote_api_port": AppConfig.REMOTE_HTTP_PORT,
        "remote_api_token": "dman_remote_2026",
        "recent_download_dirs": [],
    }

    def __init__(self) -> None:
        self._path = AppConfig.get_settings_file()
        self._data: Dict[str, Any] = dict(self.DEFAULT_SETTINGS)
        self.load()

    def load(self) -> None:
        if not self._path.exists():
            self.save()
            return
        try:
            raw = json.loads(self._path.read_text(encoding="utf-8"))
            if isinstance(raw, dict):
                for key, default_val in self.DEFAULT_SETTINGS.items():
                    if key in raw and raw[key] is not None:
                        self._data[key] = raw[key]
        except Exception:
            self._data = dict(self.DEFAULT_SETTINGS)

    def save(self) -> None:
        try:
            self._path.write_text(
                json.dumps(self._data, indent=2, ensure_ascii=False),
                encoding="utf-8",
            )
        except Exception:
            pass

    def get(self, key: str, fallback: Any = None) -> Any:
        return self._data.get(key, fallback)

    def set(self, key: str, value: Any) -> None:
        self._data[key] = value
        self.save()

    def update_many(self, updates: Dict[str, Any]) -> None:
        self._data.update(updates)
        self.save()

    def as_dict(self) -> Dict[str, Any]:
        return dict(self._data)
