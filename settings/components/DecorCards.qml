import QtQuick
import "../core"

// A choice drawn as preview cards (K45, I104): for a select whose offers have previews in `theme.previews` (`styles`,
// `looks`, `palettes`; K53), each card is a small scene in that pack — its ground, a bar of three blocks, a card with "Aa"
// in its font and an accent pill — drawn from the tokens the daemon resolved for it (Shōjiki: what you pick is what you
// get). A look with frame art (`frame`) gets a hint of it: corner brackets in its ink and a frame mark (the frames are the
// shell's components; W29). An offer without a preview (your own settings) is a plain card. Keyboard as Segmented: Tab
// enters, arrows move (and, with `previewOnMove`, emit `previewed`), Space/Return/click pick, Escape is `cancelled`.
Flow {
    id: dc
    property var choices: []
    property var current
    property bool enabled: true
    // name -> preview entry {tokens, frame?}, from `theme.previews`.
    property var looks: ({})
    // Arrows preview the card moved to. Off where a pick is an action that resets settings (styles, looks: W29): there
    // the arrows only move the focus, and Space/Return/click pick (a radio group with manual activation).
    property bool previewOnMove: true
    signal picked(var value)
    signal previewed(var value)
    signal cancelled()
    // Escape is taken only while there is something to take back (the row binds its open preview); otherwise it goes on
    // up, where the sheet closes on it (K63).
    property bool cancellable: true

    spacing: Theme.gap
    readonly property bool anyOn: dc.choices.some(function (c) { return JSON.stringify(c.value) === JSON.stringify(dc.current) })

    function move(from, d) {
        var i = from + d
        if (i < 0 || i >= dc.choices.length) return
        var c = rep.itemAt(i)
        if (!c || !dc.enabled) return
        c.forceActiveFocus()
        if (dc.previewOnMove && JSON.stringify(dc.choices[i].value) !== JSON.stringify(dc.current)) dc.previewed(dc.choices[i].value)
    }

    Repeater {
        id: rep
        model: dc.choices
        delegate: Item {
            id: card
            required property var modelData
            required property int index
            readonly property bool on: JSON.stringify(modelData.value) === JSON.stringify(dc.current)
            readonly property var entry: dc.looks[modelData.value] || null
            readonly property var t: card.entry ? card.entry.tokens : null
            readonly property bool framed: !!card.entry && !!card.entry.frame
            function tk(k, d) { var v = card.t ? card.t[k] : undefined; return v === undefined ? d : v }
            function ck(k, d) { return Qt.color(tk(k, d)) }
            width: 156
            height: scene.height + caption.height + Theme.gap
            opacity: dc.enabled ? 1 : 0.5
            // One Tab stop for the group (WAI-ARIA radio group, roving): the chosen card, or the first when none is; the
            // arrows move inside. Every card a stop made a page of 26 looks and 26 palettes 52 Tabs long.
            activeFocusOnTab: dc.enabled && (card.on || (card.index === 0 && !dc.anyOn))
            objectName: dc.objectName
            Keys.onSpacePressed: event => { dc.picked(modelData.value); event.accepted = true }
            Keys.onReturnPressed: event => { dc.picked(modelData.value); event.accepted = true }
            Keys.onEnterPressed: event => { dc.picked(modelData.value); event.accepted = true }
            Keys.onEscapePressed: event => { if (dc.cancellable) dc.cancelled(); event.accepted = dc.cancellable }
            Keys.onLeftPressed: event => { dc.move(card.index, -1); event.accepted = true }
            Keys.onUpPressed: event => { dc.move(card.index, -1); event.accepted = true }
            Keys.onRightPressed: event => { dc.move(card.index, 1); event.accepted = true }
            Keys.onDownPressed: event => { dc.move(card.index, 1); event.accepted = true }
            Accessible.role: Accessible.RadioButton
            Accessible.name: I18n.tr(modelData.label) + (card.framed ? ", " + I18n.tr("settings.appearance.frame") : "")
            Accessible.checkable: true
            Accessible.checked: card.on

            // The selection: a tonal frame round the scene, so it is not colour alone (a check sits in the caption).
            Rectangle {
                anchors.fill: scene
                anchors.margins: -4
                radius: Theme.rSm + 4
                color: "transparent"
                border.width: card.on ? 2 : 0
                border.color: Theme.accent
            }
            Rectangle {
                id: scene
                width: parent.width
                height: 104
                radius: Theme.rSm
                clip: true
                color: card.t ? card.ck("color.surface", "#222") : Theme.containerHigh
                border.width: card.t ? 0 : 1
                border.color: Theme.outline

                // Your own: no look of its own to show.
                Text {
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    visible: !card.t
                    anchors.centerIn: parent
                    text: Theme.iconFamily !== "" ? "tune" : "⚙"
                    font.family: Theme.iconFamily !== "" ? Theme.iconFamily : Theme.fam(text, Theme.families)
                    font.pixelSize: 30
                    color: Theme.dim
                }

                // A bar of three blocks.
                Row {
                    visible: !!card.t
                    x: 8; y: 8
                    spacing: 5
                    Repeater {
                        model: [34, 56, 22]
                        delegate: MiniBlock {
                            required property var modelData
                            required property int index
                            t: card.t
                            width: modelData
                            height: 16
                            fill: index === 1 ? card.ck("color.selected", "#444") : card.ck("color.surface_container_high", "#333")
                        }
                    }
                }
                // A card with type and an accent pill.
                MiniBlock {
                    visible: !!card.t
                    t: card.t
                    x: 8; y: 34
                    width: parent.width - 16
                    height: 60
                    fill: card.ck("color.surface_container", "#2a2a2a")
                    radius: Math.min(card.tk("radius.lg", 12) * 0.6, 14)
                    Text {
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        x: 10; y: 6
                        text: "Aa あ"
                        font.family: card.tk("font.family", "sans-serif")
                        font.pixelSize: 18
                        font.weight: card.tk("font.weight.bold", 700)
                        color: card.ck("color.on_surface", "#eee")
                    }
                    Rectangle {
                        x: 10; y: 34
                        width: 46; height: 12
                        radius: Math.min(card.tk("radius.sm", 6), 6)
                        color: card.ck("color.accent", "#c33")
                    }
                    Row {
                        x: 64; y: 37
                        spacing: 4
                        Repeater {
                            model: ["color.secondary", "color.tertiary"]
                            delegate: Rectangle {
                                required property var modelData
                                width: 6; height: 6; radius: 3
                                color: card.ck(modelData, "#888")
                            }
                        }
                    }
                }
            }
            // The look's frame art, as a hint: corner brackets in its ink round the card, and a frame mark in the corner.
            Item {
                id: brackets
                visible: card.framed
                x: scene.x + 4; y: scene.y + 30
                width: scene.width - 8; height: 68
                readonly property color ink: Qt.alpha(card.ck("color.on_surface", "#eee"), 0.55)
                readonly property real arm: 10
                Repeater {
                    model: 4
                    delegate: Item {
                        id: corner
                        required property int index
                        readonly property bool atRight: index % 2 === 1
                        readonly property bool atBottom: index >= 2
                        x: corner.atRight ? brackets.width - brackets.arm : 0
                        y: corner.atBottom ? brackets.height - brackets.arm : 0
                        width: brackets.arm
                        height: brackets.arm
                        Rectangle { y: corner.atBottom ? corner.height - 2 : 0; width: corner.width; height: 2; color: brackets.ink }
                        Rectangle { x: corner.atRight ? corner.width - 2 : 0; width: 2; height: corner.height; color: brackets.ink }
                    }
                }
            }
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                visible: card.framed
                anchors.right: scene.right
                anchors.top: scene.top
                anchors.margins: 6
                text: Theme.iconFamily !== "" ? "filter_frames" : "▣"
                font.family: Theme.iconFamily !== "" ? Theme.iconFamily : Theme.fam(text, Theme.families)
                font.pixelSize: 14
                color: card.ck("color.on_surface", "#eee")
                opacity: 0.7
            }
            Row {
                id: caption
                anchors.top: scene.bottom
                anchors.topMargin: Theme.gap
                spacing: 4
                Text {
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    visible: card.on
                    text: Theme.iconFamily !== "" ? "check" : "✓"
                    font.family: Theme.iconFamily !== "" ? Theme.iconFamily : Theme.fam(text, Theme.families)
                    font.pixelSize: Theme.fs + 2
                    color: Theme.accent
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    width: card.width - (card.on ? Theme.fs + 6 : 0)
                    elide: Text.ElideRight
                    text: I18n.tr(card.modelData.label)
                    color: Theme.fg
                    font.pixelSize: Theme.fs
                    font.weight: card.on ? Theme.wBold : Theme.wMedium
                    font.family: Theme.fam(text, Theme.families)
                }
            }
            MouseArea {
                anchors.fill: parent
                enabled: dc.enabled
                cursorShape: Qt.PointingHandCursor
                onClicked: dc.picked(card.modelData.value)
            }
            FocusRing {
                anchors.fill: scene
                anchors.margins: -4
                shown: card.activeFocus
                corner: Theme.rSm + 4
            }
        }
    }

    // One block drawn from a look's chrome tokens: soft shadow, hard shadow, outline (+ ring), fill.
    component MiniBlock: Item {
        id: mb
        property var t: null
        property color fill: "#333"
        property real radius: Math.min(tk("radius.sm", 6), height / 2)
        function tk(k, d) { var v = mb.t ? mb.t[k] : undefined; return v === undefined ? d : v }
        // The chrome is drawn at half its widths: the scene is a small picture of it.
        readonly property real ol: tk("chrome.outline", 0) > 0 ? Math.max(1, tk("chrome.outline", 0) / 2) : 0
        readonly property real rg: tk("chrome.ring", 0) / 2
        readonly property real sh: tk("chrome.shadow", 0) / 2
        readonly property real so: tk("chrome.soft", 0) / 3
        Rectangle {
            visible: mb.so > 0
            x: -mb.so / 2; y: tk("chrome.soft_dy", 0) / 3
            width: mb.width + mb.so; height: mb.height + mb.so / 2
            radius: mb.radius + mb.so / 2
            color: Qt.alpha(Qt.color(tk("chrome.soft_color", "#000")), tk("chrome.soft_alpha", 0) * 0.6)
        }
        Rectangle {
            visible: mb.sh > 0
            y: mb.sh
            width: mb.width; height: mb.height
            radius: mb.radius
            color: tk("chrome.line", "#000")
        }
        Rectangle {
            anchors.fill: parent
            radius: mb.radius
            color: mb.rg > 0 ? tk("chrome.ring_color", "#fff") : mb.fill
            border.width: mb.ol
            border.color: Qt.alpha(Qt.color(tk("chrome.outline_color", "#000")), tk("chrome.outline_alpha", 0))
        }
        Rectangle {
            visible: mb.rg > 0
            anchors.fill: parent
            anchors.margins: mb.ol + mb.rg
            radius: Math.max(0, mb.radius - mb.ol - mb.rg)
            color: mb.fill
        }
    }
}
