import QtQuick
import QtQuick.Effects
import "core"

// A control of the web host's card (docs/ux/webdock.md "Layout per edge", "Keyboard and a11y"): a 26 px glyph button of
// the header (quiet: a tint on hover, no fill), a drawn device (`shape`: the view and size toggles), or a text button
// (`label`; `primary` is the one accent action of a view, `flat` a menu item, `start` puts its label at the left).
// The shell's kit (frontend/components IconButton, Button) is the same look; the host draws its own copy because it
// cannot import the components (they reach the core through "../core", a second copy of the singletons here).
// `keyed` (the phone's bottom bar, I109): a glyph button drawn as a block of the theme's chrome, from tokens only (rule
// 4) — a keycap with its outline and hard shadow that sinks while pressed, a soft disc with its rim and shadow that
// shrinks, an outlined box that flashes (line), a quiet disc (flat). Its size stays 26 px, so the bar's spread holds.
// Reachable by Tab; Return, Enter and Space press it. The focus ring shows for keyboard focus only. `tipFn(item, on)`
// is the card's tooltip, shown on hover and on keyboard focus; the tip is the accessible name (or the label).
Rectangle {
    id: b

    property string glyph: ""
    // A Material Symbols name, drawn when the theme found the font (Theme.iconFamily, K42); else `glyph`.
    property string icon: ""
    readonly property bool symbols: Theme.iconFamily !== "" && icon !== "" && !texted
    property string shape: ""           // phone | desktop (the view), narrow | wide (the size): drawn, not a glyph
    property string label: ""
    property string a11y: ""
    property bool primary: false
    property bool flat: false           // a menu item: no fill of its own, a tint on hover
    property bool start: false          // the label starts at the left edge (menu items)
    property bool keyed: false          // a glyph button as a block of the chrome (see the header)
    property bool enabled: true
    property var tipFn: null
    readonly property string tip: a11y !== "" ? a11y : label
    signal clicked()

    function press() {
        if (b.enabled) b.clicked()
    }

    readonly property bool texted: label !== ""
    readonly property bool block: keyed && !texted
    readonly property bool lifted: Theme.shadowDy > 0 || Theme.softR > 0
    readonly property bool down: tap.pressed && b.enabled
    implicitWidth: texted ? txt.implicitWidth + 2 * Theme.pad : 26
    implicitHeight: texted ? 28 : 26
    radius: texted ? Theme.rSm : Math.min(height / 2, Theme.rFull)
    color: texted
        ? (primary ? Theme.accent : (flat ? (hover.hovered && enabled ? Theme.containerHigh : "transparent") : Theme.containerHigh))
        : (block && down && !lifted && Theme.pressScale >= 1 ? Qt.alpha(Theme.fg, 0.16)
            : (hover.hovered && enabled ? Theme.containerHigh : (block && lifted ? Theme.container : "transparent")))
    border.width: block ? Theme.outlineW : 0
    border.color: Theme.outlineColor
    scale: block && down ? Theme.pressScale : 1
    transform: Translate { y: b.block && b.down ? Theme.shadowDy : 0 }
    // The block's shadow: hard (keycap; it stays put while the key sinks onto it) or soft.
    Rectangle {
        z: -1
        visible: b.block && Theme.shadowDy > 0
        y: Theme.shadowDy - (b.down ? Theme.shadowDy : 0)
        width: b.width
        height: b.height
        radius: b.radius
        color: Theme.line
    }
    Loader {
        z: -1
        anchors.fill: parent
        active: b.block && Theme.softR > 0
        sourceComponent: RectangularShadow {
            offset.y: Theme.softDy * 0.4
            blur: Theme.softR * 0.4
            spread: -1
            radius: b.radius
            color: Theme.softColor
        }
    }
    opacity: enabled ? 1 : 0.5

    activeFocusOnTab: b.enabled
    Keys.onReturnPressed: b.press()
    Keys.onEnterPressed: b.press()
    Keys.onSpacePressed: b.press()
    Accessible.role: Accessible.Button
    Accessible.name: b.tip
    onActiveFocusChanged: if (b.tipFn) b.tipFn(b, activeFocus)

    Text {
        id: txt
        x: b.start ? Theme.gap : Math.round((b.width - width) / 2)
        y: Math.round((b.height - height) / 2)
        visible: b.shape === ""
        text: b.texted ? b.label : (b.symbols ? b.icon : b.glyph)
        color: b.texted && b.primary ? Theme.fgOnAccent : Theme.fg
        font.pixelSize: b.texted ? Theme.fsLabel : (b.symbols ? 18 : Theme.fs + 2)
        font.family: b.symbols ? Theme.iconFamily : Theme.fam(text, Theme.families)
        font.variableAxes: b.symbols ? { "FILL": Theme.iconFill > 0 ? 1 : 0, "wght": Theme.iconWeight, "opsz": 20 } : ({})
        renderType: Text.QtRendering
    }

    // A device drawn in the foreground colour: a phone or a desktop (with its stand) for the view, a narrow or a wide
    // page for the size. Drawn, not an icon font, so it is the same in every locale (no missing glyph, no emoji).
    Item {
        id: device
        anchors.centerIn: parent
        width: 16
        height: 16
        visible: b.shape !== ""
        readonly property int screenW: b.shape === "desktop" ? 16 : b.shape === "wide" ? 14 : 9
        readonly property int screenH: b.shape === "phone" ? 14 : b.shape === "desktop" ? 10 : 13

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 1
            width: device.screenW
            height: device.screenH
            radius: 2
            color: "transparent"
            border.width: 1.5
            border.color: Theme.fg
        }
        // The two text lines of a page, for the size toggle.
        Rectangle {
            visible: b.shape === "narrow" || b.shape === "wide"
            x: 2
            y: 5
            width: device.screenW - 4
            height: 1.5
            color: Theme.fg
        }
        Rectangle {
            visible: b.shape === "narrow" || b.shape === "wide"
            x: 2
            y: 8
            width: device.screenW - 4
            height: 1.5
            color: Theme.fg
        }
        // The stand of a desktop.
        Rectangle {
            visible: b.shape === "desktop"
            anchors.horizontalCenter: parent.horizontalCenter
            y: 12
            width: 6
            height: 1.5
            color: Theme.fg
        }
    }

    HoverHandler {
        id: hover
        onHoveredChanged: if (b.tipFn) b.tipFn(b, hovered)
    }
    MouseArea {
        id: tap
        anchors.fill: parent
        enabled: b.enabled
        onClicked: b.press()
    }
    Rectangle {
        anchors.fill: parent
        radius: b.radius
        color: "transparent"
        border.width: 1
        border.color: Theme.focusRing
        visible: b.activeFocus
    }
}
