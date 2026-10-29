import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Popup {
    id: root
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    anchors.centerIn: Overlay.overlay
    width: Math.min(680, parent ? parent.width - 40 : 680)
    height: 540
    padding: 0

    required property var controller

    property int currentTab: 0
    property string pinCodeDisplay: ""
    property string pinUrlDisplay: ""
    property string selectedPostAction: "nothing"
    property string selectedClipboardMode: "all"

    function openSettings() {
        defaultDirField.text = root.controller.defaultSaveDir
        concurrentSpin.value = root.controller.maxConcurrentDownloads
        splitSpin.value = root.controller.splitCount
        connPerServerSpin.value = root.controller.maxConnectionPerServer
        minSplitField.text = root.controller.minSplitSize
        speedLimitSpin.value = root.controller.speedLimitMb

        adEnabledCheck.checked = root.controller.alldebridEnabled
        adApiKeyField.text = root.controller.alldebridApiKey
        adCloudMagnetCheck.checked = root.controller.alldebridCloudMagnets

        startSysCheck.checked = root.controller.startWithSystem
        startMinCheck.checked = root.controller.startMinimized
        closeTrayCheck.checked = root.controller.closeToTray
        root.selectedPostAction = root.controller.postDownloadAction

        root.selectedClipboardMode = root.controller.clipboardMode
        clipAutoPopupCheck.checked = root.controller.clipboardAutoPopup

        notifCompleteCheck.checked = root.controller.notifyOnComplete
        notifErrorCheck.checked = root.controller.notifyOnError
        notifClipCheck.checked = root.controller.notifyOnClipboard
        notifTitleField.text = root.controller.notifyTitleTemplate
        notifCompleteField.text = root.controller.notifyCompleteTemplate
        notifErrorField.text = root.controller.notifyErrorTemplate
        notifClipField.text = root.controller.notifyClipboardTemplate

        root.pinCodeDisplay = ""
        root.pinUrlDisplay = ""
        root.controller.refreshDebugLogs()
        root.open()
    }

    Connections {
        target: root.controller
        function onPinDataReady(pin, url, expiresIn) {
            root.pinCodeDisplay = pin
            root.pinUrlDisplay = url
        }
        function onSettingsChanged() {
            if (root.visible) {
                adApiKeyField.text = root.controller.alldebridApiKey
                adEnabledCheck.checked = root.controller.alldebridEnabled
            }
        }
    }

    background: Rectangle {
        color: Theme.bgPanel
        radius: Theme.radiusMedium
        border.color: Theme.borderFocus
        border.width: 1
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        // Dialog Header + Tab Selector
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "DMAN Preferences"
                color: Theme.textPrimary
                font.pixelSize: 15
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            Repeater {
                model: [
                    "1. Engine & AllDebrid",
                    "2. System & Watchdog",
                    "3. Notifications",
                    "4. Logs & Debugging"
                ]

                delegate: Rectangle {
                    implicitWidth: tabLbl.implicitWidth + 18
                    implicitHeight: 28
                    radius: Theme.radiusSmall
                    color: root.currentTab === index ? Theme.rowSelected : Theme.bgHeader
                    border.color: root.currentTab === index ? Theme.borderFocus : Theme.borderSubtle

                    Text {
                        id: tabLbl
                        anchors.centerIn: parent
                        text: modelData
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSizeNormal
                        font.bold: root.currentTab === index
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.currentTab = index
                    }
                }
            }
        }

        // TAB 0: Engine & AllDebrid
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 0
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: dirCol.implicitHeight + 16
                color: Theme.bgSecondary
                radius: Theme.radiusSmall
                border.color: Theme.borderSubtle

                ColumnLayout {
                    id: dirCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    Text {
                        text: "Default Download Directory"
                        color: Theme.accentBlue
                        font.pixelSize: Theme.fontSizeNormal
                        font.bold: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        TextField {
                            id: defaultDirField
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeNormal
                            selectByMouse: true
                            leftPadding: 8
                            rightPadding: 8
                            background: Rectangle {
                                color: Theme.bgInput
                                radius: Theme.radiusSmall
                                border.color: Theme.borderSubtle
                            }
                        }

                        Rectangle {
                            implicitWidth: 85
                            implicitHeight: 28
                            radius: Theme.radiusSmall
                            color: Theme.bgHeader
                            border.color: Theme.borderSubtle

                            Text {
                                anchors.centerIn: parent
                                text: "Browse..."
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeNormal
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var folder = root.controller.browseFolder(defaultDirField.text)
                                    if (folder !== "") defaultDirField.text = folder
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: ariaCol.implicitHeight + 16
                color: Theme.bgSecondary
                radius: Theme.radiusSmall
                border.color: Theme.borderSubtle

                ColumnLayout {
                    id: ariaCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    Text {
                        text: "aria2 Engine Tuning (Live Applied & Resumable Sessions)"
                        color: Theme.accentBlue
                        font.pixelSize: Theme.fontSizeNormal
                        font.bold: true
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 4
                        rowSpacing: 8
                        columnSpacing: 12

                        Text { text: "Max Concurrent Files:"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeNormal }
                        SpinBox { id: concurrentSpin; from: 1; to: 32; value: 5; editable: true }

                        Text { text: "Segments per File (Split):"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeNormal }
                        SpinBox { id: splitSpin; from: 1; to: 64; value: 16; editable: true }

                        Text { text: "Max Conn. per Server:"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeNormal }
                        SpinBox { id: connPerServerSpin; from: 1; to: 16; value: 16; editable: true }

                        Text { text: "Min Split Size (1M, 5M):"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeNormal }
                        TextField {
                            id: minSplitField
                            Layout.preferredWidth: 100
                            Layout.preferredHeight: 26
                            text: "1M"
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeNormal
                            leftPadding: 8
                            background: Rectangle { color: Theme.bgInput; radius: Theme.radiusSmall; border.color: Theme.borderSubtle }
                        }

                        Text { text: "Speed Limit (MB/s, 0=Unlim):"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeNormal }
                        SpinBox { id: speedLimitSpin; from: 0; to: 2000; value: 0; editable: true }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.bgSecondary
                radius: Theme.radiusSmall
                border.color: Theme.borderSubtle

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "AllDebrid API v4 / v4.1 (Supports Links, Magnets & .torrent Files)"
                            color: Theme.statusActive
                            font.pixelSize: Theme.fontSizeNormal
                            font.bold: true
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "Status: " + root.controller.alldebridStatusText
                            color: root.controller.alldebridIsPremium ? Theme.statusActive : Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }
                    }

                    RowLayout {
                        spacing: 16
                        CheckBox {
                            id: adEnabledCheck
                            text: "Enable AllDebrid Unrestricting"
                            contentItem: Text {
                                text: adEnabledCheck.text
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeNormal
                                leftPadding: adEnabledCheck.indicator.width + 6
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                        CheckBox {
                            id: adCloudMagnetCheck
                            text: "Convert Magnets & .torrent via Cloud"
                            contentItem: Text {
                                text: adCloudMagnetCheck.text
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeNormal
                                leftPadding: adCloudMagnetCheck.indicator.width + 6
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text { text: "API Key:"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeNormal }

                        TextField {
                            id: adApiKeyField
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            placeholderText: "Bearer API Key or click 'Login via PIN'"
                            placeholderTextColor: Theme.textMuted
                            echoMode: TextInput.Password
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeNormal
                            leftPadding: 8
                            background: Rectangle { color: Theme.bgInput; radius: Theme.radiusSmall; border.color: Theme.borderSubtle }
                        }

                        Rectangle {
                            implicitWidth: 115
                            implicitHeight: 28
                            radius: Theme.radiusSmall
                            color: Theme.bgHeader
                            border.color: Theme.borderFocus

                            Text {
                                anchors.centerIn: parent
                                text: "Login via PIN"
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.controller.startAllDebridPinAuth()
                            }
                        }
                    }

                    Text {
                        visible: root.pinCodeDisplay !== ""
                        text: "PIN: [" + root.pinCodeDisplay + "] — Approve in browser (" + root.pinUrlDisplay + ")"
                        color: Theme.statusPaused
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                    }
                }
            }
        }

        // TAB 1: System Integration, Tray, Power & Clipboard Watchdog
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 1
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: sysCol.implicitHeight + 16
                color: Theme.bgSecondary
                radius: Theme.radiusSmall
                border.color: Theme.borderSubtle

                ColumnLayout {
                    id: sysCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    Text {
                        text: "Desktop & System Tray Integration (Hyprland Wayland & Windows)"
                        color: Theme.accentBlue
                        font.pixelSize: Theme.fontSizeNormal
                        font.bold: true
                    }

                    CheckBox {
                        id: startSysCheck
                        text: "Start DMAN automatically with system login"
                        contentItem: Text {
                            text: startSysCheck.text
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeNormal
                            leftPadding: startSysCheck.indicator.width + 6
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    CheckBox {
                        id: startMinCheck
                        text: "Start minimized in System Tray"
                        contentItem: Text {
                            text: startMinCheck.text
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeNormal
                            leftPadding: startMinCheck.indicator.width + 6
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    CheckBox {
                        id: closeTrayCheck
                        text: "Closing the window places DMAN in System Tray (Keep downloads running)"
                        contentItem: Text {
                            text: closeTrayCheck.text
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeNormal
                            leftPadding: closeTrayCheck.indicator.width + 6
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    RowLayout {
                        spacing: 10
                        Text {
                            text: "When all downloads finish:"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeNormal
                        }

                        Repeater {
                            model: [
                                { label: "Do Nothing", value: "nothing" },
                                { label: "Sleep System", value: "sleep" },
                                { label: "Shutdown System", value: "shutdown" },
                                { label: "Quit DMAN", value: "quit" }
                            ]

                            delegate: Rectangle {
                                implicitWidth: pwrTxt.implicitWidth + 14
                                implicitHeight: 24
                                radius: Theme.radiusSmall
                                color: root.selectedPostAction === modelData.value ? Theme.rowSelected : Theme.bgHeader
                                border.color: root.selectedPostAction === modelData.value ? Theme.borderFocus : Theme.borderSubtle

                                Text {
                                    id: pwrTxt
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.selectedPostAction = modelData.value
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: clipCol.implicitHeight + 16
                color: Theme.bgSecondary
                radius: Theme.radiusSmall
                border.color: Theme.borderSubtle

                ColumnLayout {
                    id: clipCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    Text {
                        text: "Clipboard Watchdog (Auto-Capture Copied Links)"
                        color: Theme.statusActive
                        font.pixelSize: Theme.fontSizeNormal
                        font.bold: true
                    }

                    RowLayout {
                        spacing: 8
                        Text {
                            text: "Watchdog Mode:"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeNormal
                        }

                        Repeater {
                            model: [
                                { label: "Disabled", value: "disabled" },
                                { label: "All Download Links", value: "all" },
                                { label: "AllDebrid Supported Only", value: "alldebrid_only" }
                            ]

                            delegate: Rectangle {
                                implicitWidth: cmTxt.implicitWidth + 14
                                implicitHeight: 24
                                radius: Theme.radiusSmall
                                color: root.selectedClipboardMode === modelData.value ? Theme.rowSelected : Theme.bgHeader
                                border.color: root.selectedClipboardMode === modelData.value ? Theme.borderFocus : Theme.borderSubtle

                                Text {
                                    id: cmTxt
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.selectedClipboardMode = modelData.value
                                }
                            }
                        }
                    }

                    CheckBox {
                        id: clipAutoPopupCheck
                        text: "Automatically open 'Add Links' dialog when links are captured"
                        contentItem: Text {
                            text: clipAutoPopupCheck.text
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeNormal
                            leftPadding: clipAutoPopupCheck.indicator.width + 6
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }

            // App Lifecycle Control Box
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.bgSecondary
                radius: Theme.radiusSmall
                border.color: Theme.borderSubtle

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    Text {
                        text: "Application Control (Saves aria2 session before exit):"
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeNormal
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        implicitWidth: 120
                        implicitHeight: 28
                        radius: Theme.radiusSmall
                        color: Theme.bgHeader
                        border.color: Theme.statusPaused

                        Text {
                            anchors.centerIn: parent
                            text: "↻ Restart App"
                            color: Theme.statusPaused
                            font.pixelSize: Theme.fontSizeNormal
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.controller.restartApp()
                        }
                    }

                    Rectangle {
                        implicitWidth: 130
                        implicitHeight: 28
                        radius: Theme.radiusSmall
                        color: Theme.bgHeader
                        border.color: Theme.statusError

                        Text {
                            anchors.centerIn: parent
                            text: "⏻ Shutdown App"
                            color: Theme.statusError
                            font.pixelSize: Theme.fontSizeNormal
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.controller.shutdownApp()
                        }
                    }
                }
            }
        }

        // TAB 2: Notifications Customization
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 2
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.bgSecondary
                radius: Theme.radiusSmall
                border.color: Theme.borderSubtle

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    Text {
                        text: "OS Notification Triggers & Custom Message Templates"
                        color: Theme.accentBlue
                        font.pixelSize: Theme.fontSizeNormal
                        font.bold: true
                    }

                    RowLayout {
                        spacing: 16
                        CheckBox {
                            id: notifCompleteCheck
                            text: "On Download Complete"
                            contentItem: Text {
                                text: notifCompleteCheck.text
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeNormal
                                leftPadding: notifCompleteCheck.indicator.width + 6
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                        CheckBox {
                            id: notifErrorCheck
                            text: "On Download Error"
                            contentItem: Text {
                                text: notifErrorCheck.text
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeNormal
                                leftPadding: notifErrorCheck.indicator.width + 6
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                        CheckBox {
                            id: notifClipCheck
                            text: "On Clipboard Link Captured"
                            contentItem: Text {
                                text: notifClipCheck.text
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeNormal
                                leftPadding: notifClipCheck.indicator.width + 6
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    Text {
                        text: "Available Variables: {event}, {name}, {dir}, {count}, {error}"
                        color: Theme.textMuted
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: 8
                        columnSpacing: 10

                        Text { text: "Notification Title:"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeNormal }
                        TextField {
                            id: notifTitleField
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeNormal
                            leftPadding: 8
                            background: Rectangle { color: Theme.bgInput; radius: Theme.radiusSmall; border.color: Theme.borderSubtle }
                        }

                        Text { text: "Complete Body:"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeNormal }
                        TextField {
                            id: notifCompleteField
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeNormal
                            leftPadding: 8
                            background: Rectangle { color: Theme.bgInput; radius: Theme.radiusSmall; border.color: Theme.borderSubtle }
                        }

                        Text { text: "Error Body:"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeNormal }
                        TextField {
                            id: notifErrorField
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeNormal
                            leftPadding: 8
                            background: Rectangle { color: Theme.bgInput; radius: Theme.radiusSmall; border.color: Theme.borderSubtle }
                        }

                        Text { text: "Clipboard Body:"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeNormal }
                        TextField {
                            id: notifClipField
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeNormal
                            leftPadding: 8
                            background: Rectangle { color: Theme.bgInput; radius: Theme.radiusSmall; border.color: Theme.borderSubtle }
                        }
                    }

                    Rectangle {
                        implicitWidth: 160
                        implicitHeight: 28
                        radius: Theme.radiusSmall
                        color: Theme.bgHeader
                        border.color: Theme.borderFocus

                        Text {
                            anchors.centerIn: parent
                            text: "Send Test Notification"
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.controller.testCustomNotification()
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }

        // TAB 3: Logs & Debugging
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 3
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Live Application & API Debug Logs"
                    color: Theme.accentBlue
                    font.pixelSize: Theme.fontSizeNormal
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: 90
                    implicitHeight: 26
                    radius: Theme.radiusSmall
                    color: Theme.bgHeader
                    border.color: Theme.borderSubtle

                    Text {
                        anchors.centerIn: parent
                        text: "↻ Refresh"
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.controller.refreshDebugLogs()
                    }
                }

                Rectangle {
                    implicitWidth: 80
                    implicitHeight: 26
                    radius: Theme.radiusSmall
                    color: Theme.bgHeader
                    border.color: Theme.borderSubtle

                    Text {
                        anchors.centerIn: parent
                        text: "Clear"
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.controller.clearDebugLogs()
                    }
                }

                Rectangle {
                    implicitWidth: 120
                    implicitHeight: 26
                    radius: Theme.radiusSmall
                    color: Theme.bgHeader
                    border.color: Theme.borderFocus

                    Text {
                        anchors.centerIn: parent
                        text: "Copy All Logs"
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.controller.copyLogsToClipboard(debugLogArea.text)
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.bgInput
                radius: Theme.radiusSmall
                border.color: Theme.borderSubtle

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 6

                    TextArea {
                        id: debugLogArea
                        readOnly: true
                        selectByMouse: true
                        text: root.controller.debugLogsText
                        color: Theme.textPrimary
                        font.family: "monospace"
                        font.pixelSize: 11
                        wrapMode: TextEdit.WrapAnywhere
                        background: null
                    }
                }
            }
        }

        // Bottom Save & Cancel Row
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Item { Layout.fillWidth: true }

            Rectangle {
                implicitWidth: 90
                implicitHeight: 30
                radius: Theme.radiusSmall
                color: Theme.bgHeader
                border.color: Theme.borderSubtle

                Text {
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeNormal
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.close()
                }
            }

            Rectangle {
                implicitWidth: 135
                implicitHeight: 30
                radius: Theme.radiusSmall
                color: Theme.accentBlue

                Text {
                    anchors.centerIn: parent
                    text: "Save & Apply"
                    color: "#FFFFFF"
                    font.pixelSize: Theme.fontSizeNormal
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.controller.saveSettings({
                            "defaultSaveDir": defaultDirField.text,
                            "maxConcurrentDownloads": concurrentSpin.value,
                            "splitCount": splitSpin.value,
                            "maxConnectionPerServer": connPerServerSpin.value,
                            "minSplitSize": minSplitField.text,
                            "speedLimitMb": speedLimitSpin.value,
                            "alldebridEnabled": adEnabledCheck.checked,
                            "alldebridApiKey": adApiKeyField.text,
                            "alldebridCloudMagnets": adCloudMagnetCheck.checked,
                            "startWithSystem": startSysCheck.checked,
                            "startMinimized": startMinCheck.checked,
                            "closeToTray": closeTrayCheck.checked,
                            "postDownloadAction": root.selectedPostAction,
                            "clipboardMode": root.selectedClipboardMode,
                            "clipboardAutoPopup": clipAutoPopupCheck.checked,
                            "notifyOnComplete": notifCompleteCheck.checked,
                            "notifyOnError": notifErrorCheck.checked,
                            "notifyOnClipboard": notifClipCheck.checked,
                            "notifyTitleTemplate": notifTitleField.text,
                            "notifyCompleteTemplate": notifCompleteField.text,
                            "notifyErrorTemplate": notifErrorField.text,
                            "notifyClipboardTemplate": notifClipField.text
                        })
                        root.close()
                    }
                }
            }
        }
    }
}
