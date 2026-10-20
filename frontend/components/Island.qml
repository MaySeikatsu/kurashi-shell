import QtQuick
import "../core"
import "../core/mods.js" as Mods
import "faces"
import "island"

// Island (島): the daemon decides the face (runtime.island.*); this only morphs between faces, and shows what the
// decision adds beside it: the secondary activity as a minimal glyph and "+N" for the rest (K30), and "as of" when the
// face's content is stale (Shōjiki). The face's peek line is the Stage's, shown while the pointer is on the island (K35).
// One component per core face id (faces/); each watches only the docs it renders and only while it is
// visible. Interruptible: width/opacity are Behaviors, so a new face retargets mid-flight.
// Animations are gated on `visible` (Ma) and armed only after the first layout so startup does
// not animate. A mod's face (K28) draws its Face.qml, loaded only while it is the face; a face the
// `mods` document names no file for (mod off, or not yet loaded) falls back to the clock, not to nothing.
// Input is presentational: the surface passes island.main's resolved bindings in `slots` and gets
// `activated(slot)` for a bound slot only. What a slot does is the daemon's call (input.dispatch).
// On a side bar (`vertical`, set by the bar) the pill is a column as wide as the bar is thick: the face's glyph over a
// short value, the stale time stacked at its foot, and the secondary glyph and "+N" stacked under the pill. Nothing
// crosses the bar's width and no text is turned (I85). A mod's face gets `vertical` when it declares it, else the pill
// shows the face's glyph.
// W21 (docs/ux/island.md "Session 9 morph"): the pill is a Block (keycap chrome under the sekai decor) whose size follows a
// spring (Theme.spring/damping; snaps when Theme.springOn is false) and grows a few px while the pointer is on it. On a top
// or bottom bar it reports its rect to IslandGeom; while the Stage's shape has taken it (the island's card is out on this
// output) the pill is not drawn, so the shape that grew out of it is the only island on screen.
Item {
    id: isl
    property string face: "clock"
    // `{ "<slot>": {action, source, forced_by?} }`; an unbound slot is absent, never null.
    property var slots: ({})
    // left, right, middle, hover, scroll_up, scroll_down, shift_scroll_up, shift_scroll_down
    signal activated(string slot)

    function isBound(slot) { return slots[slot] !== undefined }

    property string reason: "default"   // why the daemon picked this face
    // `manual` (island.next/prev/pin via the arbiter) is a deliberate user choice, like `user`.
    readonly property bool byUser: reason === "user" || reason === "manual"
    // The bar's edge is a side one: the pill is a column (see the header).
    property bool vertical: false

    // The arbiter's document beyond the face (K30): the secondary face, the overflow count, and per face its peek line
    // and stale time. The island reads it itself, so the bars keep their one `face` and `reason` binding.
    Watch { doc: "runtime.island.main" }
    readonly property var island: Store.docs["runtime.island.main"] || ({})
    readonly property string secondaryFace: island.secondary ?? ""
    readonly property int overflowN: island.overflow ?? 0
    function detailOf(f) { return (island.detail || ({}))[f] ?? "" }
    // Wall-clock ms the face's content is "as of", or -1 when the face is not stale.
    function staleOf(f) { var s = (island.stale_at || ({}))[f]; return s === undefined || s === null ? -1 : s }
    function timeOf(ms) { return Qt.formatTime(new Date(ms), "hh:mm") }
    // The minimal icon of a face beside the pill (Material Symbols name; glyphOf is its text fallback).
    function iconOf(f) {
        switch (f) {
        case "clock": return "schedule"
        case "media": return "music_note"
        case "volume": return "volume_up"
        case "brightness": return "brightness_6"
        case "notifications": return "notifications"
        case "power": return "bolt"
        case "bluetooth": return "bluetooth"
        default: return "circle"
        }
    }
    // The minimal glyph of a face beside the pill; a mod's face has none, so it gets a dot.
    function glyphOf(f) {
        switch (f) {
        case "clock": return "◷"
        case "media": return "♪"
        case "volume": return "♫"
        case "brightness": return "☼"
        case "notifications": return "◉"
        case "power": return "⚡︎"
        case "bluetooth": return "ᛒ"
        default: return "•"
        }
    }

    readonly property var modsDoc: Store.docs["mods"]
    readonly property bool coreFace: ["clock", "media", "volume", "brightness", "notifications", "power", "bluetooth"].indexOf(face) >= 0
    readonly property bool isModFace: !coreFace && face !== "" && Mods.qmlOf(modsDoc, "island-face:" + face) !== ""
    readonly property string shown: (coreFace || isModFace) ? face : "clock"
    readonly property bool isStale: staleOf(shown) >= 0
    // A transient face is glanced at and its pill says it; the peek line is for the faces that stay.
    readonly property bool isTransient: ["volume", "brightness", "power", "bluetooth"].indexOf(shown) >= 0
    readonly property bool animate: armed && visible
    property bool armed: false
    Component.onCompleted: armed = true

    // The peek (island brief 4, K35): while the pointer is on the island, a face that stays and has a line from the daemon
    // is offered to the Stage, which draws that line under the bar. Leaving or clicking ends it (WCAG 1.4.13: dismissible,
    // hoverable). Pointer-only by design: the Stage holds the keyboard, and the island's keys are its own bindings.
    property bool pointerIn: false
    property bool peekDismissed: false
    readonly property string peekText: isTransient ? "" : detailOf(shown)
    // The Stage draws a side bar's peek beside the bar, aligned to the island (I67), so it is offered on every edge.
    property bool peekable: true
    // The output this island's bar is on: the Stage draws the peek there.
    property string peekOutput: ""
    PeekSource {
        target: isl
        source: "island:main"
        output: isl.peekOutput
        hovered: isl.pointerIn && !isl.peekDismissed
        enabled: isl.peekable && isl.peekText !== ""
    }

    readonly property real faceW: {
        var l = [clock, media, volume, bright, notifs, power, bluetooth]
        for (var i = 0; i < l.length; i++)
            if (l[i].current && l[i].item) return l[i].item.wantW
        if (modFace.item) return modFace.item.wantW ?? modFace.item.implicitWidth
        return 0
    }
    // A side bar's pill: the current face's natural height (a mod's face when it declares `vertical`, else the glyph).
    readonly property real faceH: {
        var l = [clock, media, volume, bright, notifs, power, bluetooth]
        for (var i = 0; i < l.length; i++)
            if (l[i].current && l[i].item) return l[i].item.wantH
        if (isModFace) return modVertical ? (modFace.item ? (modFace.item.wantH ?? modFace.item.implicitHeight) : 0) : modGlyph.implicitHeight
        return 0
    }
    // The tail at the pill's right end: the "as of" label while the face is stale. Measured with TextMetrics, which is
    // synchronous (a hidden Text is not laid out, so its implicit width is not there when the pill needs it).
    TextMetrics {
        id: staleM
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: isl.isStale ? I18n.tr("island.stale").replace("{t}", isl.timeOf(isl.staleOf(isl.shown))) : ""
    }
    readonly property real staleW: isStale ? staleM.advanceWidth : 0
    readonly property real tailW: staleW > 0 ? staleW + Theme.gap : 0
    // The chrome's outline and (half) ring sit inside the pill: the faces keep their padding inside them.
    readonly property real chromeIn: Theme.outlineW + Theme.ringW * 0.5
    // While the pointer is on the island the pill grows a few px (with the peek), on a spring.
    readonly property real grow: pointerIn && !vertical ? 1 : 0
    readonly property real pillW: faceW + 2 * Theme.pad + tailW + 2 * chromeIn + grow * 2 * Theme.xs
    readonly property real extrasW: extras.visible ? Theme.xs + extras.width : 0
    // A side bar's pill: the faces' column with a little air above and below, and the stale time stacked at the foot.
    readonly property int vpad: Theme.xs + 2
    readonly property real tailH: vertical && isStale ? staleCol.implicitHeight + Theme.xs : 0
    // The pill's face (the keycap's shadow comes on top, below it).
    readonly property real pillFaceH: vertical ? vpad + faceH + tailH + vpad + 2 * chromeIn : Theme.barH - 10 + grow * 2
    readonly property real pillH: pillFaceH + Theme.shadowDy
    readonly property real extrasH: extras.visible ? Theme.xs + extras.height : 0

    height: vertical ? pillH + extrasH : pillH
    width: vertical ? Theme.barH - 8 : pillW + extrasW
    readonly property bool springy: isl.animate && Theme.springOn
    Behavior on width {
        enabled: isl.springy
        SpringAnimation { spring: Theme.spring; damping: Theme.damping; epsilon: 0.25 }
    }
    Behavior on height {
        enabled: isl.springy
        SpringAnimation { spring: Theme.spring; damping: Theme.damping; epsilon: 0.25 }
    }

    // The Stage's shape has this output's pill (W21): the pill is not drawn while it is out.
    readonly property bool taken: peekOutput !== "" && IslandGeom.takenOn === peekOutput
    // The rest rect the Stage's shape starts from and folds back into: the pill's target size and its centre's offset
    // from the bar's centre (the bar centres the whole island, extras included). Top and bottom bars only.
    readonly property var geom: [peekOutput, pillW, pillFaceH, -extrasW / 2, shown, vertical]
    onGeomChanged: if (!vertical) IslandGeom.report(peekOutput, pillW, pillFaceH, -extrasW / 2, shown)

    // The pill is what is drawn: a Block (flat fill, or a keycap with a thin ring so it fits the bar); the faces paint
    // inside it and nothing outside it. Its size follows the same spring as the island's, so the morph is one motion.
    Block {
        id: pill
        x: 0
        y: 0
        width: isl.vertical ? isl.width : isl.pillW
        height: isl.pillH
        radius: Theme.rFull
        ringScale: 0.5
        // A short soft shadow: the bar's window ends a few px under the pill.
        softScale: 0.3
        // The panel's opacity (glass sees through); an outlined chrome with no shadow (line) draws a box on the strip,
        // no fill behind the face (Bar.qml).
        fill: Theme.outlineW > 0 && Theme.shadowDy <= 0 && Theme.softR <= 0 ? "transparent"
            : Qt.alpha(Theme.containerHigh, Theme.panel.a)
        animate: isl.animate
        opacity: isl.taken ? 0 : 1
        Behavior on width {
            enabled: isl.springy
            SpringAnimation { spring: Theme.spring; damping: Theme.damping; epsilon: 0.25 }
        }
        Behavior on height {
            enabled: isl.springy
            SpringAnimation { spring: Theme.spring; damping: Theme.damping; epsilon: 0.25 }
        }

        Item {
            id: faces
            x: isl.vertical ? 0 : 0
            y: isl.vertical ? isl.vpad : 0
            width: isl.vertical ? parent.width : parent.width - isl.tailW
            height: isl.vertical ? isl.faceH : parent.height
            clip: true

            // A face exists only while it is current or still fading out: the idle faces cost
            // ~1 MiB per bar, i.e. per output (B7, docs/BENCH.md).
            FaceSlot { id: clock; face: "clock"; sourceComponent: ClockFace { current: clock.current; animate: isl.animate; vertical: isl.vertical } }
            FaceSlot { id: media; face: "media"; sourceComponent: MediaFace { current: media.current; animate: isl.animate; vertical: isl.vertical } }
            FaceSlot { id: volume; face: "volume"; sourceComponent: VolumeFace { current: volume.current; animate: isl.animate; vertical: isl.vertical } }
            FaceSlot { id: bright; face: "brightness"; sourceComponent: BrightnessFace { current: bright.current; animate: isl.animate; vertical: isl.vertical } }
            FaceSlot { id: notifs; face: "notifications"; sourceComponent: NotificationsFace { current: notifs.current; animate: isl.animate; vertical: isl.vertical } }
            FaceSlot {
                id: power
                face: "power"
                sourceComponent: PowerFace { current: power.current; animate: isl.animate; vertical: isl.vertical; line: isl.detailOf("power") }
            }
            FaceSlot {
                id: bluetooth
                face: "bluetooth"
                sourceComponent: BluetoothFace { current: bluetooth.current; animate: isl.animate; vertical: isl.vertical; line: isl.detailOf("bluetooth") }
            }

            // A mod's compact face (K28): its Face.qml, instantiated only while it is the face. It is not faded:
            // the next face replaces it at once, and the pill's width still animates.
            ModLoader {
                id: modFace
                provide: "island-face:" + isl.face
                shown: isl.isModFace
                anchors.centerIn: parent
            }
            // A mod's face on a side bar that does not declare `vertical`: its glyph, the face's full text is the peek's.
            Text {
                id: modGlyph
                visible: isl.vertical && isl.isModFace && !isl.modVertical
                anchors.centerIn: parent
                color: Theme.dim
                font.pixelSize: Theme.fs
                text: isl.glyphOf(isl.face)
            }
        }

        // The tail of a top or bottom bar (see tailW): the "as of" label at the right end while the face is stale.
        Text {
            id: staleLabel
            visible: isl.isStale && !isl.vertical
            anchors { right: parent.right; rightMargin: Theme.pad; verticalCenter: parent.verticalCenter }
            width: isl.staleW
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: staleM.text
        }
        // A side bar's tail: the stale hour over the minute (the words are the accessible name).
        Column {
            id: staleCol
            visible: isl.isStale && isl.vertical
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: isl.vpad }
            Accessible.role: Accessible.StaticText
            Accessible.name: isl.isStale ? I18n.tr("island.stale").replace("{t}", isl.timeOf(isl.staleOf(isl.shown))) : ""
            Text {
                Accessible.ignored: true
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: isl.isStale ? Qt.formatTime(new Date(isl.staleOf(isl.shown)), "hh") : ""
            }
            Text {
                Accessible.ignored: true
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: isl.isStale ? Qt.formatTime(new Date(isl.staleOf(isl.shown)), "mm") : ""
            }
        }
    }

    // A mod's face gets `vertical` when its QML declares it (ModLoader is not involved: the binding is here).
    readonly property bool modVertical: modFace.item !== null && modFace.item !== undefined && ("vertical" in modFace.item)
    Binding {
        target: modFace.item
        property: "vertical"
        value: isl.vertical
        when: isl.modVertical
    }

    // Keeps its face while current and, after that, until the face has faded out.
    component FaceSlot: Loader {
        id: slot
        required property string face
        readonly property bool current: isl.shown === face
        property bool fading: false
        onCurrentChanged: fading = !current && item !== null && item.visible
        anchors.fill: parent
        active: current || fading
        Connections {
            target: slot.item
            function onVisibleChanged() { if (!slot.item.visible) slot.fading = false }
        }
    }

    // Beside the pill: the next live activity of another face, minimal (20 px), then "+N" for the rest (K30).
    // It is one target with the island: a pointer on it is a pointer on the island. A side bar stacks them under the
    // pill: the secondary glyph, then "+N".
    Item {
        id: extras
        x: isl.vertical ? (isl.width - width) / 2 : pill.width + Theme.xs
        y: isl.vertical ? pill.height + Theme.xs : (isl.height - height) / 2
        visible: isl.secondaryFace !== "" || isl.overflowN > 0
        height: isl.vertical
            ? (second.visible ? second.height : 0) + (over.visible ? (second.visible ? Theme.xs : 0) + over.implicitHeight : 0)
            : 20
        width: isl.vertical
            ? Math.max(second.visible ? second.width : 0, over.visible ? over.implicitWidth : 0)
            : (second.visible ? second.width : 0) + (over.visible ? (second.visible ? Theme.xs : 0) + over.implicitWidth : 0)

        Block {
            id: second
            visible: isl.secondaryFace !== ""
            x: isl.vertical ? (extras.width - width) / 2 : 0
            y: isl.vertical ? 0 : (extras.height - height) / 2
            width: 20 + Theme.shadowDy
            height: 20 + Theme.shadowDy
            radius: Theme.rFull
            ringScale: 0
            softScale: 0
            fill: Theme.containerHigh
            flatBorder: Theme.outline
            animate: isl.animate
            Accessible.role: Accessible.StaticText
            Accessible.name: isl.secondaryFace ? I18n.tr("island.secondary").replace("{face}", I18n.tr("island.face." + isl.secondaryFace)) : ""
            Icon {
                anchors.centerIn: parent
                name: isl.iconOf(isl.secondaryFace)
                glyph: isl.glyphOf(isl.secondaryFace)
                filled: true
                size: Theme.fsCaption + 2
                color: Theme.dim
            }
        }
        Text {
            id: over
            visible: isl.overflowN > 0
            x: isl.vertical ? (extras.width - width) / 2 : (second.visible ? second.width + Theme.xs : 0)
            y: isl.vertical ? (second.visible ? second.height + Theme.xs : 0) : (extras.height - height) / 2
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: "+" + isl.overflowN
            Accessible.role: Accessible.StaticText
            Accessible.name: I18n.tr("island.overflow").replace("{n}", isl.overflowN)
        }
    }

    // The pointer target is the bar's full thickness (review #11: at least 32 px), centred on the pill; on a side bar it
    // runs the length of the island with its marks. It is a sibling of the pill, not a child: a clipping parent does not
    // deliver pointer events to children outside it, and the pill keeps its clip.
    MouseArea {
        x: (isl.width - width) / 2
        y: (isl.height - height) / 2
        width: isl.vertical ? Theme.barH : isl.width
        height: isl.vertical ? isl.height : Theme.barH
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        // A pointer only promises a click when the left click does something (unbound = no pointer).
        cursorShape: isl.isBound("left") ? Qt.PointingHandCursor : Qt.ArrowCursor
        // Hover is an event, not a poll: one dispatch per entry into the island.
        onEntered: {
            isl.pointerIn = true
            isl.peekDismissed = false
            if (isl.isBound("hover")) isl.activated("hover")
        }
        onExited: isl.pointerIn = false
        onClicked: m => {
            // A click is an answer to the peek: it dismisses it until the pointer comes back.
            isl.peekDismissed = true
            var slot = m.button === Qt.RightButton ? "right" : m.button === Qt.MiddleButton ? "middle" : "left"
            if (isl.isBound(slot)) isl.activated(slot)
        }
        onWheel: w => {
            // Toolkits differ on which axis Shift+wheel reports, so with Shift either axis counts.
            var shift = (w.modifiers & Qt.ShiftModifier) !== 0
            var d = w.angleDelta.y !== 0 ? w.angleDelta.y : (shift ? w.angleDelta.x : 0)
            if (d === 0) return
            var slot = (shift ? "shift_scroll_" : "scroll_") + (d > 0 ? "up" : "down")
            if (isl.isBound(slot)) isl.activated(slot)
        }
    }
}
