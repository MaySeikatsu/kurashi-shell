import QtQuick

// The contract every frame shares (W25; shellseikatsu `Widgets/ThemeDecor.qml`'s radius/surfaceKind contract):
// FrameHost binds these. A frame fills its block's face (or a surface) and paints from tokens only (rule 4), so a
// frame pinned onto another palette still matches it. Static: no timer, no running animation unless `animate`.
Item {
    property real radius: 0
    // "card" | "small" | "ground"
    property string kind: "card"
    property bool pressed: false
    // Visible and springs on: a frame may run a one-shot motion (never an endless one: Ma).
    property bool animate: false
    // This frame draws a ground for kind "ground" (else the surface keeps its own).
    property bool grounds: true
    readonly property bool card: kind === "card"
    readonly property bool small: kind === "small"
    readonly property bool ground: kind === "ground"
    // Clear of rounded corners for edge ornaments.
    readonly property real cornerInset: radius * 0.4
}
