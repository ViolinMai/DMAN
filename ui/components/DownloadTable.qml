import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Rectangle {
    id: root
    color: Theme.bgPrimary
    border.color: Theme.borderSubtle
    border.width: 1
    focus: true

    required property var controller

    // Multi-selection tracking
    property int anchorIndex: -1

    function isGidSelected(gid) {
        return root.controller.selectedGids.indexOf(gid) !== -1
    }

    function selectSingleRow(gid, idx) {
        root.anchorIndex = idx
        root.controller.setSelectionList([gid], gid)
    }

    function toggleRowSelection(gid, idx) {
        var current = root.controller.selectedGids.slice()
        var pos = current.indexOf(gid)
        if (pos !== -1) {
            current.splice(pos, 1)
        } else {
            current.push(gid)
        }
        root.anchorIndex = idx
        root.controller.setSelectionList(current, gid)
    }

    function selectRangeRows(toIdx) {
        var count = listView.count
        if (count <= 0) return
        var start = root.anchorIndex >= 0 ? root.anchorIndex : 0
        var low = Math.min(start, toIdx)
        var high = Math.max(start, toIdx)
        var gids = []
        for (var i = low; i <= high; i++) {
            var mIdx = root.controller.downloadModel.index(i, 0)
            var g = root.controller.downloadModel.data(mIdx, Qt.UserRole + 1) // GidRole
            if (g) gids.push(g)
        }
        var primary = gids.length > 0 ? gids[gids.length - 1] : ""
        root.controller.setSelectionList(gids, primary)
    }

    function selectAllRows() {
        var count = listView.count
        var gids = []
        for (var i = 0; i < count; i++) {
            var mIdx = root.controller.downloadModel.index(i, 0)
            var g = root.controller.downloadModel.data(mIdx, Qt.UserRole + 1)
            if (g) gids.push(g)
        }
        var primary = gids.length > 0 ? gids[0] : ""
        root.controller.setSelectionList(gids, primary)
    }

    Shortcut {
        sequence: "Ctrl+A"
        onActivated: root.selectAllRows()
    }

    Shortcut {
        sequence: "Delete"
        onActivated: {
            if (root.controller.selectedGid !== "") {
                root.controller.removeDownload(root.controller.selectedGid, "")
            }
        }
    }

    component DarkMenuItem: MenuItem {
        id: menuItemControl
        property color textColor: Theme.textPrimary
        implicitWidth: 230
        implicitHeight: visible ? 30 : 0
        height: visible ? 30 : 0

        contentItem: Text {
            text: menuItemControl.text
            font.pixelSize: Theme.fontSizeNormal
            color: menuItemControl.enabled ? menuItemControl.textColor : Theme.textMuted
            verticalAlignment: Text.AlignVCenter
            leftPadding: 10
            elide: Text.ElideRight
        }

        background: Rectangle {
            color: menuItemControl.highlighted ? Theme.rowSelected : "transparent"
            radius: Theme.radiusSmall
        }
    }

    component DarkMenuSeparator: MenuSeparator {
        id: sepControl
        implicitHeight: visible ? 9 : 0
        height: visible ? 9 : 0
        padding: 0
        contentItem: Rectangle {
            implicitWidth: 210
            implicitHeight: 1
            color: Theme.borderSubtle
        }
        background: Item {}
    }

    // Smart Dark-Mode Right-Click Context Menu
    Menu {
        id: rowContextMenu
        width: 240
        padding: 5

        readonly property var caps: root.controller.selectionCapabilities || ({})

        background: Rectangle {
            color: Theme.bgPanel
            border.color: Theme.borderFocus
            border.width: 1
            radius: Theme.radiusMedium
        }

        DarkMenuItem {
            visible: rowContextMenu.caps.canResume === true
            text: root.controller.selectedGids.length > 1
                  ? "▶ Resume Selected (" + root.controller.selectedGids.length + ")"
                  : "▶ Resume / Start"
            textColor: Theme.statusActive
            onTriggered: root.controller.resumeDownload(root.controller.selectedGid)
        }
        DarkMenuItem {
            visible: rowContextMenu.caps.canPause === true
            text: root.controller.selectedGids.length > 1
                  ? "⏸ Pause Selected (" + root.controller.selectedGids.length + ")"
                  : "⏸ Pause"
            textColor: Theme.statusPaused
            onTriggered: root.controller.pauseDownload(root.controller.selectedGid)
        }
        DarkMenuItem {
            visible: rowContextMenu.caps.canRetry === true
            text: "↻ Retry Failed / Missing"
            textColor: Theme.accentBlue
            onTriggered: root.controller.retryDownload(root.controller.selectedGid)
        }

        DarkMenuSeparator {
            visible: (rowContextMenu.caps.canResume || rowContextMenu.caps.canPause || rowContextMenu.caps.canRetry) && rowContextMenu.caps.canPrioritize
        }

        DarkMenuItem {
            visible: rowContextMenu.caps.canPrioritize === true
            text: "⬆ Priority: High (Move to Top)"
            onTriggered: root.controller.setDownloadPriority(root.controller.selectedGid, "High")
        }
        DarkMenuItem {
            visible: rowContextMenu.caps.canPrioritize === true
            text: "▬ Priority: Normal"
            onTriggered: root.controller.setDownloadPriority(root.controller.selectedGid, "Normal")
        }
        DarkMenuItem {
            visible: rowContextMenu.caps.canPrioritize === true
            text: "⬇ Priority: Low (Move to Bottom)"
            onTriggered: root.controller.setDownloadPriority(root.controller.selectedGid, "Low")
        }

        DarkMenuSeparator {
            visible: rowContextMenu.caps.canResume || rowContextMenu.caps.canPause || rowContextMenu.caps.canRetry || rowContextMenu.caps.canPrioritize
        }

        DarkMenuItem {
            text: "📂 Open Destination Folder"
            onTriggered: {
                var dir = root.controller.selectedItem.saveDir || root.controller.defaultSaveDir
                root.controller.openFolder(dir)
            }
        }
        DarkMenuItem {
            visible: rowContextMenu.caps.canChangeDir === true
            text: "📁 Change Save Directory..."
            onTriggered: {
                var cur = root.controller.selectedItem.saveDir || root.controller.defaultSaveDir
                var picked = root.controller.browseFolder(cur)
                if (picked !== "") {
                    root.controller.changeDownloadPath(root.controller.selectedGid, picked)
                }
            }
        }
        DarkMenuItem {
            visible: rowContextMenu.caps.hasSourceUri === true
            text: "📋 Copy Source Link"
            onTriggered: root.controller.copyLogsToClipboard(root.controller.selectedItem.sourceUri || "")
        }

        DarkMenuSeparator {}

        DarkMenuItem {
            text: "Select All (Ctrl+A)"
            onTriggered: root.selectAllRows()
        }
        DarkMenuItem {
            text: root.controller.selectedGids.length > 1
                  ? "✕ Remove Selected (" + root.controller.selectedGids.length + ")"
                  : "✕ Remove from List"
            textColor: Theme.statusError
            onTriggered: root.controller.removeDownload(root.controller.selectedGid, root.controller.selectedItem.status || "")
        }
    }

    // Dynamic proportional column ratios (Total = 1.0)
    readonly property real colNameRatio: 0.28
    readonly property real colSizeRatio: 0.09
    readonly property real colConnRatio: 0.06
    readonly property real colStatusRatio: 0.12
    readonly property real colSpeedRatio: 0.09
    readonly property real colEtaRatio: 0.07
    readonly property real colLoadedRatio: 0.09
    readonly property real colProgressRatio: 0.10
    readonly property real colSaveToRatio: 0.10

    component HeaderCell: Rectangle {
        property string title: ""
        property real ratio: 0.1
        Layout.preferredWidth: Math.floor(root.width * ratio)
        Layout.fillHeight: true
        color: "transparent"

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.rightMargin: 4
            text: parent.title
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeHeader
            font.bold: true
            elide: Text.ElideRight
        }

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: Theme.borderSubtle
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Table Header Bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.headerHeight
            color: Theme.bgHeader
            border.color: Theme.borderSubtle
            border.width: 1

            RowLayout {
                anchors.fill: parent
                spacing: 0

                HeaderCell { title: "Name"; ratio: root.colNameRatio }
                HeaderCell { title: "Size"; ratio: root.colSizeRatio }
                HeaderCell { title: "Conn."; ratio: root.colConnRatio }
                HeaderCell { title: "Status"; ratio: root.colStatusRatio }
                HeaderCell { title: "Speed"; ratio: root.colSpeedRatio }
                HeaderCell { title: "ETA"; ratio: root.colEtaRatio }
                HeaderCell { title: "Bytes Loaded"; ratio: root.colLoadedRatio }
                HeaderCell { title: "Progress"; ratio: root.colProgressRatio }
                HeaderCell { title: "Save to"; ratio: root.colSaveToRatio }
            }
        }

        // Main High-Density ListView
        ListView {
            id: listView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.controller.downloadModel
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            // Empty State
            Text {
                anchors.centerIn: parent
                visible: listView.count === 0
                text: "No downloads in queue. Click '+ Add New Links' to start."
                color: Theme.textMuted
                font.pixelSize: 13
            }

            delegate: Rectangle {
                id: rowDelegate
                width: listView.width
                height: Theme.rowHeight

                readonly property bool isSelected: root.isGidSelected(model.gid)

                color: {
                    if (isSelected) return Theme.rowSelected
                    if (rowMouse.containsMouse) return Theme.rowHover
                    if (model.isPackage) return "#272C33"
                    return (index % 2 === 0) ? Theme.rowEven : Theme.rowOdd
                }

                Timer {
                    id: hoverNameTimer
                    interval: 1000
                    repeat: false
                    onTriggered: {
                        if (rowMouse.containsMouse) {
                            fullNameTooltip.visible = true
                        }
                    }
                }

                ToolTip {
                    id: fullNameTooltip
                    parent: rowDelegate
                    x: Math.min(rowMouse.mouseX + 14, rowDelegate.width - implicitWidth - 10)
                    y: rowMouse.mouseY + 18
                    visible: false
                    text: model.name || ""
                    delay: 0
                    timeout: 6000

                    contentItem: Text {
                        text: fullNameTooltip.text
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
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onEntered: hoverNameTimer.restart()
                    onExited: {
                        hoverNameTimer.stop()
                        fullNameTooltip.visible = false
                    }
                    onPositionChanged: {
                        fullNameTooltip.visible = false
                        hoverNameTimer.restart()
                    }
                    onClicked: function(mouse) {
                        root.forceActiveFocus()
                        if (mouse.button === Qt.RightButton) {
                            if (!root.isGidSelected(model.gid)) {
                                root.selectSingleRow(model.gid, index)
                            }
                            rowContextMenu.popup()
                            return
                        }
                        if (mouse.modifiers & Qt.ShiftModifier) {
                            root.selectRangeRows(index)
                        } else if (mouse.modifiers & Qt.ControlModifier) {
                            root.toggleRowSelection(model.gid, index)
                        } else {
                            root.selectSingleRow(model.gid, index)
                        }
                    }
                    onDoubleClicked: {
                        if (model.isPackage) {
                            root.controller.downloadModel.togglePackage(model.packageKey)
                        } else {
                            root.controller.openFolder(model.saveDir)
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: 0

                    // 1. Name
                    Item {
                        Layout.preferredWidth: Math.floor(root.width * root.colNameRatio)
                        Layout.fillHeight: true

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: model.isPackage ? 8 : 26
                            anchors.rightMargin: 6
                            spacing: 6

                            // Expand/Collapse toggle for Package Parent rows
                            Text {
                                visible: model.isPackage
                                text: model.isExpanded ? "▾ 📁" : "▸ 📁"
                                color: Theme.statusPaused
                                font.pixelSize: Theme.fontSizeNormal
                                font.bold: true

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.controller.downloadModel.togglePackage(model.packageKey)
                                }
                            }

                            // Status Dot (Purple #C678DD for Finished!)
                            Rectangle {
                                visible: !model.isPackage
                                width: 9
                                height: 9
                                radius: 5
                                color: {
                                    if (model.status === "active") return Theme.statusActive
                                    if (model.status === "complete") return Theme.statusFinished // Purple
                                    if (model.status === "paused") return Theme.statusPaused
                                    if (model.status === "error" || model.status === "missing") return Theme.statusError
                                    return Theme.textMuted
                                }
                            }

                            // Website Favicon Badge
                            Rectangle {
                                visible: !model.isPackage
                                width: 16
                                height: 16
                                radius: 3
                                color: Theme.bgInput
                                border.color: Theme.borderSubtle
                                border.width: 1
                                clip: true

                                Image {
                                    id: siteFavicon
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    source: (!model.isPackage && model.faviconUrl) ? model.faviconUrl : ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: true
                                    visible: status === Image.Ready
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: siteFavicon.status !== Image.Ready
                                    text: (model.domain && model.domain.length > 0) ? model.domain.charAt(0).toUpperCase() : "🌐"
                                    color: Theme.accentBlue
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                            }

                            // Optional Item Number (Toggled via TopBar '# Num' button)
                            Text {
                                visible: !model.isPackage && root.controller.showRowNumbers && model.itemNumber > 0
                                text: model.itemNumber + "."
                                color: Theme.accentBlue
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                            }

                            Text {
                                Layout.fillWidth: true
                                text: (model.priority === "High" ? "⬆ " : (model.priority === "Low" ? "⬇ " : "")) + model.name
                                color: model.isPackage ? "#FFD580" : Theme.textPrimary
                                font.pixelSize: Theme.fontSizeNormal
                                font.bold: model.isPackage
                                elide: Text.ElideMiddle
                            }
                        }
                    }

                    // 2. Size
                    Item {
                        Layout.preferredWidth: Math.floor(root.width * root.colSizeRatio)
                        Layout.fillHeight: true
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            text: model.sizeStr
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeNormal
                            elide: Text.ElideRight
                        }
                    }

                    // 3. Connections
                    Item {
                        Layout.preferredWidth: Math.floor(root.width * root.colConnRatio)
                        Layout.fillHeight: true
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            text: model.connections > 0 ? model.connections : "-"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeNormal
                        }
                    }

                    // 4. Status
                    Item {
                        Layout.preferredWidth: Math.floor(root.width * root.colStatusRatio)
                        Layout.fillHeight: true
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            text: model.statusDisplay
                            color: {
                                if (model.status === "complete") return Theme.statusFinished // Purple
                                if (model.status === "error" || model.status === "missing") return Theme.statusError
                                if (model.status === "paused") return Theme.statusPaused
                                if (model.status === "active") return Theme.statusActive
                                return Theme.textSecondary
                            }
                            font.pixelSize: Theme.fontSizeNormal
                            font.bold: model.status === "complete"
                            elide: Text.ElideRight
                        }
                    }

                    // 5. Speed
                    Item {
                        Layout.preferredWidth: Math.floor(root.width * root.colSpeedRatio)
                        Layout.fillHeight: true
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            text: model.speedStr
                            color: Theme.accentBlue
                            font.pixelSize: Theme.fontSizeNormal
                            font.bold: true
                            elide: Text.ElideRight
                        }
                    }

                    // 6. ETA
                    Item {
                        Layout.preferredWidth: Math.floor(root.width * root.colEtaRatio)
                        Layout.fillHeight: true
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            text: model.etaStr
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeNormal
                        }
                    }

                    // 7. Bytes Loaded
                    Item {
                        Layout.preferredWidth: Math.floor(root.width * root.colLoadedRatio)
                        Layout.fillHeight: true
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            text: model.completedStr
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeNormal
                            elide: Text.ElideRight
                        }
                    }

                    // 8. Progress Bar Cell
                    Item {
                        Layout.preferredWidth: Math.floor(root.width * root.colProgressRatio)
                        Layout.fillHeight: true

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 4
                            radius: 2
                            color: Theme.progressBg
                            border.color: Theme.borderSubtle
                            border.width: 1
                            clip: true

                            Rectangle {
                                width: parent.width * (model.progress / 100.0)
                                height: parent.height
                                color: model.status === "error"
                                       ? Theme.statusError
                                       : (model.status === "complete" ? "#7E57C2" : Theme.progressFill)
                            }

                            Text {
                                anchors.centerIn: parent
                                text: model.progress.toFixed(0) + "%"
                                color: Theme.textPrimary
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                            }
                        }
                    }

                    // 9. Save To Path
                    Item {
                        Layout.preferredWidth: Math.floor(root.width * root.colSaveToRatio)
                        Layout.fillHeight: true
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            text: model.saveDir
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeNormal
                            elide: Text.ElideMiddle
                        }
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Theme.bgPrimary
                }
            }
        }
    }
}
