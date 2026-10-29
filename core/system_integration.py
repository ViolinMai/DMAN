import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Callable, Dict, Optional

from PySide6.QtWidgets import QSystemTrayIcon


class SystemIntegration:
    """
    Cross-platform integration for Wayland/Hyprland (Linux) and Windows:
    - Native desktop notifications (notify-send / Tray messages) with custom template formatting
    - Autostart management (XDG ~/.config/autostart/dman.desktop & Windows Registry Run)
    - Post-download power actions (Sleep / Shutdown)
    """

    @staticmethod
    def format_template(template: str, context: Dict[str, str]) -> str:
        result = template
        for key, val in context.items():
            result = result.replace(f"{{{key}}}", str(val))
        return result

    @staticmethod
    def send_os_notification(
        title: str,
        body: str,
        tray_icon: Optional[QSystemTrayIcon] = None,
    ) -> None:
        # Prefer QSystemTrayIcon balloon/notification when available so clicking the notification
        # triggers QSystemTrayIcon.messageClicked -> opens DMAN with pre-staged links immediately.
        if tray_icon is not None and tray_icon.isVisible() and tray_icon.supportsMessages():
            tray_icon.showMessage(title, body, QSystemTrayIcon.Information, 5000)
            return

        if sys.platform.startswith("linux"):
            notify_bin = shutil.which("notify-send")
            if notify_bin:
                try:
                    subprocess.Popen(
                        [notify_bin, "-a", "DMAN", title, body],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )
                except Exception:
                    pass

    @staticmethod
    def open_url_safe(url_str: str) -> None:
        """Opens a web URL in the user's browser without triggering x-www-browser errors on Wayland."""
        from PySide6.QtCore import QUrl
        from PySide6.QtGui import QDesktopServices

        if sys.platform.startswith("linux"):
            for candidate in ("xdg-open", "firefox", "google-chrome-stable", "chromium", "brave"):
                bin_path = shutil.which(candidate)
                if bin_path:
                    try:
                        subprocess.Popen(
                            [bin_path, url_str],
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                        )
                        return
                    except Exception:
                        pass
        QDesktopServices.openUrl(QUrl(url_str))

    @staticmethod
    def get_disk_free_bytes(folder_path: str) -> int:
        try:
            target = Path(folder_path.strip() or Path.home())
            while not target.exists() and target.parent != target:
                target = target.parent
            usage = shutil.disk_usage(str(target))
            return int(usage.free)
        except Exception:
            return 0

    @staticmethod
    def set_autostart(enabled: bool) -> None:
        main_script = Path(__file__).resolve().parent.parent / "main.py"
        python_exe = sys.executable

        if sys.platform.startswith("linux"):
            autostart_dir = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "autostart"
            desktop_file = autostart_dir / "dman.desktop"
            if enabled:
                autostart_dir.mkdir(parents=True, exist_ok=True)
                icon_path = "/mnt/storage/LINUX-WIN/مستودع/download.png"
                content = (
                    "[Desktop Entry]\n"
                    "Type=Application\n"
                    "Name=DMAN Download Manager\n"
                    f'Exec="{python_exe}" "{main_script}" --autostart\n'
                    f'Icon={icon_path}\n'
                    "Terminal=false\n"
                    "Categories=Network;FileTransfer;\n"
                )
                try:
                    desktop_file.write_text(content, encoding="utf-8")
                except Exception:
                    pass
            else:
                try:
                    if desktop_file.exists():
                        desktop_file.unlink()
                except Exception:
                    pass

        elif sys.platform == "win32":
            try:
                import winreg

                key_path = r"Software\Microsoft\Windows\CurrentVersion\Run"
                with winreg.OpenKey(winreg.HKEY_CURRENT_USER, key_path, 0, winreg.KEY_SET_VALUE) as reg_key:
                    if enabled:
                        cmd = f'"{python_exe}" "{main_script}" --autostart'
                        winreg.SetValueEx(reg_key, "DMAN", 0, winreg.REG_SZ, cmd)
                    else:
                        try:
                            winreg.DeleteValue(reg_key, "DMAN")
                        except FileNotFoundError:
                            pass
            except Exception:
                pass

    @staticmethod
    def execute_power_action(action: str) -> None:
        action = action.lower().strip()
        if action == "sleep":
            if sys.platform.startswith("linux"):
                subprocess.Popen(["systemctl", "suspend"])
            elif sys.platform == "win32":
                subprocess.Popen(["rundll32.exe", "powrprof.dll,SetSuspendState", "0,1,0"])
        elif action == "shutdown":
            if sys.platform.startswith("linux"):
                subprocess.Popen(["systemctl", "poweroff"])
            elif sys.platform == "win32":
                subprocess.Popen(["shutdown", "/s", "/t", "5"])
