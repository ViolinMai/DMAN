import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import ".."

Window {
    id: root
    title: "DMAN - Settings & Configuration"
    width: 820
    height: 580
    minimumWidth: 720
    minimumHeight: 500
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowSystemMenuHint | Qt.WindowMinMaxButtonsHint | Qt.WindowCloseButtonHint
    modality: Qt.NonModal
    visible: false
    color: Theme.bgPrimary

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
        notifPackageOnlyCheck.checked = root.controller.notifyPackageOnly
        notifErrorCheck.checked = root.controller.notifyOnError
        notifClipCheck.checked = root.controller.notifyOnClipboard
        notifTitleField.text = root.controller.notifyTitleTemplate
        notifCompleteField.text = root.controller.notifyCompleteTemplate
        notifPackageField.text = root.controller.notifyPackageTemplate
        notifErrorField.text = root.controller.notifyErrorTemplate
        notifClipField.text = root.controller.notifyClipboardTemplate

        root.pinCodeDisplay = ""
        root.pinUrlDisplay = ""
        root.controller.refreshDebugLogs()
        root.show()
        root.raise()
        root.requestActivate()
    }

    Shortcut {
        sequence: "Escape"
        onActivated: root.close()
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

    component SectionCard: Rectangle {
        default property alias cardContent: innerCol.data
        property string cardTitle: ""
        property color titleColor: Theme.accentBlue
        Layout.fillWidth: true
        implicitHeight: innerCol.implicitHeight + 28
        color: Theme.bgSecondary
        radius: Theme.radiusMedium
        border.color: Theme.borderSubtle
        border.width: 1

        ColumnLayout {
            id: innerCol
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            Text {
                visible: cardTitle !== ""
                text: cardTitle
                color: titleColor
                font.pixelSize: 13
                font.bold: true
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // LEFT NAVIGATION SIDEBAR
        Rectangle {
            Layout.preferredWidth: 210
            Layout.fillHeight: true
            color: Theme.bgSecondary
            border.color: Theme.borderSubtle
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 6

                Text {
                    text: "⚙ Preferences"
                    color: Theme.textPrimary
                    font.pixelSize: 16
                    font.bold: true
                    Layout.bottomMargin: 10
                }

                Repeater {
                    model: [
                        { title: "Engine & Storage", icon: "🚀" },
                        { title: "AllDebrid Cloud", icon: "⚡" },
                        { title: "System & Watchdog", icon: "🖥" },
                        { title: "Notifications", icon: "🔔" },
                        { title: "Logs & Debugging", icon: "🐞" }
                    ]

                    delegate: Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 36
                        radius: Theme.radiusSmall
                        readonly property bool isCurrent: root.currentTab === index
                        color: isCurrent ? Theme.rowSelected : (navMouse.containsMouse ? Theme.rowHover : "transparent")
                        border.color: isCurrent ? Theme.borderFocus : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 10
                            spacing: 10

                            Text {
                                text: modelData.icon
                                font.pixelSize: 14
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData.title
                                color: isCurrent ? "#FFFFFF" : Theme.textSecondary
                                font.pixelSize: Theme.fontSizeNormal
                                font.bold: isCurrent
                            }
                        }

                        MouseArea {
                            id: navMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.currentTab = index
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                // App Lifecycle Controls at bottom of sidebar
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: Theme.radiusSmall
                    color: Theme.bgHeader
                    border.color: Theme.statusPaused

                    Text {
                        anchors.centerIn: parent
                        text: "↻ Restart DMAN"
                        color: Theme.statusPaused
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.controller.restartApp()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: Theme.radiusSmall
                    color: Theme.bgHeader
                    border.color: Theme.statusError

                    Text {
                        anchors.centerIn: parent
                        text: "⏻ Quit & Shutdown"
                        color: Theme.statusError
                        font.pixelSize: Theme.fontSizeSmall
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

        // RIGHT CONTENT AREA
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Content Pages Container
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 18

                // PAGE 0: Engine & Storage
                ColumnLayout {
                    anchors.fill: parent
                    visible: root.currentTab === 0
                    spacing: 14

                    SectionCard {
                        cardTitle: "Default Download Storage"

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            TextField {
                                id: defaultDirField
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeNormal
                                selectByMouse: true
                                leftPadding: 10
                                background: Rectangle {
                                    color: Theme.bgInput
                                    radius: Theme.radiusSmall
                                    border.color: defaultDirField.activeFocus ? Theme.borderFocus : Theme.borderSubtle
                                }
                            }

                            Rectangle {
                                implicitWidth: 95
                                implicitHeight: 32
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

                    SectionCard {
                        cardTitle: "aria2 High-Speed Engine Tuning (Applied Live)"

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            rowSpacing: 12
                            columnSpacing: 20

                            Text { text: "Max Concurrent Downloads:"; color: Theme.textPrimary; font.pixelSize: Theme.fontSizeNormal }
                            SpinBox { id: concurrentSpin; from: 1; to: 32; value: 5; editable: true }

                            Text { text: "Connections / Split per File (1 - 64):"; color: Theme.textPrimary; font.pixelSize: Theme.fontSizeNormal }
                            SpinBox { id: splitSpin; from: 1; to: 64; value: 16; editable: true }

                            Text { text: "Max Connections per Server (1 - 16):"; color: Theme.textPrimary; font.pixelSize: Theme.fontSizeNormal }
                            SpinBox { id: connPerServerSpin; from: 1; to: 16; value: 16; editable: true }

                            Text { text: "Minimum Split Size (e.g. 1M, 5M):"; color: Theme.textPrimary; font.pixelSize: Theme.fontSizeNormal }
                            TextField {
                                id: minSplitField
                                Layout.preferredWidth: 120
                                Layout.preferredHeight: 28
                                text: "1M"
                                color: Theme.textPrimary
                                leftPadding: 8
                                background: Rectangle { color: Theme.bgInput; radius: Theme.radiusSmall; border.color: Theme.borderSubtle }
                            }

                            Text { text: "Global Speed Limit (MB/s, 0 = Unlimited):"; color: Theme.textPrimary; font.pixelSize: Theme.fontSizeNormal }
                            SpinBox { id: speedLimitSpin; from: 0; to: 2000; value: 0; editable: true }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                // PAGE 1: AllDebrid Cloud
                ColumnLayout {
                    anchors.fill: parent
                    visible: root.currentTab === 1
                    spacing: 14

                    SectionCard {
                        cardTitle: "AllDebrid Account & Unrestricting"
                        titleColor: Theme.statusActive

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Account Status: " + root.controller.alldebridStatusText
                                color: root.controller.alldebridIsPremium ? Theme.statusActive : Theme.textSecondary
                                font.pixelSize: 13
                                font.bold: true
                            }
                            Item { Layout.fillWidth: true }
                        }

                        CheckBox {
                            id: adEnabledCheck
                            text: "Enable AllDebrid Link Unrestricting & Fast-Track CDN"
                            contentItem: Text {
                                text: adEnabledCheck.text
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeNormal
                                leftPadding: adEnabledCheck.indicator.width + 8
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        CheckBox {
                            id: adCloudMagnetCheck
                            text: "Convert Magnets & .torrent files via AllDebrid Cloud"
                            contentItem: Text {
                                text: adCloudMagnetCheck.text
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeNormal
                                leftPadding: adCloudMagnetCheck.indicator.width + 8
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text { text: "Bearer API Key:"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeNormal }

                            TextField {
                                id: adApiKeyField
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                placeholderText: "Paste API Key or use 'Login via PIN'"
                                placeholderTextColor: Theme.textMuted
                                echoMode: TextInput.Password
                                color: Theme.textPrimary
                                leftPadding: 10
                                background: Rectangle { color: Theme.bgInput; radius: Theme.radiusSmall; border.color: Theme.borderSubtle }
                            }

                            Rectangle {
                                implicitWidth: 125
                                implicitHeight: 32
                                radius: Theme.radiusSmall
                                color: Theme.bgHeader
                                border.color: Theme.borderFocus

                                Text {
                                    anchors.centerIn: parent
                                    text: "🔑 Login via PIN"
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
                            text: "PIN Code: [" + root.pinCodeDisplay + "] — Opened in browser: " + root.pinUrlDisplay
                            color: Theme.statusPaused
                            font.pixelSize: Theme.fontSizeNormal
                            font.bold: true
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                // PAGE 2: System & Watchdog
                ColumnLayout {
                    anchors.fill: parent
                    visible: root.currentTab === 2
                    spacing: 14

                    SectionCard {
                        cardTitle: "Desktop Integration & Power Management"

                        CheckBox {
                            id: startSysCheck
                            text: "Start DMAN automatically on system login"
                            contentItem: Text {
                                text: startSysCheck.text
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeNormal
                                leftPadding: startSysCheck.indicator.width + 8
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
                                leftPadding: startMinCheck.indicator.width + 8
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        CheckBox {
                            id: closeTrayCheck
                            text: "Closing main window hides DMAN to System Tray (keeps downloads active)"
                            contentItem: Text {
                                text: closeTrayCheck.text
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeNormal
                                leftPadding: closeTrayCheck.indicator.width + 8
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        RowLayout {
                            spacing: 8
                            Text { text: "When all downloads finish:"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeNormal }

                            Repeater {
                                model: [
                                    { label: "Do Nothing", value: "nothing" },
                                    { label: "Sleep OS", value: "sleep" },
                                    { label: "Shutdown OS", value: "shutdown" },
                                    { label: "Quit App", value: "quit" }
                                ]
                                delegate: Rectangle {
                                    implicitWidth: pwrTxt.implicitWidth + 16
                                    implicitHeight: 28
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

                    SectionCard {
                        cardTitle: "Clipboard Watchdog"
                        titleColor: Theme.statusActive

                        RowLayout {
                            spacing: 8
                            Text { text: "Capture Mode:"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeNormal }

                            Repeater {
                                model: [
                                    { label: "Disabled", value: "disabled" },
                                    { label: "All Download Links", value: "all" },
                                    { label: "AllDebrid Domains Only", value: "alldebrid_only" }
                                ]
                                delegate: Rectangle {
                                    implicitWidth: cmTxt.implicitWidth + 16
                                    implicitHeight: 28
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
                            text: "Pop up 'Add Links' window automatically when links are copied"
                            contentItem: Text {
                                text: clipAutoPopupCheck.text
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeNormal
                                leftPadding: clipAutoPopupCheck.indicator.width + 8
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                // PAGE 3: Notifications
                ColumnLayout {
                    anchors.fill: parent
                    visible: root.currentTab === 3
                    spacing: 14

                    SectionCard {
                        cardTitle: "Notification Triggers & Package Grouping"

                        RowLayout {
                            spacing: 18
                            CheckBox {
                                id: notifCompleteCheck
                                text: "Notify on Completion"
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
                                text: "Notify on Error"
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
                                text: "Notify on Clipboard Capture"
                                contentItem: Text {
                                    text: notifClipCheck.text
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontSizeNormal
                                    leftPadding: notifClipCheck.indicator.width + 6
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }

                        CheckBox {
                            id: notifPackageOnlyCheck
                            text: "Notify ONCE per parent Package/Folder when ALL files inside it finish (Prevents spam)"
                            contentItem: Text {
                                text: notifPackageOnlyCheck.text
                                color: Theme.statusFinished
                                font.pixelSize: Theme.fontSizeNormal
                                font.bold: true
                                leftPadding: notifPackageOnlyCheck.indicator.width + 8
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    SectionCard {
                        cardTitle: "Custom Notification Templates ({event}, {name}, {dir}, {count}, {error})"

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            rowSpacing: 8
                            columnSpacing: 12

                            Text { text: "Title Template:"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeNormal }
                            TextField {
                                id: notifTitleField
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                color: Theme.textPrimary
                                leftPadding: 8
                                background: Rectangle { color: Theme.bgInput; radius: Theme.radiusSmall; border.color: Theme.borderSubtle }
                            }

                            Text { text: "Package Finished:"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeNormal }
                            TextField {
                                id: notifPackageField
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                color: Theme.textPrimary
                                leftPadding: 8
                                background: Rectangle { color: Theme.bgInput; radius: Theme.radiusSmall; border.color: Theme.borderSubtle }
                            }

                            Text { text: "Single File Finished:"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeNormal }
                            TextField {
                                id: notifCompleteField
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                color: Theme.textPrimary
                                leftPadding: 8
                                background: Rectangle { color: Theme.bgInput; radius: Theme.radiusSmall; border.color: Theme.borderSubtle }
                            }

                            Text { text: "Error Template:"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeNormal }
                            TextField {
                                id: notifErrorField
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                color: Theme.textPrimary
                                leftPadding: 8
                                background: Rectangle { color: Theme.bgInput; radius: Theme.radiusSmall; border.color: Theme.borderSubtle }
                            }

                            Text { text: "Clipboard Template:"; color: Theme.textSecondary; font.pixelSize: Theme.fontSizeNormal }
                            TextField {
                                id: notifClipField
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                color: Theme.textPrimary
                                leftPadding: 8
                                background: Rectangle { color: Theme.bgInput; radius: Theme.radiusSmall; border.color: Theme.borderSubtle }
                            }
                        }

                        Rectangle {
                            implicitWidth: 165
                            implicitHeight: 30
                            radius: Theme.radiusSmall
                            color: Theme.bgHeader
                            border.color: Theme.borderFocus

                            Text {
                                anchors.centerIn: parent
                                text: "🔔 Send Test Notification"
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
                    }

                    Item { Layout.fillHeight: true }
                }

                // PAGE 4: Logs & Debugging
                ColumnLayout {
                    anchors.fill: parent
                    visible: root.currentTab === 4
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Live Application & API Debug Logs"
                            color: Theme.accentBlue
                            font.pixelSize: 14
                            font.bold: true
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            implicitWidth: 90
                            implicitHeight: 28
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
                            implicitHeight: 28
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
                            implicitWidth: 125
                            implicitHeight: 28
                            radius: Theme.radiusSmall
                            color: Theme.bgHeader
                            border.color: Theme.borderFocus

                            Text {
                                anchors.centerIn: parent
                                text: "📋 Copy All Logs"
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
                            anchors.margins: 8

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
            }

            // Bottom Save & Cancel Footer Bar
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                color: Theme.bgSecondary
                border.color: Theme.borderSubtle
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    spacing: 10

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        implicitWidth: 95
                        implicitHeight: 32
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
                        implicitWidth: 145
                        implicitHeight: 32
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
                                    "notifyPackageOnly": notifPackageOnlyCheck.checked,
                                    "notifyOnError": notifErrorCheck.checked,
                                    "notifyOnClipboard": notifClipCheck.checked,
                                    "notifyTitleTemplate": notifTitleField.text,
                                    "notifyCompleteTemplate": notifCompleteField.text,
                                    "notifyPackageTemplate": notifPackageField.text,
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
    }
}
