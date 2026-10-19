import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

ColumnLayout {
    id: root
    spacing: 0

    required property var controller
    property bool showInspector: true

    signal openAddLinksRequested()

    // 1. Selected Package/Download Properties Panel (Collapsible)
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: root.showInspector ? 112 : 26
        color: Theme.bgPanel
        border.color: Theme.borderSubtle
        border.width: 1
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Section Title Bar
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                color: Theme.bgHeader

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10

                    Text {
                        text: root.controller.selectedGid !== ""
                              ? "Package Properties: " + (root.controller.selectedItem.name || "")
                              : "Package Properties (Select a download to inspect)"
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSizeHeader
                        font.bold: true
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Text {
                        text: root.showInspector ? "▼" : "▲"
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showInspector = !root.showInspector
                        }
                    }
                }
            }

            // Inspector Fields Grid
            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 8
                columns: 3
                rowSpacing: 6
                columnSpacing: 10
                visible: root.showInspector

                Text {
                    text: "File Name:"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeNormal
                    horizontalAlignment: Text.AlignRight
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 24
                    color: Theme.bgInput
                    border.color: Theme.borderSubtle
                    radius: Theme.radiusSmall

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        text: root.controller.selectedItem.name || "-"
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSizeNormal
                        elide: Text.ElideRight
                    }
                }

                Text {
                    text: "GID: " + (root.controller.selectedItem.gid || "-")
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeSmall
                }

                Text {
                    text: "Save to:"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeNormal
                    horizontalAlignment: Text.AlignRight
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 24
                    color: Theme.bgInput
                    border.color: Theme.borderSubtle
                    radius: Theme.radiusSmall

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        text: root.controller.selectedItem.saveDir || root.controller.defaultSaveDir
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSizeNormal
                        elide: Text.ElideMiddle
                    }
                }

                RowLayout {
                    spacing: 6

                    Rectangle {
                        implicitWidth: 82
                        implicitHeight: 24
                        radius: Theme.radiusSmall
                        opacity: root.controller.selectedGid !== "" ? 1.0 : 0.4
                        color: chgDirMouse.containsMouse ? Theme.rowHover : Theme.bgHeader
                        border.color: Theme.borderSubtle

                        Text {
                            anchors.centerIn: parent
                            text: "Change Path"
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        MouseArea {
                            id: chgDirMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: root.controller.selectedGid !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (root.controller.selectedGid !== "") {
                                    var cur = root.controller.selectedItem.saveDir || root.controller.defaultSaveDir
                                    var picked = root.controller.browseFolder(cur)
                                    if (picked !== "") {
                                        root.controller.changeDownloadPath(root.controller.selectedGid, picked)
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        implicitWidth: 82
                        implicitHeight: 24
                        radius: Theme.radiusSmall
                        color: openDirMouse.containsMouse ? Theme.rowHover : Theme.bgHeader
                        border.color: Theme.borderSubtle

                        Text {
                            anchors.centerIn: parent
                            text: "Open Folder"
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        MouseArea {
                            id: openDirMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var folder = root.controller.selectedItem.saveDir || root.controller.defaultSaveDir
                                root.controller.openFolder(folder)
                            }
                        }
                    }
                }
            }
        }
    }

    // 2. Download Overview Summary Panel
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 62
        color: Theme.bgSecondary
        border.color: Theme.borderSubtle
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.topMargin: 4
            anchors.bottomMargin: 4
            spacing: 2

            Text {
                text: "Download Overview"
                color: Theme.statusActive
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 4
                rowSpacing: 2
                columnSpacing: 24

                Text {
                    text: "Total Tasks: " + root.controller.totalPackages
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeNormal
                }
                Text {
                    text: "Total Bytes: " + root.controller.totalBytesStr
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeNormal
                }
                Text {
                    text: "Bytes Loaded: " + root.controller.loadedBytesStr
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeNormal
                }
                Text {
                    text: "Open Connections: " + root.controller.openConnections
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeNormal
                }

                Text {
                    text: "Running Downloads: " + root.controller.activeDownloads
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSizeNormal
                }
                Text {
                    text: "Download Speed: " + root.controller.globalSpeedStr
                    color: Theme.accentBlue
                    font.pixelSize: Theme.fontSizeNormal
                    font.bold: true
                }
                Text {
                    text: "Remaining Bytes: " + root.controller.remainingBytesStr
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeNormal
                }
                Text {
                    text: "Global ETA: " + root.controller.globalEtaStr
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeNormal
                }
            }
        }
    }

    // 3. Bottom Quick Action & Filter Bar
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Theme.bottomBarHeight
        color: Theme.bgHeader
        border.color: Theme.borderSubtle
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            // + Add New Links Button
            Rectangle {
                implicitWidth: 125
                implicitHeight: 24
                radius: Theme.radiusSmall
                color: addBottomMouse.containsMouse ? Theme.rowHover : Theme.bgPanel
                border.color: Theme.borderSubtle

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        text: "+"
                        color: Theme.statusActive
                        font.pixelSize: 14
                        font.bold: true
                    }
                    Text {
                        text: "Add New Links"
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSizeNormal
                        font.bold: true
                    }
                }

                MouseArea {
                    id: addBottomMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openAddLinksRequested()
                }
            }

            // Live Search Input
            TextField {
                id: searchInput
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                placeholderText: "Please enter the file name you are looking for..."
                placeholderTextColor: Theme.textMuted
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeNormal
                verticalAlignment: TextInput.AlignVCenter
                leftPadding: 8
                rightPadding: 8
                onTextChanged: root.controller.downloadModel.setSearchText(text)

                background: Rectangle {
                    color: Theme.bgInput
                    radius: Theme.radiusSmall
                    border.color: searchInput.activeFocus ? Theme.borderFocus : Theme.borderSubtle
                    border.width: 1
                }
            }

            // Status Filter Selector
            RowLayout {
                spacing: 4

                Repeater {
                    model: [
                        { label: "All Downloads", value: "all" },
                        { label: "Active", value: "active" },
                        { label: "Finished", value: "complete" }
                    ]

                    delegate: Rectangle {
                        property bool isCurrent: root.currentFilter === modelData.value
                        implicitWidth: filterLbl.implicitWidth + 14
                        implicitHeight: 24
                        radius: Theme.radiusSmall
                        color: isCurrent ? Theme.rowSelected : Theme.bgPanel
                        border.color: isCurrent ? Theme.borderFocus : Theme.borderSubtle

                        Text {
                            id: filterLbl
                            anchors.centerIn: parent
                            text: modelData.label
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.currentFilter = modelData.value
                                root.controller.downloadModel.setStatusFilter(modelData.value)
                            }
                        }
                    }
                }
            }
        }
    }

    property string currentFilter: "all"
}
