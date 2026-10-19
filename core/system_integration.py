import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Dict

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
        tray_icon: QSystemTrayIcon = None,
    ) -> None:
        if sys.platform.startswith("linux"):
            notify_bin = shutil.which("notify-send")
            if notify_bin:
                try:
                    subprocess.Popen(
                        [notify_bin, "-a", "DMAN", title, body],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )
                    return
                except Exception:
                    pass

        if tray_icon is not None and tray_icon.isVisible():
            tray_icon.showMessage(title, body, QSystemTrayIcon.Information, 4000)

    @staticmethod
    def set_autostart(enabled: bool) -> None:
        main_script = Path(__file__).resolve().parent.parent / "main.py"
        python_exe = sys.executable

        if sys.platform.startswith("linux"):
            autostart_dir = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "autostart"
            desktop_file = autostart_dir / "dman.desktop"
            if enabled:
                autostart_dir.mkdir(parents=True, exist_ok=True)
                content = (
                    "[Desktop Entry]\n"
                    "Type=Application\n"
                    "Name=DMAN Download Manager\n"
                    f'Exec="{python_exe}" "{main_script}" --autostart\n'
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
