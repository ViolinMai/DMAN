import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Rectangle {
    id: root
    height: Theme.topBarHeight
    color: Theme.bgSecondary
    border.color: Theme.borderSubtle
    border.width: 1

    required property var controller
    signal openAddLinksRequested()
    signal openSettingsRequested()

    component ActionBtn: Rectangle {
        id: btn
        property string label: ""
        property string iconText: ""
        property color iconColor: Theme.textPrimary
        property bool enabledBtn: true
        signal triggered()

        implicitWidth: btnRow.implicitWidth + 18
        implicitHeight: 26
        radius: Theme.radiusSmall
        opacity: enabledBtn ? 1.0 : 0.4
        color: mouseArea.containsMouse && enabledBtn ? Theme.rowHover : Theme.bgHeader
        border.color: Theme.borderSubtle
        border.width: 1

        RowLayout {
            id: btnRow
            anchors.centerIn: parent
            spacing: 6

            Text {
                text: btn.iconText
                color: btn.iconColor
                font.pixelSize: Theme.fontSizeNormal
                font.bold: true
            }

            Text {
                text: btn.label
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeNormal
                visible: btn.label.length > 0
            }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.enabledBtn ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (btn.enabledBtn) {
                    btn.triggered()
                }
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 6

        ActionBtn {
            iconText: "+"
            iconColor: Theme.statusActive
            label: "Add Links"
            onTriggered: root.openAddLinksRequested()
        }

        Rectangle {
            width: 1
            height: 20
            color: Theme.borderSubtle
        }

        ActionBtn {
            iconText: "▶"
            iconColor: Theme.statusActive
            label: "Resume"
            enabledBtn: root.controller.selectedGid !== ""
            onTriggered: root.controller.resumeDownload(root.controller.selectedGid)
        }

        ActionBtn {
            iconText: "⏸"
            iconColor: Theme.statusPaused
            label: "Pause"
            enabledBtn: root.controller.selectedGid !== ""
            onTriggered: root.controller.pauseDownload(root.controller.selectedGid)
        }

        ActionBtn {
            iconText: "↻"
            iconColor: Theme.accentBlue
            label: "Retry"
            enabledBtn: root.controller.selectedGid !== ""
            onTriggered: root.controller.retryDownload(root.controller.selectedGid)
        }

        ActionBtn {
            iconText: "✕"
            iconColor: Theme.statusError
            label: "Remove"
            enabledBtn: root.controller.selectedGid !== ""
            onTriggered: {
                var item = root.controller.selectedItem
                root.controller.removeDownload(root.controller.selectedGid, item.status || "")
            }
        }

        Rectangle {
            width: 1
            height: 20
            color: Theme.borderSubtle
        }

        ActionBtn {
            iconText: "▶▶"
            iconColor: Theme.accentBlue
            label: "Resume All"
            onTriggered: root.controller.resumeAll()
        }

        ActionBtn {
            iconText: "⏸⏸"
            iconColor: Theme.statusPaused
            label: "Pause All"
            onTriggered: root.controller.pauseAll()
        }

        Rectangle {
            width: 1
            height: 20
            color: Theme.borderSubtle
        }

        ActionBtn {
            iconText: "⚙"
            iconColor: Theme.accentBlue
            label: "Settings"
            onTriggered: root.openSettingsRequested()
        }

        Item {
            Layout.fillWidth: true
        }

        // Post-Download Completion Action Selector
        Rectangle {
            implicitWidth: afterRow.implicitWidth + 14
            implicitHeight: 24
            radius: Theme.radiusSmall
            color: Theme.bgInput
            border.color: Theme.borderSubtle
            border.width: 1

            RowLayout {
                id: afterRow
                anchors.centerIn: parent
                spacing: 6

                Text {
                    text: "When Done:"
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeSmall
                }

                Text {
                    text: {
                        var act = root.controller.postDownloadAction
                        if (act === "sleep") return "Sleep OS ▾"
                        if (act === "shutdown") return "Shutdown OS ▾"
                        if (act === "quit") return "Quit App ▾"
                        return "Do Nothing ▾"
                    }
                    color: root.controller.postDownloadAction === "nothing" ? Theme.textSecondary : Theme.statusPaused
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    var order = ["nothing", "sleep", "shutdown", "quit"]
                    var idx = order.indexOf(root.controller.postDownloadAction)
                    var nextAct = order[(idx + 1) % order.length]
                    root.controller.setPostDownloadAction(nextAct)
                }
            }
        }

        // AllDebrid Status Badge
        Rectangle {
            implicitWidth: adLayout.implicitWidth + 16
            implicitHeight: 24
            radius: Theme.radiusSmall
            color: Theme.bgInput
            border.color: Theme.borderSubtle
            border.width: 1

            RowLayout {
                id: adLayout
                anchors.centerIn: parent
                spacing: 6

                Rectangle {
                    width: 8
                    height: 8
                    radius: 4
                    color: {
                        if (!root.controller.alldebridEnabled) return Theme.textMuted
                        return root.controller.alldebridIsPremium ? Theme.statusActive : Theme.statusPaused
                    }
                }

                Text {
                    text: root.controller.alldebridEnabled
                          ? "AllDebrid: " + root.controller.alldebridStatusText
                          : "AllDebrid: Off"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openSettingsRequested()
            }
        }

        // Aria2 RPC Status Indicator
        Rectangle {
            implicitWidth: statusLayout.implicitWidth + 16
            implicitHeight: 24
            radius: Theme.radiusSmall
            color: Theme.bgInput
            border.color: Theme.borderSubtle
            border.width: 1

            RowLayout {
                id: statusLayout
                anchors.centerIn: parent
                spacing: 6

                Rectangle {
                    width: 8
                    height: 8
                    radius: 4
                    color: root.controller.rpcConnected ? Theme.statusActive : Theme.statusError
                }

                Text {
                    text: root.controller.rpcConnected ? "aria2 RPC: Online" : "aria2 RPC: Offline"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }
    }
}
