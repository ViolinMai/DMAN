import os
import sys
from pathlib import Path

from PySide6.QtCore import Qt, QUrl
from PySide6.QtGui import QAction, QColor, QIcon, QPainter, QPixmap
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle
from PySide6.QtWidgets import QApplication, QMenu, QSystemTrayIcon

from controllers.app_controller import AppController
from core.config import AppConfig


def configure_environment() -> None:
    QQuickStyle.setStyle("Basic")
    os.environ.setdefault("QT_LOGGING_RULES", "qt.qpa.wayland.textinput=false")

    if sys.platform.startswith("linux"):
        if "WAYLAND_DISPLAY" in os.environ and "QT_QPA_PLATFORM" not in os.environ:
            os.environ["QT_QPA_PLATFORM"] = "wayland;xcb"


def create_dman_tray_icon() -> QIcon:
    pixmap = QPixmap(64, 64)
    pixmap.fill(Qt.transparent)
    painter = QPainter(pixmap)
    painter.setRenderHint(QPainter.Antialiasing)
    painter.setBrush(QColor("#2B4257"))
    painter.setPen(QColor("#5B9BD5"))
    painter.drawRoundedRect(4, 4, 56, 56, 12, 12)
    painter.setPen(QColor("#6CC644"))
    font = painter.font()
    font.setPixelSize(34)
    font.setBold(True)
    painter.setFont(font)
    painter.drawText(pixmap.rect(), Qt.AlignCenter, "⬇")
    painter.end()
    return QIcon(pixmap)


def setup_system_tray(app: QApplication, controller: AppController) -> QSystemTrayIcon:
    tray = QSystemTrayIcon(create_dman_tray_icon(), app)
    tray.setToolTip("DMAN - aria2 & AllDebrid Download Manager")

    menu = QMenu()
    act_toggle = QAction("Show / Hide DMAN", menu)
    act_toggle.triggered.connect(controller.requestShowMainWindow.emit)

    act_resume_all = QAction("Resume All", menu)
    act_resume_all.triggered.connect(controller.resumeAll)

    act_pause_all = QAction("Pause All", menu)
    act_pause_all.triggered.connect(controller.pauseAll)

    act_restart = QAction("Restart App", menu)
    act_restart.triggered.connect(controller.restartApp)

    act_quit = QAction("Shutdown App", menu)
    act_quit.triggered.connect(controller.shutdownApp)

    menu.addAction(act_toggle)
    menu.addSeparator()
    menu.addAction(act_resume_all)
    menu.addAction(act_pause_all)
    menu.addSeparator()
    menu.addAction(act_restart)
    menu.addAction(act_quit)

    tray.setContextMenu(menu)
    tray.activated.connect(
        lambda reason: controller.requestShowMainWindow.emit()
        if reason in (QSystemTrayIcon.Trigger, QSystemTrayIcon.DoubleClick)
        else None
    )
    tray.show()
    controller.set_tray_icon(tray)
    return tray


def main() -> int:
    # Route to headless CLI mode if invoked with 'cli' subcommand or CLI flags
    if len(sys.argv) > 1 and sys.argv[1] == "cli":
        from cli.cli_runner import run_cli
        return run_cli(sys.argv[2:])

    from cli.logger import setup_cli_logging
    setup_cli_logging(debug=True)

    configure_environment()

    app = QApplication(sys.argv)
    app.setApplicationName(AppConfig.APP_NAME)
    app.setApplicationVersion(AppConfig.APP_VERSION)
    app.setQuitOnLastWindowClosed(False)

    controller = AppController()
    tray = setup_system_tray(app, controller)
    app.aboutToQuit.connect(controller.shutdown)

    engine = QQmlApplicationEngine()
    base_dir = Path(__file__).resolve().parent
    ui_dir = base_dir / "ui"

    engine.addImportPath(str(ui_dir))
    engine.setInitialProperties({"appController": controller})

    qml_file = ui_dir / "Main.qml"
    engine.load(QUrl.fromLocalFile(str(qml_file)))

    if not engine.rootObjects():
        tray.hide()
        controller.shutdown()
        return 1

    root_win = engine.rootObjects()[0]
    if controller.startMinimized or "--autostart" in sys.argv:
        root_win.hide()

    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
