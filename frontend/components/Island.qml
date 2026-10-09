import QtQuick
import "../core"
import "../core/mods.js" as Mods
import "faces"

// Island (島): the daemon decides the face (runtime.island.*); this only morphs between faces, and shows what the
// decision adds beside it: the secondary activity as a minimal glyph and "+N" for the rest (K30), the face's peek
// line while the pointer is on it (island brief 4), and "as of" when the face's content is stale (Shōjiki).
// One component per core face id (faces/); each watches only the docs it renders and only while it is
// visible. Interruptible: width/opacity are Behaviors, so a new face retargets mid-flight.
// Animations are gated on `visible` (Ma) and armed only after the first layout so startup does
// not animate. A mod's face (K28) draws its Face.qml, loaded only while it is the face; a face the
// `mods` document names no file for (mod off, or not yet loaded) falls back to the clock, not to nothing.
// Input is presentational: the surface passes island.main's resolved bindings in `slots` and gets
// `activated(slot)` for a bound slot only. What a slot does is the daemon's call (input.dispatch).
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

    // The peek (island brief 4): while the pointer is on the island, a face that stays and has a line from the daemon
    // shows that line in the pill's tail. It is inline, so nothing overlays other content and it stays exactly as long
    // as the pointer is on the island (hoverable and dismissible in the WCAG 1.4.13 sense: leaving or clicking hides it).
    // Pointer-only by design: the Stage holds the keyboard, and the island's keys are its own bindings.
    property bool pointerIn: false
    property bool peekDismissed: false
    readonly property string peekText: isTransient ? "" : detailOf(shown)
    readonly property bool peekOpen: pointerIn && !peekDismissed && peekText !== ""

    readonly property real faceW: {
        var l = [clock, media, volume, bright, notifs, power, bluetooth]
        for (var i = 0; i < l.length; i++)
            if (l[i].current && l[i].item) return l[i].item.wantW
        if (modFace.item) return modFace.item.wantW ?? modFace.item.implicitWidth
        return 0
    }
    // The tail at the pill's right end: the peek line, then the "as of" label. Measured with TextMetrics, which is
    // synchronous (a hidden Text is not laid out, so its implicit width is not there when the pill needs it).
    TextMetrics {
        id: peekM
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: isl.peekOpen ? isl.peekText : ""
    }
    TextMetrics {
        id: staleM
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: isl.isStale ? I18n.tr("island.stale").replace("{t}", isl.timeOf(isl.staleOf(isl.shown))) : ""
    }
    readonly property real peekW: peekOpen ? Math.min(peekM.advanceWidth, 240) : 0
    readonly property real staleW: isStale ? staleM.advanceWidth : 0
    readonly property real tailContentW: peekW + (peekW > 0 && staleW > 0 ? Theme.gap : 0) + staleW
    readonly property real tailW: tailContentW > 0 ? tailContentW + Theme.gap : 0
    readonly property real pillW: faceW + 2 * Theme.pad + tailW
    readonly property real extrasW: extras.visible ? Theme.xs + extras.width : 0

    height: Theme.barH - 10
    width: pillW + extrasW
    Behavior on width {
        enabled: isl.animate
        NumberAnimation { duration: Theme.emphMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
    }

    // The pill is what is drawn: the faces paint inside it and nothing outside it. Its width follows the same
    // tween as the island's, so the morph is one motion.
    Rectangle {
        id: pill
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: isl.pillW
        radius: Theme.rFull
        color: Theme.containerHigh
        clip: true
        Behavior on width {
            enabled: isl.animate
            NumberAnimation { duration: Theme.emphMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
        }

        Item {
            id: faces
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: parent.right; rightMargin: isl.tailW }

            // A face exists only while it is current or still fading out: the idle faces cost
            // ~1 MiB per bar, i.e. per output (B7, docs/BENCH.md).
            FaceSlot { id: clock; face: "clock"; sourceComponent: ClockFace { current: clock.current; animate: isl.animate } }
            FaceSlot { id: media; face: "media"; sourceComponent: MediaFace { current: media.current; animate: isl.animate } }
            FaceSlot { id: volume; face: "volume"; sourceComponent: VolumeFace { current: volume.current; animate: isl.animate } }
            FaceSlot { id: bright; face: "brightness"; sourceComponent: BrightnessFace { current: bright.current; animate: isl.animate } }
            FaceSlot { id: notifs; face: "notifications"; sourceComponent: NotificationsFace { current: notifs.current; animate: isl.animate } }
            FaceSlot {
                id: power
                face: "power"
                sourceComponent: PowerFace { current: power.current; animate: isl.animate; line: isl.detailOf("power") }
            }
            FaceSlot {
                id: bluetooth
                face: "bluetooth"
                sourceComponent: BluetoothFace { current: bluetooth.current; animate: isl.animate; line: isl.detailOf("bluetooth") }
            }

            // A mod's compact face (K28): its Face.qml, instantiated only while it is the face. It is not faded:
            // the next face replaces it at once, and the pill's width still animates.
            ModLoader {
                id: modFace
                provide: "island-face:" + isl.face
                shown: isl.isModFace
                anchors.centerIn: parent
            }
        }

        // The tail (see tailW): the "as of" label at the right end while the face is stale, the peek line before it.
        Text {
            id: staleLabel
            visible: isl.isStale
            anchors { right: parent.right; rightMargin: Theme.pad; verticalCenter: parent.verticalCenter }
            width: isl.staleW
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: staleM.text
        }
        Text {
            id: peekLabel
            visible: isl.peekOpen
            anchors {
                right: staleLabel.visible ? staleLabel.left : parent.right
                rightMargin: staleLabel.visible ? Theme.gap : Theme.pad
                verticalCenter: parent.verticalCenter
            }
            width: isl.peekW
            elide: Text.ElideRight
            color: Theme.fg
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: peekM.text
        }
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
    // It is one target with the island: a pointer on it is a pointer on the island.
    Item {
        id: extras
        anchors { left: pill.right; leftMargin: Theme.xs; verticalCenter: parent.verticalCenter }
        visible: isl.secondaryFace !== "" || isl.overflowN > 0
        height: 20
        width: (second.visible ? second.width : 0) + (over.visible ? (second.visible ? Theme.xs : 0) + over.implicitWidth : 0)

        Rectangle {
            id: second
            visible: isl.secondaryFace !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            height: 20
            radius: 10
            color: Theme.containerHigh
            border.width: 1
            border.color: Theme.outline
            Accessible.role: Accessible.StaticText
            Accessible.name: I18n.tr("island.secondary").replace("{face}", I18n.tr("island.face." + isl.secondaryFace))
            Text {
                anchors.centerIn: parent
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                text: isl.glyphOf(isl.secondaryFace)
            }
        }
        Text {
            id: over
            visible: isl.overflowN > 0
            x: second.visible ? second.width + Theme.xs : 0
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: "+" + isl.overflowN
            Accessible.role: Accessible.StaticText
            Accessible.name: I18n.tr("island.overflow").replace("{n}", isl.overflowN)
        }
    }

    // The pointer target is the bar's full thickness (review #11: at least 32 px), centred on the pill.
    // It is a sibling of the pill, not a child: a clipping parent does not deliver pointer events to
    // children outside it, and the pill keeps its clip.
    MouseArea {
        anchors.centerIn: parent
        width: parent.width
        height: Theme.barH
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
