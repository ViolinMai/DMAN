pragma Singleton
import QtQuick

QtObject {
    // Core Surfaces (JDownloader-inspired high-contrast dark palette, modernized)
    readonly property color bgPrimary: "#181A1D"
    readonly property color bgSecondary: "#202327"
    readonly property color bgPanel: "#26292E"
    readonly property color bgHeader: "#2D3137"
    readonly property color bgInput: "#141619"

    // Table Rows
    readonly property color rowEven: "#1E2125"
    readonly property color rowOdd: "#23272C"
    readonly property color rowHover: "#2C323B"
    readonly property color rowSelected: "#2B4257"

    // Borders & Dividers
    readonly property color borderSubtle: "#343942"
    readonly property color borderFocus: "#4D88FF"

    // Typography
    readonly property color textPrimary: "#ECEFF4"
    readonly property color textSecondary: "#A5B0C0"
    readonly property color textMuted: "#6C7686"

    // Status & Accents
    readonly property color accentBlue: "#5B9BD5"
    readonly property color progressFill: "#6897BB"
    readonly property color progressBg: "#15181C"
    readonly property color statusActive: "#6CC644"
    readonly property color statusPaused: "#E5C07B"
    readonly property color statusError: "#E06C75"
    readonly property color statusFinished: "#73C991"

    // Sizing & Spacing
    readonly property int fontSizeSmall: 11
    readonly property int fontSizeNormal: 12
    readonly property int fontSizeHeader: 12
    readonly property int rowHeight: 28
    readonly property int headerHeight: 28
    readonly property int topBarHeight: 38
    readonly property int bottomBarHeight: 34
    readonly property int radiusSmall: 3
    readonly property int radiusMedium: 5
}
