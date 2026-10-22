import QtQuick
import Quickshell
import "../core"

// Glyph-only button, 28 px square; its hit area is the control height (32 px floor). `a11y` is the
// translated accessible name. Reachable by Tab; Return, Enter and Space press it. `icon` is a Material
// Symbols name drawn when the font is there; `glyph` is the text fallback (and the only mark without `icon`).
// Block chromes (K42, K45): a small round block — a keycap that sinks, a soft disc that shrinks, an outlined box (line
// chrome); flat chrome: a hover disc.
Item {
    id: b
    property string glyph: ""
    property string icon: ""
    property string a11y: ""
    property bool enabled: true
    // Lit: the button stands for something that is on (tonal fill).
    property bool lit: false
    property real radius: Theme.rFull
    signal clicked()
    // K61 (docs/ux/texture.md "Controls"): an opaque face carries the relief over its fill and glyph, and Block's own is
    // then left out (one relief per pixel), in a window that shares its sheet. A transparent face gets none (QuickButton).
    readonly property var qsw: Window.window ? QsWindow.window : null
    readonly property bool ownRelief: Theme.texControls && !Theme.texText && blk.fill.a >= 1 && !!(qsw && qsw.tileSheet)
    // The relief on the glyph alone (row 285: a mask of its own alpha) while the face is transparent or translucent: the
    // ground of a transparent face gets no relief, so nothing halos.
    readonly property bool glyphRelief: Theme.texControls && blk.fill.a < 1 && !!(qsw && qsw.tileSheet)

    function press() { if (b.enabled) b.clicked() }

    readonly property int side: Theme.ringW > 0 ? 32 : 28
    // A block with a shadow of either kind stands as a filled key; an outline alone is a box with no fill.
    readonly property bool lifted: Theme.shadowDy > 0 || Theme.softR > 0
    implicitWidth: side
    implicitHeight: side + Theme.shadowDy
    opacity: enabled ? 1 : 0.5

    activeFocusOnTab: b.enabled
    Keys.onReturnPressed: b.press()
    Keys.onEnterPressed: b.press()
    Keys.onSpacePressed: b.press()
    Accessible.role: Accessible.Button
    Accessible.name: b.a11y

    Block {
        id: blk
        anchors.fill: parent
        radius: b.radius
        ringScale: 0.34
        softScale: 0.4
        pressed: area.pressed && b.enabled
        relief: !b.ownRelief
        fill: b.lit ? Theme.selected
            : (Theme.groups && b.lifted ? (hover.hovered && b.enabled ? Theme.containerHigh : Theme.container)
                                        : (hover.hovered && b.enabled ? Theme.containerHigh : "transparent"))
        Icon {
            id: glyph
            anchors.centerIn: parent
            name: b.icon
            glyph: b.glyph
            filled: b.lit
            size: Theme.fs + 5
            color: b.lit ? Theme.fgOnSelected : Theme.fg
        }
        // The relief over the fill and the glyph (the face is opaque here, see ownRelief).
        Loader {
            active: b.ownRelief
            anchors.fill: parent
            sourceComponent: Relief { anchors.fill: parent; radius: Math.max(0, Math.min(blk.radius, blk.face.height / 2) - blk.inset) }
        }
        // The glyph's relief: a parked, non-live copy of the glyph is the mask, refreshed only when the glyph's shape changes.
        Loader {
            active: b.glyphRelief && glyph.visible
            x: glyph.x; y: glyph.y; width: glyph.width; height: glyph.height
            sourceComponent: Item {
                anchors.fill: parent
                ShaderEffectSource {
                    id: glyphMask
                    width: parent.width
                    height: parent.height
                    sourceItem: glyph
                    live: false
                    x: -100000
                    y: -100000
                    readonly property var key: [glyph.text, glyph.font.pixelSize, glyph.font.family, glyph.font.variableAxes, glyph.width, glyph.height]
                    onKeyChanged: scheduleUpdate()
                    Component.onCompleted: scheduleUpdate()
                }
                Relief { anchors.fill: parent; radius: 0; mask: glyphMask }
            }
        }
    }
    HoverHandler { id: hover }
    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -Math.max(0, (Theme.controlH - b.height) / 2)
        enabled: b.enabled
        onClicked: b.clicked()
    }
    FocusRing {
        width: blk.face.width
        height: blk.face.height
        y: blk.face.y
        shown: b.activeFocus
        corner: Math.min(b.radius, height / 2)
    }
}
