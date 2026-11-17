import QtQuick
import Quickshell
import "../core"
import "decor"

// Optimistic slider: follows the pointer locally while dragging, sends at most one intent per
// frame (and only while the pointer is held, Ma), and shows the daemon value otherwise.
// Keyboard: Tab focuses it; Left/Down and Right/Up step by `step`, PageUp/PageDown by 10 %, Home
// and End go to the ends. A key press is an event, so each press sends one intent. The knob keeps
// showing the daemon value until it answers, so only values in effect are shown (Shōjiki).
// `unavailable`: there is no level to show (the caller says why). Then no track, fill or knob is
// drawn, only a dim "⊘", and the control takes no pointer, key or Tab input (B2).
Item {
    id: s
    property real value: 0              // daemon value
    property color track: Theme.outline
    property color fill: Theme.colorOr("slider.fill", Theme.accent)
    property string a11y: ""            // translated accessible name, from the caller
    property real step: 0.05
    property bool unavailable: false
    // I484: a slider that stands upright (a side bar's): drawn upright, the value rising from the bottom — its face is
    // told so (SliderBase `vertical`) and draws its own upright form, where the slider used to be turned as a whole (a
    // turned face has its light, its bevels and its pixel grid turned with it).
    property bool vertical: false
    signal moved(real v)
    // K61 (docs/ux/texture.md "Controls"): the track, its fill and the knob are opaque, so they carry the relief, in a
    // window that shares its sheet (Relief makes its own otherwise). Nothing is drawn while unavailable.
    readonly property var qsw: Window.window ? QsWindow.window : null
    readonly property bool ownRelief: Theme.texControls && !s.unavailable && !!(qsw && qsw.tileSheet)

    property bool dragging: false
    property real local: 0
    property bool dirty: false
    // A key target the daemon has not confirmed yet; repeated keys build on it.
    property bool keyPending: false
    property real keyTarget: 0
    // Clamped (B12): a level past the scale, such as svc.audio's 1.5, must not draw past the track.
    readonly property real shown: Math.max(0, Math.min(1, dragging ? local : value))

    implicitWidth: vertical ? 20 : 120
    implicitHeight: vertical ? 120 : 20
    activeFocusOnTab: !s.unavailable

    onValueChanged: if (keyPending && Math.abs(value - keyTarget) < 0.005) keyPending = false
    // Input in flight when the level goes away gets no release and no answer: drop it.
    onUnavailableChanged: if (unavailable) { dragging = false; dirty = false; keyPending = false }

    function setKey(v) {
        keyTarget = Math.max(0, Math.min(1, v)); keyPending = true; s.moved(keyTarget)
    }
    function nudge(d) { setKey((keyPending ? keyTarget : value) + d) }

    Keys.enabled: !s.unavailable
    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Left: case Qt.Key_Down: s.nudge(-s.step); break
        case Qt.Key_Right: case Qt.Key_Up: s.nudge(s.step); break
        case Qt.Key_PageDown: s.nudge(-0.1); break
        case Qt.Key_PageUp: s.nudge(0.1); break
        case Qt.Key_Home: s.setKey(0); break
        case Qt.Key_End: s.setKey(1); break
        default: return
        }
        event.accepted = true
    }
    Accessible.role: Accessible.Slider
    Accessible.name: s.a11y

    // Keycap chrome (K42): a thick outlined pill whose fill carries the level, and a ring-coloured knob. Square corners
    // (radius.full 0) square the track and the knob.
    readonly property int trackH: Theme.ringW > 0 ? 12 : 6
    Rectangle {
        id: trackRect
        anchors.verticalCenter: s.vertical ? undefined : parent.verticalCenter
        anchors.horizontalCenter: s.vertical ? parent.horizontalCenter : undefined
        width: s.vertical ? s.trackH : parent.width
        height: s.vertical ? parent.height : s.trackH
        radius: Math.min(Math.min(width, height) / 2, Theme.rFull)
        color: Theme.ringW > 0 ? Theme.ring : s.track
        border.width: Theme.ringW > 0 ? Theme.outlineW : 0
        border.color: Theme.outlineColor
        visible: !s.unavailable && !face.has
        Rectangle {
            readonly property real bw: trackRect.border.width
            readonly property real across: (s.vertical ? parent.width : parent.height) - 2 * bw
            readonly property real along: Math.max(across, ((s.vertical ? parent.height : parent.width) - 2 * bw) * s.shown)
            x: bw
            y: s.vertical ? parent.height - bw - along : bw
            width: s.vertical ? across : along
            height: s.vertical ? along : across
            radius: Math.min(across / 2, Theme.rFull); color: s.fill
            visible: s.shown > 0
        }
        // The relief over the track and its fill (the outline stays flat).
        Loader {
            active: s.ownRelief
            anchors.fill: parent
            anchors.margins: trackRect.border.width
            sourceComponent: Relief { anchors.fill: parent; radius: Math.max(0, trackRect.radius - trackRect.border.width) }
        }
    }
    Rectangle {
        id: handle
        width: Theme.ringW > 0 ? 18 : 12; height: width; radius: Math.min(width / 2, Theme.rFull)
        color: Theme.ringW > 0 ? Theme.ring : s.fill
        border.width: Theme.ringW > 0 ? Theme.outlineW : 0
        border.color: Theme.outlineColor
        x: s.vertical ? (s.width - width) / 2 : (s.width - width) * s.shown
        y: s.vertical ? (s.height - height) * (1 - s.shown) : (s.height - height) / 2
        visible: !s.unavailable && !face.has
        // The relief over the knob (its ring stays flat).
        Loader {
            active: s.ownRelief
            anchors.fill: parent
            anchors.margins: handle.border.width
            sourceComponent: Relief { anchors.fill: parent; radius: Math.max(0, handle.radius - handle.border.width) }
        }
    }
    // W53.3: the look's slider part (`[slots] slider`, contract decor/slider/SliderBase.qml) draws the track, fill and
    // thumb instead of the two above — 11's rail with its ringed thumb, 9x's trackbar; nothing is made without one.
    DecorHost {
        id: face
        slot: "slider"
        anchors.fill: parent
        visible: !s.unavailable
        onLoaded: {
            item.value = Qt.binding(function () { return s.shown })
            item.pressed = Qt.binding(function () { return s.dragging })
            item.vertical = Qt.binding(function () { return s.vertical })
            if (item.hovered !== undefined) item.hovered = Qt.binding(function () { return sliderHover.hovered })
        }
    }
    HoverHandler { id: sliderHover; enabled: face.has && !s.unavailable }
    // Stands in for the level (VolumeFace draws the same mark for no audio). Dim: it is not an input.
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        anchors.centerIn: parent
        visible: s.unavailable
        color: Theme.dim
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: "⊘"
    }
    FrameAnimation {
        running: s.dragging
        onTriggered: if (s.dirty) { s.dirty = false; s.moved(s.local) }
    }
    function setFrom(x, y) {
        local = Math.max(0, Math.min(1, vertical ? 1 - y / height : x / width)); dirty = true
    }
    MouseArea {
        anchors.fill: parent
        // The hit area grows to the control height; the drawn track keeps its size.
        readonly property real grow: Math.max(0, (Theme.controlH - (s.vertical ? s.width : s.height)) / 2)
        anchors.topMargin: s.vertical ? 0 : -grow
        anchors.bottomMargin: s.vertical ? 0 : -grow
        anchors.leftMargin: s.vertical ? -grow : 0
        anchors.rightMargin: s.vertical ? -grow : 0
        enabled: !s.unavailable
        // (the margins move the area's origin: the point is read in the slider's own coordinates)
        onPressed: m => { s.dragging = true; var p = mapToItem(s, m.x, m.y); s.setFrom(p.x, p.y) }
        onPositionChanged: m => { if (s.dragging) { var p = mapToItem(s, m.x, m.y); s.setFrom(p.x, p.y) } }
        onReleased: { s.dragging = false; s.moved(s.local); s.dirty = false }
        onCanceled: { s.dragging = false; s.dirty = false }
    }
    FocusRing {
        anchors.fill: parent
        shown: s.activeFocus
        corner: Theme.rSm
    }
}
