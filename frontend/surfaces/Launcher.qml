import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components"

// Launcher (M5): centred overlay with exclusive keyboard focus while open. The daemon owns the
// open state (runtime.ui.launcher), the index, ranking and launching; this only renders results
// of `query launcher` and sends `launcher.launch` / `ui.close`.
//
// Same idle discipline as Stage (K16): permanently mapped but transparent, input-less and
// focus-less while hidden, so it renders 0 frames; the reveal is a slide that starts on the first
// presented frame. Typing never animates: the result list is replaced, the highlight just moves.
PanelWindow {
    id: lp

    readonly property bool want: (Store.docs["runtime.ui"] && Store.docs["runtime.ui"].launcher) === true
    readonly property int slide: 12
    readonly property int rowH: 48
    readonly property int maxRows: 7
    readonly property int minRows: 1      // the empty state keeps one row of height
    // The list follows its results: as many rows as there are, within [minRows, maxRows].
    readonly property int listH: Math.max(minRows, Math.min(results.length, maxRows)) * rowH
    property real p: 0
    property bool gate: false
    property bool shown: false
    property var results: []
    property int sel: 0
    property string err: ""     // translated failure line above the list; "" when there is none
    property var scr: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null   // latched on open so the card never jumps outputs

    function focusedScreen() {
        var o = (Store.docs["svc.workspaces"] && Store.docs["svc.workspaces"].outputs) || {}
        var s = Quickshell.screens
        for (var i = 0; i < s.length; i++) {
            var l = o[s[i].name] || []
            for (var j = 0; j < l.length; j++)
                if (l[j].focused) return s[i]
        }
        return s.length > 0 ? s[0] : null
    }
    // A failure carries a kind (invalid, unavailable, internal, or the Store's own). Its message is
    // English and is never shown: the kind picks a translated line, unknown kinds the generic one.
    function errorText(e) {
        var k = "surfaces.launcher.error." + (e.kind || "failed")
        var t = I18n.tr(k)
        return t !== k ? t : I18n.tr("surfaces.launcher.error.failed")
    }
    function run(q) {
        Store.query("launcher", q, function (items, e) {
            if (!lp.want) return
            lp.results = items || []
            lp.sel = 0
            lp.err = e ? lp.errorText(e) : ""
        })
    }
    function launch() {
        if (sel < 0 || sel >= results.length || !results[sel].id) return
        Store.act("launcher.launch", { id: results[sel].id }, function (done, e) {
            // Close only once the app is up: a failure stays open with its reason.
            if (e) { lp.err = lp.errorText(e); return }
            Store.act("ui.close")
        })
    }

    screen: scr
    // No anchors: the compositor centres the surface.
    // Room round the card for the soft chrome's shadow (K45; 0 under every other chrome): the surface stays centred.
    readonly property int shade: Theme.softR
    implicitWidth: card.width + 2 * shade
    implicitHeight: card.height + 2 * shade
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: want ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "kurashi-launcher"
    color: "transparent"
    mask: shown ? cardRegion : emptyRegion
    BackgroundEffect.blurRegion: shown ? cardRegion : emptyRegion
    Region { id: cardRegion; item: card }
    Region { id: emptyRegion }

    onWantChanged: {
        if (want) {
            scr = focusedScreen()
            field.text = ""
            results = []; sel = 0; err = ""
            anim.stop()
            if (!shown) { p = 0; gate = true; shown = true }
            else { anim.from = p; anim.to = 1; anim.start() }
            run("")
            field.forceActiveFocus()
        } else if (shown) {
            gate = false
            anim.stop(); anim.from = p; anim.to = 0; anim.start()
        }
    }
    NumberAnimation {
        id: anim
        target: lp; property: "p"
        duration: Theme.stdMs
        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve
        onFinished: if (lp.p <= 0 && !lp.want) { lp.shown = false; lp.results = [] }
    }
    Connections {
        target: card.Window.window
        function onFrameSwapped() {
            if (lp.gate) { lp.gate = false; anim.from = lp.p; anim.to = 1; anim.start() }
        }
    }

    // The card is a Block (K42, K45): a flat panel with a hairline, a keycap panel with an ink outline and hard shadow, a
    // soft glass panel with a rim and a drop shadow, or a panel outlined in ink (line).
    Item {
        id: card
        visible: lp.shown
        width: 600
        readonly property real inset: Theme.outlineW + Theme.ringW
        height: 2 * Theme.pad + 2 * inset + 44 + Theme.gap + (lp.err !== "" ? errRow.height + Theme.gap : 0) + lp.listH + Theme.shadowDy
        x: lp.shade
        y: lp.shade - lp.slide * (1 - lp.p)
        opacity: Math.min(1, lp.p * 1.6)
        scale: 0.96 + 0.04 * lp.p
        Block {
            anchors.fill: parent
            radius: Theme.rLg + 4
            fill: Theme.panel
            flatBorder: Theme.outline
        }

        Block {
            id: box
            x: Theme.pad + card.inset
            y: Theme.pad + card.inset
            width: card.width - 2 * x
            height: 44
            radius: Theme.rFull
            ringScale: 0
            softScale: 0
            fill: Theme.surface
            flatBorder: field.activeFocus ? Theme.accent : Theme.outline
            Icon {
                id: searchIcon
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                glyph: "⌕"
                color: Theme.dim
                size: Theme.fsTitle + 4
            }
            TextInput {
                id: field
                anchors { fill: parent; leftMargin: searchIcon.x + searchIcon.width + 8; rightMargin: 14 }
                color: Theme.fg
                font.pixelSize: Theme.fsTitle
                font.weight: Theme.wMedium
                font.family: Theme.fam(text, Theme.families)
                verticalAlignment: TextInput.AlignVCenter
                selectByMouse: true
                clip: true
                onTextChanged: if (lp.want) lp.run(text)
                Keys.onEscapePressed: Store.act("ui.close")
                Keys.onDownPressed: if (lp.sel < lp.results.length - 1) lp.sel++
                Keys.onUpPressed: if (lp.sel > 0) lp.sel--
                Keys.onReturnPressed: lp.launch()
                Keys.onEnterPressed: lp.launch()
                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: field.text === "" && field.preeditText === ""
                    color: Theme.dim
                    font: field.font
                    text: I18n.tr("launcher.placeholder")
                }
                // The prefix modes, named while the field is empty.
                Text {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    visible: field.text === "" && field.preeditText === ""
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr("launcher.modes")
                }
            }
        }

        // Failure line above the results (a failed launch or query). The results stay usable.
        Text {
            id: errRow
            visible: lp.err !== ""
            x: Theme.pad + card.inset
            y: box.y + box.height + Theme.gap
            width: card.width - 2 * x
            wrapMode: Text.WordWrap
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: lp.err
        }

        ListView {
            id: list
            x: Theme.pad + card.inset
            y: lp.err !== "" ? errRow.y + errRow.height + Theme.gap : box.y + box.height + Theme.gap
            width: card.width - 2 * x
            height: lp.listH
            clip: true
            interactive: false
            model: lp.results
            currentIndex: lp.sel
            highlightMoveDuration: 0
            // The selected row's highlight is one tonal block that springs to the row (keycap: outlined).
            highlight: Block {
                width: list.width
                height: lp.rowH - 2
                radius: Theme.rLg
                ringScale: 0
                softScale: 0
                fill: Theme.selected
                Behavior on y {
                    enabled: lp.shown && Theme.springOn
                    NumberAnimation { duration: Theme.stdMs; easing.type: Easing.OutBack; easing.overshoot: Theme.overshoot * 0.6 }
                }
            }
            highlightFollowsCurrentItem: true
            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool isCalc: modelData.kind === "calc"
                // Prefix modes (daemon): `:` emoji, `;` clipboard; a `note` row only explains (an i18n key, no id).
                readonly property bool isEmoji: modelData.kind === "emoji"
                readonly property bool isClip: modelData.kind === "clip"
                readonly property bool isNote: modelData.kind === "note"
                readonly property bool copies: isCalc || isEmoji || isClip
                readonly property bool selected: index === lp.sel
                width: list.width
                height: lp.rowH

                Item {
                    id: ico
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -Theme.shadowDy / 2
                    width: 30; height: 30
                    property string src: modelData.kind === "app" && modelData.icon ? Quickshell.iconPath(modelData.icon, true) : ""
                    Image {
                        id: img
                        anchors.fill: parent
                        source: ico.src
                        sourceSize: Qt.size(60, 60)
                        asynchronous: true
                        visible: ico.src !== "" && status === Image.Ready
                    }
                    // Text fallback: initial of the name; a calculation shows its icon.
                    Rectangle {
                        anchors.fill: parent
                        visible: !img.visible
                        radius: Theme.rSm
                        color: row.isCalc ? Theme.accent : (row.isEmoji ? "transparent" : Theme.surface)
                        border.width: !row.isEmoji ? Theme.outlineW : 0
                        border.color: Theme.outlineColor
                        Icon {
                            anchors.centerIn: parent
                            visible: row.isCalc || row.isClip || row.isNote
                            name: row.isCalc ? "calculate" : (row.isClip ? "content_paste" : "info")
                            glyph: row.isCalc ? "=" : (row.isClip ? "⎘" : "i")
                            filled: true
                            color: row.isCalc ? Theme.fgOnAccent : Theme.dim
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: row.isEmoji
                            font.pixelSize: 24
                            text: modelData.glyph || ""
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: modelData.kind === "app" || modelData.kind === "action"
                            color: Theme.dim
                            font.pixelSize: Theme.fs
                            font.weight: Theme.wBold
                            font.family: Theme.fam(text, Theme.families)
                            text: (modelData.name || "?").charAt(0).toUpperCase()
                        }
                    }
                }
                Column {
                    anchors { left: ico.right; leftMargin: Theme.gap + 2; right: hint.left; rightMargin: 8
                              verticalCenter: ico.verticalCenter }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        color: row.selected ? Theme.fgOnSelected : Theme.fg
                        font.pixelSize: row.isCalc ? Theme.fsTitle + 2 : Theme.fs
                        font.weight: row.isCalc || row.selected ? Theme.wBold : Theme.wMedium
                        font.family: Theme.fam(text, Theme.families)
                        text: row.isNote ? I18n.tr(modelData.name) : modelData.name
                    }
                    Text {
                        width: parent.width
                        visible: !!modelData.generic
                        elide: Text.ElideRight
                        color: Theme.dim
                        font.pixelSize: Theme.fs - 2
                        font.family: Theme.fam(text, Theme.families)
                        text: modelData.generic || ""
                    }
                }
                // What Enter does on the selected row: launch, or copy a calculation.
                Text {
                    id: hint
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: ico.verticalCenter }
                    visible: row.selected && !row.isNote
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: "↵ " + I18n.tr(row.copies ? "launcher.copy" : "launcher.open")
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { lp.sel = row.index; lp.launch() }
                }
            }
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        }

        Text {
            anchors { centerIn: list }
            visible: lp.results.length === 0
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("launcher.empty")
        }
    }
}
