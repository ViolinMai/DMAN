import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."
import "components"

ApplicationWindow {
    id: window
    visible: true
    width: 1120
    height: 680
    minimumWidth: 640
    minimumHeight: 400
    title: "DMAN - aria2 Download Manager"
    color: Theme.bgPrimary

    required property var appController

    function toggleFullscreen() {
        if (window.visibility === Window.FullScreen) {
            window.showNormal()
        } else {
            window.showFullScreen()
        }
    }

    Shortcut {
        sequence: "F"
        enabled: !window.activeFocusItem || !(window.activeFocusItem instanceof TextInput || window.activeFocusItem instanceof TextEdit)
        onActivated: window.toggleFullscreen()
    }

    onClosing: function(close) {
        if (window.appController.closeToTray) {
            close.accepted = false
            window.hide()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        TopBar {
            Layout.fillWidth: true
            controller: window.appController
            onOpenAddLinksRequested: addLinkModal.openWithFocus()
            onOpenSettingsRequested: settingsModal.openSettings()
        }

        DownloadTable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            controller: window.appController
        }

        BottomPanel {
            Layout.fillWidth: true
            controller: window.appController
            onOpenAddLinksRequested: addLinkModal.openWithFocus()
        }
    }

    AddLinkDialog {
        id: addLinkModal
        controller: window.appController
    }

    SettingsDialog {
        id: settingsModal
        controller: window.appController
    }

    // Toast notification banner
    Rectangle {
        id: toastBanner
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 45
        anchors.horizontalCenter: parent.horizontalCenter
        width: toastText.implicitWidth + 28
        height: 30
        radius: Theme.radiusMedium
        color: isErrorToast ? Theme.statusError : Theme.bgHeader
        border.color: Theme.borderFocus
        border.width: 1
        visible: opacity > 0
        opacity: 0.0

        property bool isErrorToast: false

        Text {
            id: toastText
            anchors.centerIn: parent
            color: Theme.textPrimary
            font.pixelSize: Theme.fontSizeNormal
        }

        Timer {
            id: toastTimer
            interval: 3000
            onTriggered: toastBanner.opacity = 0.0
        }

        Behavior on opacity {
            NumberAnimation { duration: 180 }
        }
    }

    Connections {
        target: window.appController
        function onNotificationEmitted(message, isError) {
            toastText.text = message
            toastBanner.isErrorToast = isError
            toastBanner.opacity = 1.0
            toastTimer.restart()
        }
        function onClipboardLinksDetected(linksText, count) {
            window.show()
            window.raise()
            window.requestActivate()
            addLinkModal.openWithFocus(linksText)
        }
        function onRequestShowMainWindow() {
            if (window. visible) {
                window.hide()
            } else {
                window.show()
                window.raise()
                window.requestActivate()
            }
        }
    }
}
