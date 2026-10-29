import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import ".."

Window {
    id: root
    title: "DMAN - Add Download Links"
    width: 780
    height: 540
    minimumWidth: 620
    minimumHeight: 420
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowSystemMenuHint | Qt.WindowMinMaxButtonsHint | Qt.WindowCloseButtonHint
    modality: Qt.NonModal
    visible: false
    color: Theme.bgPanel

    required property var controller

    property int detectedTotal: 0
    property int detectedHttp: 0
    property int detectedMagnets: 0
    property bool makeDefaultDir: false
    property bool routeViaAlldebrid: true
    property string freeDiskSpace: ""
    property bool showRawLinksView: false

    // Multi-selection state for the staged files table
    property var selectedUrls: []
    property int lastClickedIndex: -1

    function isUrlSelected(u) {
        return root.selectedUrls.indexOf(u) !== -1
    }

    function selectSingleUrl(u, idx) {
        root.selectedUrls = [u]
        root.lastClickedIndex = idx
    }

    function toggleUrlSelection(u, idx) {
        var copy = root.selectedUrls.slice()
        var pos = copy.indexOf(u)
        if (pos !== -1) {
            copy.splice(pos, 1)
        } else {
            copy.push(u)
        }
        root.selectedUrls = copy
        root.lastClickedIndex = idx
    }

    function selectRangeUrls(toIdx) {
        var files = root.controller.stagedAddFiles
        if (!files || files.length === 0) return
        var start = root.lastClickedIndex >= 0 ? root.lastClickedIndex : 0
        var low = Math.min(start, toIdx)
        var high = Math.max(start, toIdx)
        var copy = []
        for (var i = low; i <= high; i++) {
            if (files[i] && files[i].url) {
                copy.push(files[i].url)
            }
        }
        root.selectedUrls = copy
    }

    function selectAllStaged() {
        var files = root.controller.stagedAddFiles
        var copy = []
        for (var i = 0; i < files.length; i++) {
            copy.push(files[i].url)
        }
        root.selectedUrls = copy
    }

    function removeSelectedStagedFiles() {
        if (root.selectedUrls.length === 0) return
        var updatedText = root.controller.removeStagedFilesByUrls(root.selectedUrls)
        urlInput.text = updatedText
        root.selectedUrls = []
        root.refreshLinkStats()
    }

    function refreshLinkStats() {
        var stats = root.controller.analyzeLinksText(urlInput.text)
        root.detectedTotal = stats.total || 0
        root.detectedHttp = stats.httpCount || 0
        root.detectedMagnets = stats.magnetCount || 0
        root.freeDiskSpace = root.controller.getDiskFreeSpaceStr(saveDirInput.text)
        root.controller.parseLinksToStagedModel(urlInput.text)
    }

    function startImmediateDownload(targetDir) {
        if (root.detectedTotal <= 0) return
        var finalDir = targetDir ? targetDir : saveDirInput.text
        if (subfolderInput.text.trim() !== "") {
            finalDir = finalDir.replace(/[\/\\]+$/, "") + "/" + subfolderInput.text.trim()
        }
        root.controller.addLinks(
            urlInput.text,
            finalDir,
            root.makeDefaultDir,
            root.routeViaAlldebrid
        )
        root.close()
    }

    function openWithFocus(prefillText) {
        if (prefillText && prefillText.length > 0) {
            urlInput.text = prefillText
        } else if (!root.visible) {
            urlInput.text = ""
        }
        saveDirInput.text = root.controller.defaultSaveDir
        subfolderInput.text = ""
        root.makeDefaultDir = false
        root.routeViaAlldebrid = root.controller.alldebridEnabled
        root.showRawLinksView = false
        root.selectedUrls = []
        root.refreshLinkStats()
        root.show()
        root.raise()
        root.requestActivate()
        saveDirInput.forceActiveFocus()
    }

    Shortcut {
        sequence: "Escape"
        onActivated: root.close()
    }

    Shortcut {
        sequence: "Delete"
        onActivated: {
            if (!root.showRawLinksView && root.selectedUrls.length > 0) {
                root.removeSelectedStagedFiles()
            }
        }
    }

    Shortcut {
        sequence: "Ctrl+A"
        onActivated: {
            if (!root.showRawLinksView) {
                root.selectAllStaged()
            }
        }
    }

    component DarkStagedMenuItem: MenuItem {
        id: stagedItemCtrl
        property color textColor: Theme.textPrimary
        implicitWidth: 220
        implicitHeight: 30

        contentItem: Text {
            text: stagedItemCtrl.text
            font.pixelSize: Theme.fontSizeNormal
            color: stagedItemCtrl.textColor
            verticalAlignment: Text.AlignVCenter
            leftPadding: 10
        }

        background: Rectangle {
            color: stagedItemCtrl.highlighted ? Theme.rowSelected : "transparent"
            radius: Theme.radiusSmall
        }
    }

    // Dark-Mode Context Menu for Staged Files Table
    Menu {
        id: stagedContextMenu
        width: 230
        padding: 5

        background: Rectangle {
            color: Theme.bgPanel
            border.color: Theme.borderFocus
            border.width: 1
            radius: Theme.radiusMedium
        }

        DarkStagedMenuItem {
            text: "⬆ Priority: High (Download First)"
            textColor: Theme.statusActive
            onTriggered: root.controller.setStagedFilesPriority(root.selectedUrls, "High")
        }
        DarkStagedMenuItem {
            text: "▬ Priority: Normal"
            onTriggered: root.controller.setStagedFilesPriority(root.selectedUrls, "Normal")
        }
        DarkStagedMenuItem {
            text: "⬇ Priority: Low"
            onTriggered: root.controller.setStagedFilesPriority(root.selectedUrls, "Low")
        }
        MenuSeparator {
            padding: 0
            contentItem: Rectangle { implicitHeight: 1; color: Theme.borderSubtle }
        }
        DarkStagedMenuItem {
            text: "Select All Files (Ctrl+A)"
            onTriggered: root.selectAllStaged()
        }
        DarkStagedMenuItem {
            text: "✕ Remove Selected File(s) (Del)"
            textColor: Theme.statusError
            onTriggered: root.removeSelectedStagedFiles()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        // Top Header Bar
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: "Add & Inspect Download Package"
                color: Theme.textPrimary
                font.pixelSize: 15
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                implicitWidth: pasteBtnTxt.implicitWidth + 18
                implicitHeight: 26
                radius: Theme.radiusSmall
                color: pasteMouse.containsMouse ? Theme.rowHover : Theme.bgHeader
                border.color: Theme.borderFocus

                Text {
                    id: pasteBtnTxt
                    anchors.centerIn: parent
                    text: "📋 Paste Links from Clipboard"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }

                MouseArea {
                    id: pasteMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        urlInput.paste()
                        root.refreshLinkStats()
                    }
                }
            }

            Rectangle {
                implicitWidth: counterTxt.implicitWidth + 16
                implicitHeight: 26
                radius: Theme.radiusSmall
                color: root.detectedTotal > 0 ? Theme.rowSelected : Theme.bgInput
                border.color: root.detectedTotal > 0 ? Theme.borderFocus : Theme.borderSubtle

                Text {
                    id: counterTxt
                    anchors.centerIn: parent
                    text: root.detectedTotal > 0
                          ? "Files: " + root.detectedTotal + " (" + root.detectedHttp + " Direct, " + root.detectedMagnets + " Magnet)"
                          : "No links staged"
                    color: root.detectedTotal > 0 ? Theme.textPrimary : Theme.textMuted
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }
            }
        }

        // Main Content Area: Either File Table View (Default) OR Raw Links Editor
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.bgPrimary
            radius: Theme.radiusSmall
            border.color: Theme.borderSubtle
            border.width: 1
            clip: true

            // 1. FILE LIST TABLE VIEW (Default)
            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                visible: !root.showRawLinksView

                // Table Columns Header
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    color: Theme.bgHeader
                    border.color: Theme.borderSubtle

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: "File Name (Shift / Ctrl Multi-Select, Right-Click for Priority)"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }
                        Text {
                            Layout.preferredWidth: 100
                            text: "Size"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }
                        Text {
                            Layout.preferredWidth: 85
                            text: "Priority"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }
                        Text {
                            Layout.preferredWidth: 50
                            text: "Action"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

                ListView {
                    id: stagedListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: root.controller.stagedAddFiles
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    Text {
                        anchors.centerIn: parent
                        visible: stagedListView.count === 0
                        text: "No files staged yet.\nClick '📋 Paste Links from Clipboard' or switch to 'Show Raw Links' below to paste URLs."
                        horizontalAlignment: Text.AlignHCenter
                        color: Theme.textMuted
                        font.pixelSize: 12
                    }

                    delegate: Rectangle {
                        width: stagedListView.width
                        height: 30
                        readonly property bool isRowSelected: root.isUrlSelected(modelData.url)

                        color: {
                            if (isRowSelected) return Theme.rowSelected
                            if (itemMouse.containsMouse) return Theme.rowHover
                            return (index % 2 === 0) ? Theme.rowEven : Theme.rowOdd
                        }

                        Timer {
                            id: stagedHoverTimer
                            interval: 1000
                            repeat: false
                            onTriggered: {
                                if (itemMouse.containsMouse) {
                                    stagedFullNameTip.visible = true
                                }
                            }
                        }

                        ToolTip {
                            id: stagedFullNameTip
                            x: Math.min(itemMouse.mouseX + 14, parent.width - implicitWidth - 10)
                            y: itemMouse.mouseY + 18
                            visible: false
                            text: modelData.filename || ""
                            delay: 0
                            timeout: 6000

                            contentItem: Text {
                                text: stagedFullNameTip.text
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeNormal
                            }

                            background: Rectangle {
                                color: Theme.bgHeader
                                border.color: Theme.borderFocus
                                border.width: 1
                                radius: Theme.radiusSmall
                            }
                        }

                        MouseArea {
                            id: itemMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onEntered: stagedHoverTimer.restart()
                            onExited: {
                                stagedHoverTimer.stop()
                                stagedFullNameTip.visible = false
                            }
                            onPositionChanged: {
                                stagedFullNameTip.visible = false
                                stagedHoverTimer.restart()
                            }
                            onClicked: function(mouse) {
                                if (mouse.button === Qt.RightButton) {
                                    if (!root.isUrlSelected(modelData.url)) {
                                        root.selectSingleUrl(modelData.url, index)
                                    }
                                    stagedContextMenu.popup()
                                    return
                                }
                                if (mouse.modifiers & Qt.ShiftModifier) {
                                    root.selectRangeUrls(index)
                                } else if (mouse.modifiers & Qt.ControlModifier) {
                                    root.toggleUrlSelection(modelData.url, index)
                                } else {
                                    root.selectSingleUrl(modelData.url, index)
                                }
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: modelData.priority === "High" ? Theme.statusActive : (modelData.priority === "Low" ? Theme.textMuted : Theme.accentBlue)
                                }

                                Rectangle {
                                    width: 16
                                    height: 16
                                    radius: 3
                                    color: Theme.bgInput
                                    border.color: Theme.borderSubtle
                                    border.width: 1
                                    clip: true

                                    Image {
                                        id: stagedFavicon
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        source: modelData.faviconUrl || ""
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        cache: true
                                        visible: status === Image.Ready
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: stagedFavicon.status !== Image.Ready
                                        text: (modelData.domain && modelData.domain.length > 0) ? modelData.domain.charAt(0).toUpperCase() : "🌐"
                                        color: Theme.accentBlue
                                        font.pixelSize: 9
                                        font.bold: true
                                    }
                                }

                                Text {
                                    visible: root.controller.showRowNumbers
                                    text: (index + 1) + "."
                                    color: Theme.accentBlue
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.filename
                                    color: Theme.textPrimary
                                    font.pixelSize: Theme.fontSizeNormal
                                    elide: Text.ElideMiddle
                                }
                            }

                            Text {
                                Layout.preferredWidth: 100
                                text: modelData.sizeStr
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeNormal
                            }

                            Rectangle {
                                Layout.preferredWidth: 85
                                implicitHeight: 20
                                radius: 3
                                color: modelData.priority === "High" ? "#244028" : (modelData.priority === "Low" ? "#25282E" : "#1F3247")
                                border.color: modelData.priority === "High" ? Theme.statusActive : Theme.borderSubtle

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.priority
                                    color: modelData.priority === "High" ? Theme.statusActive : Theme.textPrimary
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: modelData.priority === "High"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var nextP = modelData.priority === "Normal" ? "High" : (modelData.priority === "High" ? "Low" : "Normal")
                                        root.controller.setStagedFilesPriority([modelData.url], nextP)
                                    }
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 50
                                implicitHeight: 22
                                radius: 3
                                color: delBtnMouse.containsMouse ? Theme.statusError : Theme.bgHeader

                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    color: "#FFFFFF"
                                    font.pixelSize: 11
                                    font.bold: true
                                }

                                MouseArea {
                                    id: delBtnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var newTxt = root.controller.removeStagedFilesByUrls([modelData.url])
                                        urlInput.text = newTxt
                                        root.refreshLinkStats()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 2. RAW LINKS TEXT EDITOR (Toggled via bottom button)
            ScrollView {
                anchors.fill: parent
                visible: root.showRawLinksView

                TextArea {
                    id: urlInput
                    placeholderText: "Paste raw HTTP/HTTPS/Magnet links here (separated by spaces or newlines)..."
                    placeholderTextColor: Theme.textMuted
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeNormal
                    selectByMouse: true
                    wrapMode: TextEdit.WrapAnywhere
                    onTextChanged: root.refreshLinkStats()

                    background: Rectangle {
                        color: Theme.bgInput
                    }
                }
            }
        }

        // Save Directory + Subfolder + Browse Row
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Save to:"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeNormal
            }

            TextField {
                id: saveDirInput
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                text: root.controller.defaultSaveDir
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeNormal
                selectByMouse: true
                leftPadding: 8
                rightPadding: 8
                onTextChanged: root.freeDiskSpace = root.controller.getDiskFreeSpaceStr(text)
                onAccepted: root.startImmediateDownload(saveDirInput.text)

                background: Rectangle {
                    color: Theme.bgInput
                    radius: Theme.radiusSmall
                    border.color: saveDirInput.activeFocus ? Theme.borderFocus : Theme.borderSubtle
                }
            }

            TextField {
                id: subfolderInput
                Layout.preferredWidth: 170
                Layout.preferredHeight: 30
                placeholderText: "+ Subfolder / Package Name"
                placeholderTextColor: Theme.textMuted
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeNormal
                selectByMouse: true
                leftPadding: 8
                rightPadding: 8
                onAccepted: root.startImmediateDownload(saveDirInput.text)

                background: Rectangle {
                    color: Theme.bgInput
                    radius: Theme.radiusSmall
                    border.color: subfolderInput.activeFocus ? Theme.borderFocus : Theme.borderSubtle
                }
            }

            Rectangle {
                implicitWidth: 88
                implicitHeight: 30
                radius: Theme.radiusSmall
                color: browseMouse.containsMouse ? Theme.rowHover : Theme.bgHeader
                border.color: Theme.borderSubtle

                Text {
                    anchors.centerIn: parent
                    text: "Browse..."
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeNormal
                }

                MouseArea {
                    id: browseMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var chosen = root.controller.browseFolder(saveDirInput.text)
                        if (chosen !== "") {
                            saveDirInput.text = chosen
                        }
                    }
                }
            }
        }

        // Quick 1-Click Recent Folders Bar + Disk Free Space Indicator
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: "Free Space: " + root.freeDiskSpace
                color: Theme.statusActive
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }

            Text {
                text: "| 1-Click Start in:"
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeSmall
                visible: root.controller.recentDownloadDirs.length > 0
            }

            Repeater {
                model: root.controller.recentDownloadDirs
                delegate: Rectangle {
                    implicitWidth: Math.min(160, qDirTxt.implicitWidth + 14)
                    implicitHeight: 22
                    radius: Theme.radiusSmall
                    color: qDirMouse.containsMouse ? Theme.rowSelected : Theme.bgHeader
                    border.color: Theme.borderSubtle

                    Text {
                        id: qDirTxt
                        anchors.centerIn: parent
                        width: parent.width - 10
                        text: modelData.split(/[\/\\]/).pop() || modelData
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideMiddle
                        horizontalAlignment: Text.AlignHCenter
                    }

                    MouseArea {
                        id: qDirMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            saveDirInput.text = modelData
                            if (root.detectedTotal > 0) {
                                root.startImmediateDownload(modelData)
                            }
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }

        // Options Row: Set as Default Folder + Use AllDebrid
        RowLayout {
            Layout.fillWidth: true
            spacing: 18

            CheckBox {
                id: defaultDirChk
                checked: root.makeDefaultDir
                onToggled: root.makeDefaultDir = checked
                text: "Save as default download directory"
                contentItem: Text {
                    text: defaultDirChk.text
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeNormal
                    leftPadding: defaultDirChk.indicator.width + 6
                    verticalAlignment: Text.AlignVCenter
                }
            }

            CheckBox {
                id: routeAdChk
                visible: root.controller.alldebridEnabled
                checked: root.routeViaAlldebrid
                onToggled: root.routeViaAlldebrid = checked
                text: "Unrestrict via AllDebrid"
                contentItem: Text {
                    text: routeAdChk.text
                    color: Theme.statusActive
                    font.pixelSize: Theme.fontSizeNormal
                    leftPadding: routeAdChk.indicator.width + 6
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Item { Layout.fillWidth: true }
        }

        // Bottom Action Bar (Includes Toggle Raw Links Button)
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Toggle Raw Links Button
            Rectangle {
                implicitWidth: toggleRawTxt.implicitWidth + 20
                implicitHeight: 32
                radius: Theme.radiusSmall
                color: root.showRawLinksView ? Theme.rowSelected : Theme.bgHeader
                border.color: root.showRawLinksView ? Theme.borderFocus : Theme.borderSubtle

                Text {
                    id: toggleRawTxt
                    anchors.centerIn: parent
                    text: root.showRawLinksView ? "📁 Show File Table View" : "🔗 Show / Edit Raw Links"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeNormal
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showRawLinksView = !root.showRawLinksView
                }
            }

            Rectangle {
                implicitWidth: 125
                implicitHeight: 32
                radius: Theme.radiusSmall
                color: torrentBtnMouse.containsMouse ? Theme.rowHover : Theme.bgHeader
                border.color: Theme.borderSubtle

                Text {
                    anchors.centerIn: parent
                    text: "+ .torrent File..."
                    color: Theme.accentBlue
                    font.pixelSize: Theme.fontSizeNormal
                    font.bold: true
                }

                MouseArea {
                    id: torrentBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var tpath = root.controller.browseTorrentFile()
                        if (tpath !== "") {
                            urlInput.text = (urlInput.text ? urlInput.text + "\n" : "") + tpath
                            root.refreshLinkStats()
                        }
                    }
                }
            }

            Rectangle {
                visible: !root.showRawLinksView && root.selectedUrls.length > 0
                implicitWidth: 140
                implicitHeight: 32
                radius: Theme.radiusSmall
                color: Theme.bgHeader
                border.color: Theme.statusError

                Text {
                    anchors.centerIn: parent
                    text: "Remove Selected (" + root.selectedUrls.length + ")"
                    color: Theme.statusError
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.removeSelectedStagedFiles()
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                implicitWidth: 90
                implicitHeight: 32
                radius: Theme.radiusSmall
                color: cancelMouse.containsMouse ? Theme.rowHover : Theme.bgHeader
                border.color: Theme.borderSubtle

                Text {
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeNormal
                }

                MouseArea {
                    id: cancelMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.close()
                }
            }

            Rectangle {
                implicitWidth: 155
                implicitHeight: 32
                radius: Theme.radiusSmall
                opacity: root.detectedTotal > 0 ? 1.0 : 0.5
                color: startMouse.containsMouse && root.detectedTotal > 0 ? "#4A89C7" : Theme.accentBlue

                Text {
                    anchors.centerIn: parent
                    text: root.detectedTotal > 1
                          ? "Download (" + root.detectedTotal + " Files)"
                          : "Start Download"
                    color: "#FFFFFF"
                    font.pixelSize: Theme.fontSizeNormal
                    font.bold: true
                }

                MouseArea {
                    id: startMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: root.detectedTotal > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.startImmediateDownload(saveDirInput.text)
                }
            }
        }
    }
}
