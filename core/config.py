import os
import sys
from pathlib import Path


class AppConfig:
    APP_NAME = "DMAN"
    APP_VERSION = "0.3.0"

    RPC_HOST = "127.0.0.1"
    RPC_PORT = 6800
    RPC_SECRET = "dman_local_rpc_secret"
    RPC_URL = f"http://{RPC_HOST}:{RPC_PORT}/jsonrpc"

    REMOTE_HTTP_HOST = "0.0.0.0"
    REMOTE_HTTP_PORT = 6801

    POLL_INTERVAL_MS = 400
    ALLDEBRID_BASE_URL = "https://api.alldebrid.com"
    ALLDEBRID_AGENT = "DMAN_Desktop"

    @staticmethod
    def get_default_download_dir() -> str:
        home = Path.home()
        downloads = home / "Downloads"
        if downloads.exists():
            return str(downloads)
        return str(home)

    @staticmethod
    def get_config_dir() -> Path:
        if sys.platform == "win32":
            base = Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming"))
        else:
            base = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
        cfg_dir = base / "dman"
        cfg_dir.mkdir(parents=True, exist_ok=True)
        return cfg_dir

    @staticmethod
    def get_session_file() -> Path:
        session_file = AppConfig.get_config_dir() / "aria2.session"
        if not session_file.exists():
            session_file.touch()
        return session_file

    @staticmethod
    def get_settings_file() -> Path:
        return AppConfig.get_config_dir() / "settings.json"

    @staticmethod
    def get_data_dir() -> Path:
        if sys.platform == "win32":
            base = Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming"))
        else:
            base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
        data_dir = base / "dman"
        data_dir.mkdir(parents=True, exist_ok=True)
        return data_dir

    @staticmethod
    def get_state_file() -> Path:
        return AppConfig.get_config_dir() / "downloads_history.json"
