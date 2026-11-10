import QtQuick
import "../core"

// The colour picker of the palette editor (I453, docs/ux/palettes.md "Custom palettes"): a saturation × lightness square,
// a hue strip, a hex field and quick swatches (the palette in effect's colours and the wallpaper's, from the daemon's
// `palette.list`). Keyboard: in the square Left/Right move the saturation and Up/Down the lightness, in the strip
// Left/Right the hue (Shift: ten steps); Tab goes on to the hex field (Return takes a typed hex), the swatches (arrows,
// Return) and OK / Cancel. Return in the square or the strip confirms, Escape anywhere cancels. `moved` follows every
// change (the editor's live draft); a colour is never meaning alone: the hex is always written.
Column {
    id: cp
    // The role's name in words, and the colour the picker opened with.
    property string role: ""
    property string hex: "#808080"
    property var swatches: ({ palette: [], wallpaper: [] })
    signal moved(string hex)
    signal accepted(string hex)
    signal cancelled()

    property real h: 0
    property real s: 0
    property real l: 0.5
    // The colour as picked: a typed or swatch hex stays exact; a move of the square or the strip is the HSL's colour.
    property string cur: "#808080"

    objectName: "color-picker"
    spacing: Theme.gap
    width: 300

    function clamp(x) { return Math.max(0, Math.min(1, x)) }
    function hexOf(c) { return ("" + c).substring(0, 7).toLowerCase() }
    function setHex(x, emit) {
        var t = ("" + x).trim()
        if (t.charAt(0) !== "#") t = "#" + t
        if (!/^#[0-9a-fA-F]{6}$/.test(t)) return false
        var c = Qt.color(t)
        // An achromatic colour has no hue: keep the strip where it was.
        if (c.hslHue >= 0) cp.h = c.hslHue * 360
        cp.s = c.hslSaturation
        cp.l = c.hslLightness
        cp.cur = t.toLowerCase()
        if (emit) cp.moved(cp.cur)
        return true
    }
    function setHsl(h, s, l) {
        cp.h = (h % 360 + 360) % 360
        cp.s = cp.clamp(s)
        cp.l = cp.clamp(l)
        cp.cur = cp.hexOf(Qt.hsla(cp.h / 360, cp.s, cp.l, 1))
        cp.moved(cp.cur)
    }
    function focusSquare() { square.forceActiveFocus() }
    // The colour it opened with, kept beside the one picked (`hex` may follow the editor's live draft).
    property string startHex: "#808080"
    Component.onCompleted: { cp.startHex = cp.hex; cp.setHex(cp.hex, false) }

    Keys.onEscapePressed: event => { cp.cancelled(); event.accepted = true }

    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        text: I18n.fmt("palettes.picker.title", { role: cp.role })
        color: Theme.fg
        font.pixelSize: Theme.fs
        font.weight: Theme.wBold
        font.family: Theme.fam(text, Theme.families)
    }
    Row {
        spacing: Theme.pad
        Column {
            spacing: Theme.gap
            // Saturation across, lightness up: grey to the full hue at mid lightness, white over the top, black under it.
            Rectangle {
                id: square
                objectName: "picker-square"
                width: 220
                height: 140
                radius: Theme.rSm
                border.width: 1
                border.color: Theme.outline
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.hsla(cp.h / 360, 0, 0.5, 1) }
                    GradientStop { position: 1; color: Qt.hsla(cp.h / 360, 1, 0.5, 1) }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#ffffff" }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0) }
                        GradientStop { position: 0.5001; color: Qt.rgba(0, 0, 0, 0) }
                        GradientStop { position: 1; color: "#000000" }
                    }
                }
                Rectangle {
                    x: cp.s * (square.width - 1) - width / 2
                    y: (1 - cp.l) * (square.height - 1) - height / 2
                    width: 14; height: 14; radius: 7
                    color: cp.cur
                    border.width: 2
                    border.color: cp.l > 0.5 ? "#000000" : "#ffffff"
                }
                activeFocusOnTab: true
                Accessible.role: Accessible.Slider
                Accessible.name: I18n.tr("palettes.picker.square") + ", "
                    + I18n.fmt("palettes.picker.square_value", { s: Math.round(cp.s * 100), l: Math.round(cp.l * 100) })
                Keys.onLeftPressed: event => { cp.setHsl(cp.h, cp.s - (event.modifiers & Qt.ShiftModifier ? 0.1 : 0.01), cp.l); event.accepted = true }
                Keys.onRightPressed: event => { cp.setHsl(cp.h, cp.s + (event.modifiers & Qt.ShiftModifier ? 0.1 : 0.01), cp.l); event.accepted = true }
                Keys.onUpPressed: event => { cp.setHsl(cp.h, cp.s, cp.l + (event.modifiers & Qt.ShiftModifier ? 0.1 : 0.01)); event.accepted = true }
                Keys.onDownPressed: event => { cp.setHsl(cp.h, cp.s, cp.l - (event.modifiers & Qt.ShiftModifier ? 0.1 : 0.01)); event.accepted = true }
                Keys.onReturnPressed: event => { cp.accepted(cp.cur); event.accepted = true }
                Keys.onEnterPressed: event => { cp.accepted(cp.cur); event.accepted = true }
                MouseArea {
                    anchors.fill: parent
                    function at(m) { cp.setHsl(cp.h, m.x / square.width, 1 - m.y / square.height) }
                    onPressed: m => { square.forceActiveFocus(); at(m) }
                    onPositionChanged: m => { if (pressed) at(m) }
                }
                FocusRing { anchors.fill: parent; shown: square.activeFocus; corner: square.radius }
            }
            Rectangle {
                id: hue
                objectName: "picker-hue"
                width: square.width
                height: 18
                radius: height / 2
                border.width: 1
                border.color: Theme.outline
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#ff0000" }
                    GradientStop { position: 1 / 6; color: "#ffff00" }
                    GradientStop { position: 2 / 6; color: "#00ff00" }
                    GradientStop { position: 3 / 6; color: "#00ffff" }
                    GradientStop { position: 4 / 6; color: "#0000ff" }
                    GradientStop { position: 5 / 6; color: "#ff00ff" }
                    GradientStop { position: 1; color: "#ff0000" }
                }
                Rectangle {
                    x: cp.h / 360 * (hue.width - 1) - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8; height: hue.height + 6; radius: 4
                    color: Qt.hsla(cp.h / 360, 1, 0.5, 1)
                    border.width: 2
                    border.color: "#ffffff"
                }
                activeFocusOnTab: true
                Accessible.role: Accessible.Slider
                Accessible.name: I18n.tr("palettes.picker.hue") + ", " + I18n.fmt("palettes.picker.hue_value", { h: Math.round(cp.h) })
                Keys.onLeftPressed: event => { cp.setHsl(cp.h - (event.modifiers & Qt.ShiftModifier ? 10 : 1), cp.s, cp.l); event.accepted = true }
                Keys.onRightPressed: event => { cp.setHsl(cp.h + (event.modifiers & Qt.ShiftModifier ? 10 : 1), cp.s, cp.l); event.accepted = true }
                Keys.onReturnPressed: event => { cp.accepted(cp.cur); event.accepted = true }
                Keys.onEnterPressed: event => { cp.accepted(cp.cur); event.accepted = true }
                MouseArea {
                    anchors.fill: parent
                    function at(m) { cp.setHsl(Math.max(0, Math.min(359.9, m.x / hue.width * 360)), cp.s, cp.l) }
                    onPressed: m => { hue.forceActiveFocus(); at(m) }
                    onPositionChanged: m => { if (pressed) at(m) }
                }
                FocusRing { anchors.fill: parent; shown: hue.activeFocus; corner: hue.radius }
            }
        }
        Column {
            spacing: Theme.gap
            // The colour picked and the one it opened with, side by side.
            Row {
                spacing: 0
                Rectangle { width: 36; height: 36; color: cp.startHex; border.width: 1; border.color: Theme.outline }
                Rectangle { objectName: "picker-current:" + cp.cur; width: 36; height: 36; color: cp.cur; border.width: 1; border.color: Theme.outline }
            }
            TextField {
                id: hexField
                width: 120
                mono: true
                label: I18n.tr("palettes.picker.hex")
                value: cp.cur
                invalid: false
                escapeTaken: true
                onSubmitted: t => { if (!cp.setHex(t, true)) hexField.invalid = true; else hexField.invalid = false }
                onAccepted: t => { if (cp.setHex(t, true)) hexField.invalid = false }
                onEscaped: cp.cancelled()
            }
        }
    }
    // Quick swatches: one Tab stop per group, arrows inside, Return or a click takes one.
    Repeater {
        model: [{ id: "palette", colors: cp.swatches.palette || [] }, { id: "wallpaper", colors: cp.swatches.wallpaper || [] }]
        delegate: Column {
            id: group
            required property var modelData
            visible: modelData.colors.length > 0
            spacing: 4
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                text: I18n.tr("palettes.picker.from_" + group.modelData.id)
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
            }
            Row {
                spacing: 4
                Repeater {
                    id: dots
                    model: group.modelData.colors
                    delegate: Rectangle {
                        id: dot
                        required property string modelData
                        required property int index
                        objectName: "picker-swatch:" + group.modelData.id + ":" + modelData
                        width: 22; height: 22; radius: 4
                        color: modelData
                        border.width: modelData === cp.cur ? 2 : 1
                        border.color: modelData === cp.cur ? Theme.fg : Theme.outline
                        activeFocusOnTab: dot.index === 0
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData
                        function step(d) { var c = dots.itemAt(dot.index + d); if (c) c.forceActiveFocus() }
                        Keys.onLeftPressed: event => { dot.step(-1); event.accepted = true }
                        Keys.onRightPressed: event => { dot.step(1); event.accepted = true }
                        Keys.onReturnPressed: event => { cp.setHex(modelData, true); event.accepted = true }
                        Keys.onEnterPressed: event => { cp.setHex(modelData, true); event.accepted = true }
                        Keys.onSpacePressed: event => { cp.setHex(modelData, true); event.accepted = true }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: cp.setHex(dot.modelData, true) }
                        FocusRing { anchors.fill: parent; shown: dot.activeFocus; corner: dot.radius }
                    }
                }
            }
        }
    }
    Row {
        spacing: Theme.gap
        Button { objectName: "picker-ok"; label: I18n.tr("palettes.picker.ok"); primary: true; onClicked: cp.accepted(cp.cur) }
        Button { objectName: "picker-cancel"; label: I18n.tr("palettes.picker.cancel"); onClicked: cp.cancelled() }
    }
}
