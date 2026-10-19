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
    width: Math.min(640, parent ? parent.width - 40 : 640)
    height: 380
    padding: 0

    required property var controller

    property int detectedTotal: 0
    property int detectedHttp: 0
    property int detectedMagnets: 0
    property bool makeDefaultDir: false
    property bool routeViaAlldebrid: true

    function refreshLinkStats() {
        var stats = root.controller.analyzeLinksText(urlInput.text)
        root.detectedTotal = stats.total || 0
        root.detectedHttp = stats.httpCount || 0
        root.detectedMagnets = stats.magnetCount || 0
    }

    function openWithFocus(prefillText) {
        urlInput.text = prefillText ? prefillText : ""
        saveDirInput.text = root.controller.defaultSaveDir
        root.makeDefaultDir = false
        root.routeViaAlldebrid = root.controller.alldebridEnabled
        root.refreshLinkStats()
        root.open()
        urlInput.forceActiveFocus()
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

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "Add New Download Link(s)"
                color: Theme.textPrimary
                font.pixelSize: 14
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            // Live Smart Link Detection Counter
            Rectangle {
                implicitWidth: counterTxt.implicitWidth + 16
                implicitHeight: 22
                radius: Theme.radiusSmall
                color: root.detectedTotal > 0 ? Theme.rowSelected : Theme.bgInput
                border.color: root.detectedTotal > 0 ? Theme.borderFocus : Theme.borderSubtle

                Text {
                    id: counterTxt
                    anchors.centerIn: parent
                    text: root.detectedTotal > 0
                          ? "Detected: " + root.detectedTotal + " link(s) (" + root.detectedHttp + " Direct, " + root.detectedMagnets + " Magnet)"
                          : "Smart Parser: Paste any text or multiple links"
                    color: root.detectedTotal > 0 ? Theme.textPrimary : Theme.textMuted
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }

        Text {
            text: "Paste links separated by spaces, newlines, or mixed inside text (automatically extracted):"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeNormal
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            TextArea {
                id: urlInput
                placeholderText: "https://example.com/archive.part1.rar https://example.com/archive.part2.rar\nmagnet:?xt=urn:btih:..."
                placeholderTextColor: Theme.textMuted
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeNormal
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                onTextChanged: root.refreshLinkStats()

                background: Rectangle {
                    color: Theme.bgInput
                    radius: Theme.radiusSmall
                    border.color: urlInput.activeFocus ? Theme.borderFocus : Theme.borderSubtle
                }
            }
        }

        // Save Directory + Browse Button
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
                Layout.preferredHeight: 28
                text: root.controller.defaultSaveDir
                color: Theme.textPrimary
                font.pixelSize: Theme.fontSizeNormal
                selectByMouse: true
                leftPadding: 8
                rightPadding: 8

                background: Rectangle {
                    color: Theme.bgInput
                    radius: Theme.radiusSmall
                    border.color: saveDirInput.activeFocus ? Theme.borderFocus : Theme.borderSubtle
                }
            }

            Rectangle {
                implicitWidth: 85
                implicitHeight: 28
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

        // Options Row: Set as Default Folder + Use AllDebrid
        RowLayout {
            Layout.fillWidth: true
            spacing: 18

            // Checkbox: Set as Default Download Dir
            RowLayout {
                spacing: 6
                Rectangle {
                    width: 16
                    height: 16
                    radius: 3
                    color: root.makeDefaultDir ? Theme.accentBlue : Theme.bgInput
                    border.color: Theme.borderSubtle

                    Text {
                        anchors.centerIn: parent
                        text: "✓"
                        visible: root.makeDefaultDir
                        color: "#FFFFFF"
                        font.pixelSize: 11
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.makeDefaultDir = !root.makeDefaultDir
                    }
                }
                Text {
                    text: "Save as default download directory"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeNormal
                }
            }

            // Checkbox: Route via AllDebrid
            RowLayout {
                spacing: 6
                visible: root.controller.alldebridEnabled
                Rectangle {
                    width: 16
                    height: 16
                    radius: 3
                    color: root.routeViaAlldebrid ? Theme.statusActive : Theme.bgInput
                    border.color: Theme.borderSubtle

                    Text {
                        anchors.centerIn: parent
                        text: "✓"
                        visible: root.routeViaAlldebrid
                        color: "#FFFFFF"
                        font.pixelSize: 11
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.routeViaAlldebrid = !root.routeViaAlldebrid
                    }
                }
                Text {
                    text: "Unrestrict via AllDebrid (Safe Rate-Limited)"
                    color: Theme.statusActive
                    font.pixelSize: Theme.fontSizeNormal
                }
            }

            Item { Layout.fillWidth: true }
        }

        // Action Buttons
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                implicitWidth: 125
                implicitHeight: 30
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
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                implicitWidth: 90
                implicitHeight: 30
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
                implicitWidth: 145
                implicitHeight: 30
                radius: Theme.radiusSmall
                opacity: root.detectedTotal > 0 ? 1.0 : 0.5
                color: startMouse.containsMouse && root.detectedTotal > 0 ? "#4A89C7" : Theme.accentBlue

                Text {
                    anchors.centerIn: parent
                    text: root.detectedTotal > 1
                          ? "Download (" + root.detectedTotal + ")"
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
                    onClicked: {
                        if (root.detectedTotal > 0) {
                            root.controller.addLinks(
                                urlInput.text,
                                saveDirInput.text,
                                root.makeDefaultDir,
                                root.routeViaAlldebrid
                            )
                            root.close()
                        }
                    }
                }
            }
        }
    }
}
