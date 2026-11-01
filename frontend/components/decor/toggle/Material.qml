import QtQuick
import "../../../core"
import "../.."

// Material (W53.8, docs/ux/styles.md "material"): Material 3's switch (material-web tokens md.comp.switch, read
// 2026-11-01): a 52 × 32 full-round track; on, the track in `primary` (accent) and a 24 px handle in `on-primary` with the
// check icon (16 px, Material Symbols "check") in primary; off, the track in surface-container-highest inside a 2 px
// `outline` ring and a 16 px handle in `outline`, no icon; pressed, the handle grows to 28. A 40 px state layer round the
// handle while hovered or pressed (on-surface / primary at 8 % / 10 %). Disabled: 38 % (the shell's 50 %). The handle
// slides on the look's standard curve; static at rest.
ToggleBase {
    id: tg
    property bool hovered: false
    property bool focused: false
    // The focus ring's corner (ToggleSwitch reads it): the track is a full round.
    readonly property real corner: height / 2
    implicitWidth: 52
    implicitHeight: 32
    opacity: enabled ? 1 : 0.5
    readonly property real d: pressed ? 28 : (checked ? 24 : 16)
    readonly property real ring: 2

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: tg.checked ? Theme.accent : Theme.color("color.surface_container_highest", Theme.containerHigh)
        border.width: tg.checked ? 0 : tg.ring
        border.color: Theme.color("color.outline", Theme.dim)
    }
    // The state layer: a 40 px disc round the handle while the pointer is on it or it is held.
    Rectangle {
        visible: tg.hovered || tg.pressed
        width: 40
        height: 40
        radius: 20
        x: handle.x + handle.width / 2 - 20
        y: (tg.height - 40) / 2
        color: Qt.alpha(tg.checked ? Theme.accent : Theme.fg, tg.pressed ? 0.10 : 0.08)
    }
    Rectangle {
        id: handle
        width: tg.d
        height: tg.d
        radius: tg.d / 2
        y: (tg.height - height) / 2
        // The handle's centre sits 16 px in from the track's end (the 32 px track's half), on or off.
        x: (tg.checked ? tg.width - 16 : 16) - width / 2
        color: tg.checked ? Theme.fgOnAccent : Theme.color("color.outline", Theme.dim)
        Behavior on x {
            enabled: Theme.timed
            NumberAnimation { duration: Theme.fastMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.fastCurve }
        }
        Behavior on width {
            enabled: Theme.timed
            NumberAnimation { duration: Theme.fastMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.fastCurve }
        }
        Icon {
            visible: tg.checked
            anchors.centerIn: parent
            name: "check"
            glyph: "✓"
            filled: true
            size: 16
            color: Theme.accent
        }
    }
}
