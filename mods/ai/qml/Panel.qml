import QtQuick
import qs.core
import qs.components
import "Ai.js" as A

// Panel of the AI mod (card W28-ai, docs/ux/ai.md "Design"). The Stage card hosts it and draws the frame. Header (the
// conversation's title, history, new chat), the model chip with its picker, the messages (questions in bubbles, answers
// as the daemon's blocks: Markdown text, code with a copy button, folded reasoning), the composer. Every value is the
// daemon's; every change is an action. Chat view after ii's `sidebarLeft/aiChat` (message blocks, code header with copy).
Item {
    // Handed in by ModLoader (K26 loader contract; the core singletons are imported too).
    required property var store
    required property var theme
    required property var i18n
    id: p

    // Visible = open: the document is subscribed only while the panel can be seen (Ma).
    property bool live: visible
    Watch { doc: "mod.ai"; active: p.live }

    property int cardWidth: 560
    width: parent ? parent.width : cardWidth
    implicitHeight: body.implicitHeight
    // A host that gives the panel more height than it needs (the left sidebar, W29 row 238) gets a conversation that
    // fills it and the composer at the bottom; the Stage card sizes the panel to its implicit height, so `extra` stays 0
    // there. Updated imperatively (natural height = the body without `extra`), so no binding loop.
    property real extra: 0
    function relayout() {
        var e = Math.max(0, p.height - (body.implicitHeight - p.extra))
        if (Math.abs(e - p.extra) > 0.5) p.extra = e
    }
    onHeightChanged: relayout()

    readonly property var d: Store.docs["mod.ai"] || ({})
    readonly property bool loaded: d.provider !== undefined
    readonly property var prov: d.provider || ({})
    readonly property var cur: d.current || ({})
    readonly property var msgs: cur.messages || []
    readonly property var reply: d.reply || null
    readonly property bool busy: d.busy === true
    readonly property var models: d.models || ({})
    readonly property var convs: d.conversations || []
    readonly property bool cloud: p.prov.local === false

    // "chat" or "history".
    property string view: "chat"
    property bool picking: false
    // What the last refused action said (an i18n key); cleared by the next success.
    property string errorKey: ""
    // The block or message copied last ("m:b"), for a moment of "Copied".
    property string copied: ""

    Accessible.role: Accessible.Pane
    Accessible.name: I18n.tr("mod-ai.panel.title")

    Component.onCompleted: Qt.callLater(function () { input.forceActiveFocus() })

    function tr(k) { return I18n.tr(k) }
    function act(name, args, then) {
        Store.act(name, args, function (done, err) {
            p.errorKey = err ? (err.msg || "mod-ai.error.provider") : ""
            if (then) then(done, err)
        })
    }
    function send() {
        var text = input.text.trim()
        if (text === "" || p.busy) return
        p.act("ai.ask", { text: text }, function (done, err) { if (!err) input.text = "" })
        p.view = "chat"
    }
    function copy(msg, block) {
        var args = { message: msg }
        if (block !== undefined && block >= 0) args.block = block
        p.act("ai.copy", args, function (done, err) {
            if (!err) { p.copied = msg + ":" + (block === undefined ? -1 : block); copiedTimer.restart() }
        })
    }
    function openPicker() {
        p.picking = !p.picking
        if (p.picking) p.act("ai.models", {})
    }
    Timer { id: copiedTimer; interval: 1500; onTriggered: p.copied = "" }

    component Line: Text {
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
    }
    component Caption: Text {
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.weight: Theme.wBold
        font.letterSpacing: 1
        font.capitalization: Font.AllUppercase
        font.family: Theme.fam(text, Theme.families)
    }

    // The blocks of an answer (or of the reply being written). `msg` is the message's index, -1 for the reply.
    component Blocks: Column {
        id: bl
        property var blocks: []
        property int msg: -1
        spacing: Theme.gap
        Repeater {
            // By count: a block whose text grows keeps its delegate (the reply streams into the last one).
            model: bl.blocks.length
            delegate: Item {
                id: blk
                required property int index
                readonly property var b: bl.blocks[index] || ({})
                width: bl.width
                height: b.kind === "code" ? code.height : (b.kind === "think" ? think.height : md.height)

                // ---- Markdown text ----
                Text {
                    id: md
                    visible: blk.b.kind === "text"
                    width: parent.width
                    height: visible ? implicitHeight : 0
                    wrapMode: Text.Wrap
                    textFormat: Text.MarkdownText
                    color: Theme.fg
                    linkColor: Theme.accent
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    text: visible ? (blk.b.text || "") : ""
                }

                // ---- code: language and copy in a header, monospace body ----
                Rectangle {
                    id: code
                    visible: blk.b.kind === "code"
                    width: parent.width
                    height: visible ? codeCol.implicitHeight : 0
                    radius: Theme.rSm
                    color: Theme.surface
                    border.width: 1
                    border.color: Theme.outline
                    clip: true
                    Column {
                        id: codeCol
                        width: parent.width
                        Item {
                            width: parent.width
                            height: Theme.controlH
                            Line {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.pad
                                anchors.verticalCenter: parent.verticalCenter
                                text: blk.b.lang || p.tr("mod-ai.code")
                            }
                            IconButton {
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.xs
                                anchors.verticalCenter: parent.verticalCenter
                                visible: bl.msg >= 0
                                icon: p.copied === bl.msg + ":" + blk.index ? "check" : "content_copy"
                                glyph: p.copied === bl.msg + ":" + blk.index ? "✓" : "⧉"
                                a11y: p.tr("mod-ai.a11y.copy_code")
                                onClicked: p.copy(bl.msg, blk.index)
                            }
                        }
                        Rectangle { width: parent.width; height: 1; color: Theme.outline }
                        Text {
                            width: parent.width
                            padding: Theme.pad
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            textFormat: Text.PlainText
                            color: Theme.fg
                            font.pixelSize: Theme.fs - 1
                            font.family: Theme.tok("font.family_mono", "monospace")
                            text: blk.b.text || ""
                        }
                    }
                }

                // ---- reasoning: one dim line, unfolded on a click ----
                Column {
                    id: think
                    visible: blk.b.kind === "think"
                    width: parent.width
                    height: visible ? implicitHeight : 0
                    spacing: Theme.xs
                    property bool unfolded: false
                    Item {
                        id: thinkHead
                        width: parent.width
                        height: Math.max(24, thinkLabel.implicitHeight)
                        activeFocusOnTab: think.visible
                        Accessible.role: Accessible.Button
                        Accessible.name: p.tr("mod-ai.a11y.think_toggle")
                        Keys.onReturnPressed: think.unfolded = !think.unfolded
                        Keys.onSpacePressed: think.unfolded = !think.unfolded
                        Line {
                            id: thinkLabel
                            anchors.verticalCenter: parent.verticalCenter
                            text: (think.unfolded ? "▾ " : "▸ ") + p.tr(blk.b.open ? "mod-ai.thinking" : "mod-ai.thought")
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: think.unfolded = !think.unfolded }
                        FocusRing { anchors.fill: parent; shown: thinkHead.activeFocus; corner: Theme.rSm }
                    }
                    Text {
                        width: parent.width
                        leftPadding: Theme.pad
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        color: Theme.dim
                        font.pixelSize: Theme.fs - 1
                        font.italic: true
                        font.family: Theme.fam(text, Theme.families)
                        maximumLineCount: think.unfolded ? 1000 : 2
                        elide: Text.ElideRight
                        text: blk.b.text || ""
                    }
                }
            }
        }
    }

    Column {
        id: body
        width: parent.width
        spacing: Theme.gap
        onImplicitHeightChanged: Qt.callLater(p.relayout)

        // ---- header: the title, history, new chat ----
        Row {
            width: parent.width
            spacing: Theme.xs
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - histBtn.width - newBtn.width - 2 * parent.spacing
                elide: Text.ElideRight
                color: Theme.fg
                font.pixelSize: Theme.fsTitle
                font.weight: Theme.wBold
                font.family: Theme.fam(text, Theme.families)
                text: p.view === "history" ? p.tr("mod-ai.history")
                    : (p.cur.title ? p.cur.title : p.tr("mod-ai.new_chat"))
            }
            IconButton {
                id: histBtn
                anchors.verticalCenter: parent.verticalCenter
                icon: "history"; glyph: "≡"
                a11y: p.tr("mod-ai.a11y.history")
                lit: p.view === "history"
                onClicked: { p.view = p.view === "history" ? "chat" : "history"; p.picking = false }
            }
            IconButton {
                id: newBtn
                anchors.verticalCenter: parent.verticalCenter
                icon: "edit_square"; glyph: "+"
                a11y: p.tr("mod-ai.a11y.new")
                enabled: !p.busy && (p.msgs.length > 0 || p.view === "history")
                onClicked: p.act("ai.new", {}, function (done, err) { if (!err) { p.view = "chat"; input.forceActiveFocus() } })
            }
        }

        // ---- the model chip: provider · model, a click opens the picker ----
        Item {
            id: chipRow
            visible: p.loaded
            width: parent.width
            height: Theme.controlH - 4
            Rectangle {
                id: chip
                height: parent.height
                width: Math.min(parent.width, chipText.implicitWidth + dot.width + 3 * Theme.gap + 16)
                radius: Theme.rFull
                color: chipMouse.containsMouse || chip.activeFocus ? Theme.containerHigh : Theme.surface
                border.width: 1
                border.color: Theme.outline
                activeFocusOnTab: true
                Accessible.role: Accessible.ComboBox
                Accessible.name: A.fill(p.tr("mod-ai.a11y.model"), { model: chipText.text })
                Keys.onReturnPressed: p.openPicker()
                Keys.onSpacePressed: p.openPicker()
                Rectangle {
                    id: dot
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.gap + 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8; height: 8; radius: 4
                    color: p.prov.state === "ready" ? Theme.tertiary : (p.prov.state === "error" ? Theme.error : Theme.outline)
                }
                Text {
                    id: chipText
                    anchors.left: dot.right
                    anchors.leftMargin: Theme.gap
                    anchors.right: chevron.left
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    color: Theme.fg
                    font.pixelSize: Theme.fsLabel
                    font.family: Theme.fam(text, Theme.families)
                    text: A.chipText(p.tr, p.prov)
                }
                Text {
                    id: chevron
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.gap
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.dim
                    font.pixelSize: Theme.fsLabel
                    text: p.picking ? "▴" : "▾"
                }
                MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: p.openPicker() }
                FocusRing { anchors.fill: parent; shown: chip.activeFocus; corner: Theme.rFull }
            }
            Line {
                anchors.left: chip.right
                anchors.leftMargin: Theme.gap
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                visible: !!p.prov.key
                text: A.fill(p.tr("mod-ai.key_from"), { key: p.prov.key || "" })
            }
        }

        // ---- the model picker ----
        Rectangle {
            visible: p.picking && p.loaded
            width: parent.width
            height: visible ? pickCol.implicitHeight + 2 * Theme.xs : 0
            radius: Theme.rSm
            color: Theme.surface
            border.width: 1
            border.color: Theme.outline
            Column {
                id: pickCol
                x: Theme.xs; y: Theme.xs
                width: parent.width - 2 * Theme.xs
                Line {
                    visible: p.models.state === "loading" || p.models.state === "idle"
                    padding: Theme.gap
                    text: p.tr("mod-ai.models.loading")
                }
                Text {
                    visible: p.models.state === "error"
                    width: parent.width
                    padding: Theme.gap
                    wrapMode: Text.Wrap
                    color: Theme.error
                    font.pixelSize: Theme.fs - 1
                    font.family: Theme.fam(text, Theme.families)
                    text: p.models.state === "error" ? A.errorText(p.tr, p.models.reason, p.prov, p.models.detail)
                        + (A.detailShown(p.models.reason, p.models.detail) ? "\n" + p.models.detail : "") : ""
                }
                Line {
                    visible: p.models.state === "ready" && (p.models.list || []).length === 0
                    padding: Theme.gap
                    text: p.tr(p.prov.id === "ollama" ? "mod-ai.error.no_models" : "mod-ai.models.empty")
                }
                Flickable {
                    width: parent.width
                    height: Math.min(pickList.implicitHeight, 260)
                    contentHeight: pickList.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height
                    Column {
                        id: pickList
                        width: parent.width
                        Repeater {
                            model: p.prov.id === "ollama" && p.models.state === "ready" && (p.models.list || []).length > 0
                                ? [{ id: "", detail: "" }].concat(p.models.list) : (p.models.list || [])
                            delegate: Item {
                                id: row
                                required property var modelData
                                readonly property bool chosen: modelData.id === "" ? !!p.prov.auto : (!p.prov.auto && p.prov.model === modelData.id)
                                width: pickList.width
                                height: 32
                                activeFocusOnTab: true
                                Accessible.role: Accessible.ListItem
                                Accessible.name: rowText.text
                                Accessible.selected: row.chosen
                                function pick() { p.picking = false; p.act("ai.model", { model: row.modelData.id }) }
                                Keys.onReturnPressed: row.pick()
                                Keys.onSpacePressed: row.pick()
                                HoverHandler { id: rowHover }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.rSm
                                    color: row.chosen ? Theme.selected : Theme.containerHigh
                                    visible: row.chosen || rowHover.hovered || row.activeFocus
                                }
                                Text {
                                    id: rowText
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.gap
                                    anchors.right: rowDetail.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                    color: row.chosen ? Theme.fgOnSelected : Theme.fg
                                    font.pixelSize: Theme.fs
                                    font.family: Theme.fam(text, Theme.families)
                                    text: row.modelData.id === "" ? p.tr("mod-ai.models.auto") : row.modelData.id
                                }
                                Line {
                                    id: rowDetail
                                    anchors.right: parent.right
                                    anchors.rightMargin: Theme.gap
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.modelData.detail || ""
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: row.pick() }
                            }
                        }
                    }
                }
            }
        }

        Line {
            visible: !p.loaded
            text: p.tr("mod-ai.loading")
        }

        // ================= history =================
        Column {
            visible: p.loaded && p.view === "history"
            width: parent.width
            spacing: Theme.xs
            Line {
                visible: p.convs.length === 0
                topPadding: Theme.pad
                bottomPadding: Theme.pad
                text: p.tr(p.d.saving === false ? "mod-ai.history.off" : "mod-ai.history.empty")
            }
            Flickable {
                visible: p.convs.length > 0
                width: parent.width
                height: Math.min(histCol.implicitHeight, 480)
                contentHeight: histCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                Column {
                    id: histCol
                    width: parent.width
                    Repeater {
                        model: p.convs
                        delegate: Item {
                            id: hrow
                            required property var modelData
                            readonly property bool here: p.cur.id === modelData.id
                            width: histCol.width
                            height: 40
                            activeFocusOnTab: true
                            Accessible.role: Accessible.ListItem
                            Accessible.name: hrow.modelData.title
                            function openIt() { p.act("ai.open", { id: hrow.modelData.id }, function (done, err) { if (!err) p.view = "chat" }) }
                            Keys.onReturnPressed: openIt()
                            Keys.onPressed: function (e) { if (e.key === Qt.Key_Delete) { p.act("ai.delete", { id: hrow.modelData.id }); e.accepted = true } }
                            HoverHandler { id: hHover }
                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.rSm
                                color: hrow.here ? Theme.selected : Theme.containerHigh
                                visible: hrow.here || hHover.hovered || hrow.activeFocus
                                opacity: hrow.here ? 1 : 0.6
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.gap
                                anchors.right: hWhen.left
                                anchors.rightMargin: Theme.gap
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                color: hrow.here ? Theme.fgOnSelected : Theme.fg
                                font.pixelSize: Theme.fs
                                font.family: Theme.fam(text, Theme.families)
                                text: hrow.modelData.title
                            }
                            Line {
                                id: hWhen
                                anchors.right: hDel.left
                                anchors.rightMargin: Theme.xs
                                anchors.verticalCenter: parent.verticalCenter
                                text: A.when(hrow.modelData.updated)
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: hrow.openIt() }
                            IconButton {
                                id: hDel
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.xs
                                anchors.verticalCenter: parent.verticalCenter
                                icon: "delete"; glyph: "×"
                                a11y: A.fill(p.tr("mod-ai.a11y.delete"), { title: hrow.modelData.title })
                                opacity: hHover.hovered || hrow.activeFocus || activeFocus ? 1 : 0
                                enabled: !(p.busy && hrow.here)
                                onClicked: p.act("ai.delete", { id: hrow.modelData.id })
                            }
                        }
                    }
                }
            }
        }

        // ================= chat =================
        Column {
            visible: p.loaded && p.view === "chat"
            width: parent.width
            spacing: Theme.gap

            // Empty: what answers and where it comes from.
            Column {
                visible: p.msgs.length === 0 && !p.reply
                width: parent.width
                spacing: Theme.gap
                topPadding: Theme.pad * 2
                bottomPadding: Theme.pad * 2
                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "auto_awesome"; glyph: "✦"
                    size: 36
                    color: Theme.secondary
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Theme.fg
                    font.pixelSize: Theme.fsTitle
                    font.weight: Theme.wBold
                    font.family: Theme.fam(text, Theme.families)
                    text: p.tr("mod-ai.empty.title")
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    color: Theme.dim
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    text: A.fill(p.tr(p.cloud ? "mod-ai.empty.cloud" : "mod-ai.empty.local"), { provider: A.providerLabel(p.tr, p.prov.id) })
                }
                Text {
                    visible: p.prov.state === "error"
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    color: Theme.error
                    font.pixelSize: Theme.fs - 1
                    font.family: Theme.fam(text, Theme.families)
                    text: p.prov.state === "error" ? A.errorText(p.tr, p.prov.reason, p.prov, p.prov.detail) : ""
                }
                Button {
                    visible: p.prov.state === "error"
                    anchors.horizontalCenter: parent.horizontalCenter
                    label: p.tr("mod-ai.check")
                    onClicked: p.act("ai.models", {})
                }
                Line {
                    visible: p.d.saving === false
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: p.tr("mod-ai.history.off")
                }
            }

            // The conversation; it follows the bottom while the user has not scrolled up.
            Flickable {
                id: flick
                visible: p.msgs.length > 0 || !!p.reply
                width: parent.width
                height: 460 + p.extra
                contentHeight: convCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                property bool stick: true
                onContentHeightChanged: if (stick) contentY = Math.max(0, contentHeight - height)
                onVisibleChanged: if (visible) { stick = true; contentY = Math.max(0, contentHeight - height) }
                onMovementEnded: stick = contentY >= contentHeight - height - 8
                Column {
                    id: convCol
                    width: flick.width
                    spacing: Theme.pad
                    Repeater {
                        model: p.msgs.length
                        delegate: Item {
                            id: msg
                            required property int index
                            readonly property var m: p.msgs[index] || ({})
                            readonly property bool mine: m.role === "user"
                            readonly property bool lastOne: index === p.msgs.length - 1
                            width: convCol.width
                            height: mine ? bubble.height : answer.implicitHeight
                            activeFocusOnTab: true
                            Accessible.role: Accessible.ListItem
                            Accessible.name: mine ? A.fill(p.tr("mod-ai.a11y.user"), { text: m.text || "" }) : p.tr("mod-ai.a11y.answer")
                            Keys.onPressed: function (e) {
                                if (e.key === Qt.Key_C && (e.modifiers & Qt.ControlModifier)) { p.copy(msg.index); e.accepted = true }
                            }
                            FocusRing { anchors.fill: parent; shown: msg.activeFocus; corner: Theme.rSm }

                            // A question: a tonal bubble on the right.
                            Rectangle {
                                id: bubble
                                visible: msg.mine
                                anchors.right: parent.right
                                width: Math.min(parent.width * 0.82, qText.implicitWidth + 2 * Theme.pad)
                                height: visible ? qText.implicitHeight + 2 * Theme.gap : 0
                                radius: Theme.rLg > 0 ? Math.min(Theme.rLg, 16) : Theme.rSm
                                color: Theme.selected
                                Text {
                                    id: qText
                                    x: Theme.pad; y: Theme.gap
                                    width: Math.min(implicitWidth, msg.width * 0.82 - 2 * Theme.pad)
                                    wrapMode: Text.Wrap
                                    textFormat: Text.PlainText
                                    color: Theme.fgOnSelected
                                    font.pixelSize: Theme.fs
                                    font.family: Theme.fam(text, Theme.families)
                                    text: msg.mine ? (msg.m.text || "") : ""
                                }
                            }

                            // An answer: its blocks, its error or stop, and (last one) copy and regenerate.
                            Column {
                                id: answer
                                visible: !msg.mine
                                width: parent.width
                                spacing: Theme.xs
                                Blocks { width: parent.width; blocks: msg.mine ? [] : (msg.m.blocks || []); msg: msg.index }
                                Text {
                                    visible: !!msg.m.error
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                    color: Theme.error
                                    font.pixelSize: Theme.fs
                                    font.family: Theme.fam(text, Theme.families)
                                    text: msg.m.error ? A.errorText(p.tr, msg.m.error, p.prov, msg.m.detail) : ""
                                }
                                Line {
                                    visible: !!msg.m.error && A.detailShown(msg.m.error, msg.m.detail)
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                    text: msg.m.detail || ""
                                }
                                Row {
                                    visible: !msg.mine
                                    spacing: Theme.xs
                                    Line {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: msg.m.stopped === true
                                        color: Theme.warning
                                        text: p.tr("mod-ai.stopped")
                                    }
                                    Line {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: !!msg.m.model
                                        text: msg.m.model || ""
                                    }
                                    IconButton {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: (msg.m.blocks || []).length > 0
                                        icon: p.copied === msg.index + ":-1" ? "check" : "content_copy"
                                        glyph: p.copied === msg.index + ":-1" ? "✓" : "⧉"
                                        a11y: p.tr("mod-ai.copy")
                                        onClicked: p.copy(msg.index)
                                    }
                                    IconButton {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: msg.lastOne && !p.busy
                                        icon: "refresh"; glyph: "↻"
                                        a11y: p.tr(msg.m.error ? "mod-ai.retry" : "mod-ai.regenerate")
                                        onClicked: p.act("ai.regenerate", {})
                                    }
                                }
                            }
                        }
                    }
                    // The reply being written.
                    Column {
                        visible: !!p.reply
                        width: convCol.width
                        spacing: Theme.xs
                        Line {
                            visible: !!p.reply && p.reply.waiting === true
                            font.pixelSize: Theme.fs
                            text: p.tr("mod-ai.thinking")
                        }
                        Blocks { width: parent.width; blocks: p.reply ? (p.reply.blocks || []) : []; msg: -1 }
                    }
                }
            }

            // The room a taller host gives, while there is no conversation to fill it: the composer stays at the bottom.
            Item { width: 1; height: flick.visible ? 0 : p.extra }

            // ---- the composer ----
            Row {
                width: parent.width
                spacing: Theme.xs
                Rectangle {
                    id: field
                    width: parent.width - sendBtn.width - parent.spacing
                    height: Math.min(Math.max(Theme.controlH + 4, input.implicitHeight + 2 * Theme.gap), 140)
                    radius: Theme.keycap ? Theme.rFull : Theme.rSm
                    color: Theme.surface
                    border.width: input.activeFocus ? Math.max(1, Theme.outlineW) : 1
                    border.color: input.activeFocus ? Theme.focusRing : Theme.outline
                    Flickable {
                        id: inFlick
                        anchors.fill: parent
                        anchors.leftMargin: Theme.pad
                        anchors.rightMargin: Theme.pad
                        anchors.topMargin: Theme.gap
                        anchors.bottomMargin: Theme.gap
                        contentHeight: input.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        function follow(r) {
                            if (contentY >= r.y) contentY = r.y
                            else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height
                        }
                        TextEdit {
                            id: input
                            width: inFlick.width
                            wrapMode: TextEdit.Wrap
                            textFormat: TextEdit.PlainText
                            color: Theme.fg
                            selectionColor: Theme.selected
                            selectedTextColor: Theme.fgOnSelected
                            font.pixelSize: Theme.fs
                            font.family: Theme.fam(text, Theme.families)
                            onCursorRectangleChanged: inFlick.follow(cursorRectangle)
                            Accessible.role: Accessible.EditableText
                            Accessible.name: placeholder.text
                            Keys.onPressed: function (e) {
                                if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) {
                                    p.send(); e.accepted = true
                                } else if (e.key === Qt.Key_Escape && p.busy) {
                                    p.act("ai.stop", {}); e.accepted = true
                                }
                            }
                        }
                        Text {
                            id: placeholder
                            visible: input.text === "" && !input.preeditText
                            width: parent.width
                            elide: Text.ElideRight
                            color: Theme.dim
                            font: input.font
                            text: A.fill(p.tr("mod-ai.input.hint"), { provider: A.providerLabel(p.tr, p.prov.id) })
                        }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onPressed: function (m) { input.forceActiveFocus(); m.accepted = false } }
                }
                IconButton {
                    id: sendBtn
                    anchors.bottom: field.bottom
                    anchors.bottomMargin: (Theme.controlH + 4 - height) / 2
                    icon: p.busy ? "stop_circle" : "arrow_upward"
                    glyph: p.busy ? "■" : "↑"
                    a11y: p.tr(p.busy ? "mod-ai.stop" : "mod-ai.send")
                    lit: p.busy || input.text.trim() !== ""
                    enabled: p.busy || input.text.trim() !== ""
                    onClicked: p.busy ? p.act("ai.stop", {}) : p.send()
                }
            }
            Text {
                visible: p.errorKey !== ""
                width: parent.width
                wrapMode: Text.Wrap
                color: Theme.error
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: p.errorKey !== "" ? p.tr(p.errorKey) : ""
            }
        }
    }
}
