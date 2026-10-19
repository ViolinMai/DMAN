import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

Rectangle {
    id: root
    color: Theme.bgPrimary
    border.color: Theme.borderSubtle
    border.width: 1

    required property var controller

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

                readonly property bool isSelected: root.controller.selectedGid === model.gid

                color: {
                    if (isSelected) return Theme.rowSelected
                    if (rowMouse.containsMouse) return Theme.rowHover
                    if (model.isPackage) return "#272C33"
                    return (index % 2 === 0) ? Theme.rowEven : Theme.rowOdd
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: function(mouse) {
                        root.controller.selectDownload(model.gid)
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

                            Rectangle {
                                visible: !model.isPackage
                                width: 8
                                height: 8
                                radius: 4
                                color: {
                                    if (model.status === "active") return Theme.statusActive
                                    if (model.status === "complete") return Theme.statusFinished
                                    if (model.status === "paused") return Theme.statusPaused
                                    if (model.status === "error" || model.status === "missing") return Theme.statusError
                                    return Theme.textMuted
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: model.name
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
                                if (model.status === "complete") return Theme.statusFinished
                                if (model.status === "error" || model.status === "missing") return Theme.statusError
                                if (model.status === "paused") return Theme.statusPaused
                                if (model.status === "active") return Theme.statusActive
                                return Theme.textSecondary
                            }
                            font.pixelSize: Theme.fontSizeNormal
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
                                color: model.status === "error" ? Theme.statusError : Theme.progressFill
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
