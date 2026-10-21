import QtQuick
import "../core"

// Under Material (K59, docs/ux/texture.md "Settings"): every material as a small lit square — the daemon's swatch, in
// the light, tint and wrinkles in effect (`theme.previews.textures`, made only while this is shown) — with "None" first.
// A card is a pick (one undo step). While a look or style holds the material, "Back to …" brings the user's own back
// (`theme.texture.restore`, as K55's light/dark). Keyboard: one Tab stop on the current card (WAI-ARIA radio group),
// arrows move, Return/Space pick. The selection is a frame, a check and a bold caption, never colour alone.
Column {
    id: tc
    readonly property var cards: {
        var pv = Store.docs["theme.previews"]
        var list = (pv && pv.textures) || []
        return [{ name: "none", image: "" }].concat(list)
    }
    readonly property string current: Store.valueOf("theme.texture.kind") || "none"
    readonly property var before: (Store.theme && Store.theme.appearance && Store.theme.appearance.texture_before) || null
    // The test hook: the cards' names in order, and how many show their swatch.
    function names() { return tc.cards.map(function (c) { return c.name }).join(",") }
    function drawn() { return tc.cards.filter(function (c) { return c.image !== "" }).length }
    function pick(name) {
        if (name === tc.current || !Store.live) return
        Store.apply([{ set: "theme.texture.kind", value: name }])
    }

    Component.onCompleted: Store.watch("theme.previews")
    Component.onDestruction: Store.unwatch("theme.previews")

    width: parent ? parent.width : 480
    spacing: Theme.gap
    objectName: "texture-cards"

    Flow {
        id: grid
        width: tc.width
        spacing: Theme.gap
        Accessible.role: Accessible.RadioButton
        Accessible.name: I18n.tr("config.theme.texture.kind.label")
        Repeater {
            id: rep
            model: tc.cards
            delegate: Item {
                id: card
                required property var modelData
                required property int index
                readonly property bool on: modelData.name === tc.current
                readonly property string caption: I18n.tr("config.choice.texture." + modelData.name)
                objectName: "texture:" + modelData.name
                width: 76
                height: 76 + cap.height + 4
                activeFocusOnTab: card.on
                opacity: Store.live ? 1 : 0.5
                function step(d) {
                    var c = rep.itemAt(card.index + d)
                    if (c) c.forceActiveFocus()
                }
                Keys.onLeftPressed: event => { card.step(-1); event.accepted = true }
                Keys.onRightPressed: event => { card.step(1); event.accepted = true }
                Keys.onUpPressed: event => { card.step(-Math.max(1, Math.floor(grid.width / (card.width + grid.spacing)))); event.accepted = true }
                Keys.onDownPressed: event => { card.step(Math.max(1, Math.floor(grid.width / (card.width + grid.spacing)))); event.accepted = true }
                Keys.onReturnPressed: event => { tc.pick(modelData.name); event.accepted = true }
                Keys.onEnterPressed: event => { tc.pick(modelData.name); event.accepted = true }
                Keys.onSpacePressed: event => { tc.pick(modelData.name); event.accepted = true }
                Accessible.role: Accessible.RadioButton
                Accessible.name: card.caption
                Accessible.checked: card.on

                Rectangle {
                    id: face
                    width: 76
                    height: 76
                    radius: Theme.rSm
                    color: Theme.containerHigh
                    border.width: card.on ? 2 : 1
                    border.color: card.on ? Theme.accent : (hov.hovered ? Theme.dim : Theme.outline)
                    clip: true
                    Image {
                        anchors.fill: parent
                        anchors.margins: 2
                        visible: modelData.image !== ""
                        source: modelData.image !== "" ? "file://" + modelData.image : ""
                        sourceSize: Qt.size(128, 128)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                    }
                    // "None": a plain square with a hairline slash; a swatch still being made: its name, quietly.
                    Rectangle {
                        visible: modelData.name === "none"
                        anchors.centerIn: parent
                        width: 1
                        height: parent.width * 1.1
                        rotation: 45
                        color: Theme.outline
                    }
                    Text {
                        visible: modelData.name !== "none" && modelData.image === ""
                        anchors.centerIn: parent
                        color: Theme.dim
                        font.pixelSize: Theme.fs - 3
                        text: "…"
                    }
                    // The check, on the selected card.
                    Rectangle {
                        visible: card.on
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 4
                        width: 18
                        height: 18
                        radius: 9
                        color: Theme.accent
                        Text {
                            anchors.centerIn: parent
                            color: Theme.fgOnAccent
                            font.pixelSize: 12
                            font.bold: true
                            text: "✓"
                        }
                    }
                }
                Text {
                    id: cap
                    anchors.top: face.bottom
                    anchors.topMargin: 4
                    width: card.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    color: card.on ? Theme.fg : Theme.dim
                    font.pixelSize: Theme.fs - 2
                    font.weight: card.on ? Font.Bold : Font.Normal
                    font.family: Theme.fam(text, Theme.families)
                    text: card.caption
                }
                HoverHandler { id: hov }
                MouseArea {
                    anchors.fill: parent
                    enabled: Store.live
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tc.pick(modelData.name)
                }
                FocusRing {
                    anchors.fill: face
                    shown: card.activeFocus
                    corner: Theme.rSm
                }
            }
        }
    }
    Button {
        objectName: "texture-back"
        visible: tc.before !== null && tc.before["theme.texture.kind"] !== undefined
        label: tc.before ? I18n.fmt("theme.texture.back", { material: I18n.tr("config.choice.texture." + tc.before["theme.texture.kind"]) }) : ""
        enabled: Store.live
        onClicked: Store.act("theme.texture.restore", {})
    }
}
