import QtQuick
import qs.core
import qs.components

// Make your own font by drawing it (K94, I415, docs/ux/handwriting.md). A list of your fonts and "Create new font"; then one letter at a time in
// a box with its shadow and lines: cancel, retry, or save and go on. Beside it the whole set: what is drawn shows as drawn, what is not shows its
// shadow; a click goes to it. Every letter can have several versions; each version is a font of its own, and Font Mix mixes them.
Item {
    required property var store
    required property var theme
    required property var i18n
    id: p
    objectName: "handwriting-panel"

    Watch { doc: "mod.handwriting" }
    property int cardWidth: 1020
    width: parent ? parent.width : cardWidth
    implicitHeight: col.implicitHeight
    property real fillHeight: 0
    property var placement: null

    readonly property var d: Store.docs["mod.handwriting"] || ({})
    readonly property var fonts: d.fonts || []
    readonly property string charset: d.charset || ""
    readonly property var chars: charset.split("")
    readonly property var lines: d.lines || ({ cap: 720, x: 480, ascent: 1000, descent: -300 })

    property string fontId: ""
    readonly property var font_: {
        for (var i = 0; i < fonts.length; i++) if (fonts[i].id === fontId) return fonts[i]
        return null
    }
    property int version: 1
    property int index: 0
    property var glyphs: ({})
    property string message: ""
    property var made: []
    readonly property string letter: chars[index] || ""
    function keyOf(v, c) { return v + ":" + c }
    readonly property int doneHere: chars.filter(function (c) { return !!p.glyphs[p.keyOf(p.version, c)] }).length
    readonly property bool complete: chars.length > 0 && doneHere === chars.length

    function fail(err) { message = err && err.msg ? I18n.tr(err.msg) : "" }
    function open(id) {
        Store.act("handwriting.font.get", { id: id }, function (m, err) {
            if (err) { fail(err); return }
            p.glyphs = m.data.glyphs || {}
            p.fontId = id
            p.version = 1
            p.message = ""
            p.made = []
            p.goFirstEmpty()
            keyCatcher.forceActiveFocus()
        })
    }
    function goFirstEmpty() {
        for (var i = 0; i < chars.length; i++) if (!glyphs[keyOf(version, chars[i])]) { go(i); return }
        go(0)
    }
    function go(i) {
        index = i
        var had = glyphs[keyOf(version, chars[i])]
        box.show(had ? JSON.parse(JSON.stringify(had)) : [])
    }
    function create() {
        Store.act("handwriting.font.create", { name: nameField.text }, function (m, err) {
            if (err) { fail(err); return }
            nameField.text = ""
            p.open(m.data.id)
        })
    }
    // Save and go on: the next letter of this version without a drawing.
    function saveNext() {
        if (box.strokes.length === 0) { goNext(); return }
        var c = letter, s = box.strokes
        Store.act("handwriting.glyph.save", { id: fontId, version: version, char: c, strokes: s }, function (m, err) {
            if (err) { fail(err); return }
            var g = Object.assign({}, p.glyphs)
            g[p.keyOf(p.version, c)] = s
            p.glyphs = g
            p.message = ""
            p.goNext()
        })
    }
    function goNext() {
        for (var k = 1; k <= chars.length; k++) {
            var i = (index + k) % chars.length
            if (!glyphs[keyOf(version, chars[i])]) { go(i); return }
        }
        go((index + 1) % chars.length)
    }
    function setVersion(v) { version = v; goFirstEmpty(); keyCatcher.forceActiveFocus() }
    function addVersion() {
        Store.act("handwriting.font.versions", { id: fontId, count: font_.versions + 1 }, function (m, err) {
            if (err) fail(err); else p.setVersion(p.font_.versions + 1)
        })
    }
    function make() {
        Store.act("handwriting.font.make", { id: fontId }, function (m, err) {
            if (err) { fail(err); return }
            p.made = m.data.families
            p.message = I18n.tr("mod-handwriting.made").replace("{names}", p.made.join(", "))
        })
    }
    // Into the shell: one version is a font; several are a mix (K93).
    function use() {
        var f = made
        var ops = f.length > 1
            ? [{ set: "theme.typography.mix.preset", value: "custom" }, { set: "theme.typography.mix.count", value: Math.min(8, f.length) },
               { set: "theme.typography.mix.fonts", value: f }]
            : [{ set: "theme.typography.family", value: [f[0], "sans-serif"] }]
        Store.apply(ops, function (errors) {
            p.message = errors && errors.length ? I18n.tr("mod-handwriting.use_refused") : I18n.tr("mod-handwriting.used")
        })
    }

    component Btn: Rectangle {
        id: b
        property string label: ""
        property bool primary: false
        property bool enabled_: true
        signal clicked()
        implicitWidth: t.implicitWidth + 2 * Theme.pad
        implicitHeight: t.implicitHeight + Theme.gap
        radius: Theme.rSm
        opacity: enabled_ ? 1 : 0.45
        color: primary ? Theme.accent : Theme.containerHigh
        border.width: primary ? 0 : 1
        border.color: Theme.outline
        Accessible.role: Accessible.Button
        Accessible.name: label
        Text {
            id: t
            anchors.centerIn: parent
            text: b.label
            color: b.primary ? Theme.fgOnAccent : Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
        }
        MouseArea { anchors.fill: parent; enabled: b.enabled_; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }

    Column {
        id: col
        width: p.width
        spacing: Theme.gap

        Text {
            visible: p.message !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: p.message
            color: Theme.accent
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
        }

        // ---- your fonts ----
        Column {
            visible: p.fontId === ""
            width: parent.width
            spacing: Theme.gap
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: I18n.tr("mod-handwriting.intro")
                color: Theme.dim
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
            }
            Row {
                spacing: Theme.gap
                Rectangle {
                    width: 320
                    height: createBtn.height
                    radius: Theme.rSm
                    color: Theme.containerHigh
                    border.width: 1
                    border.color: Theme.outline
                    TextInput {
                        id: nameField
                        objectName: "handwriting-name"
                        anchors.fill: parent
                        anchors.margins: Theme.xs + 2
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.fg
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                        clip: true
                        onAccepted: p.create()
                        Text {
                            visible: !parent.text
                            text: I18n.tr("mod-handwriting.name_hint")
                            color: Theme.dim
                            anchors.verticalCenter: parent.verticalCenter
                            font: parent.font
                        }
                    }
                }
                Btn {
                    id: createBtn
                    primary: true
                    enabled_: nameField.text.trim() !== ""
                    label: I18n.tr("mod-handwriting.create")
                    onClicked: p.create()
                }
            }
            Repeater {
                model: p.fonts
                Row {
                    required property var modelData
                    spacing: Theme.gap
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 480
                        elide: Text.ElideRight
                        text: parent.modelData.name + "   " + I18n.tr("mod-handwriting.progress")
                            .replace("{done}", Math.max.apply(null, parent.modelData.done)).replace("{all}", p.chars.length)
                            .replace("{versions}", parent.modelData.versions)
                        color: Theme.fg
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                    }
                    Btn { label: I18n.tr("mod-handwriting.open"); onClicked: p.open(parent.modelData.id) }
                    Btn {
                        label: I18n.tr("mod-handwriting.delete")
                        onClicked: Store.act("handwriting.font.delete", { id: parent.modelData.id }, function (m, err) { if (err) p.fail(err) })
                    }
                }
            }
        }

        // ---- a font: the box and the set ----
        Item {
            id: keyCatcher
            visible: p.fontId !== ""
            width: parent.width
            height: editor.implicitHeight
            focus: visible
            Keys.onReturnPressed: p.saveNext()
            Keys.onEnterPressed: p.saveNext()
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Z && (e.modifiers & Qt.ControlModifier)) { box.undo(); e.accepted = true }
                else if (e.key === Qt.Key_R && !(e.modifiers & Qt.ControlModifier)) { box.clear(); e.accepted = true }
                else if (e.key === Qt.Key_Escape && p.fontId !== "") { p.fontId = ""; e.accepted = true }
            }
            Column {
                id: editor
                width: parent.width
                spacing: Theme.gap
                // The font, its versions, the pen.
                Row {
                    spacing: Theme.gap
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: p.font_ ? p.font_.name : ""
                        color: Theme.fg
                        font.pixelSize: Theme.fs + 2
                        font.weight: Theme.wBold
                        font.family: Theme.fam(text, Theme.families)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("mod-handwriting.version")
                        color: Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.family: Theme.fam(text, Theme.families)
                    }
                    Repeater {
                        model: p.font_ ? p.font_.versions : 0
                        Btn {
                            required property int index
                            primary: p.version === index + 1
                            label: String(index + 1)
                            onClicked: p.setVersion(index + 1)
                        }
                    }
                    Btn { label: "+"; enabled_: !!p.font_ && p.font_.versions < 8; onClicked: p.addVersion() }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("mod-handwriting.pen")
                        color: Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.family: Theme.fam(text, Theme.families)
                    }
                    Repeater {
                        model: [32, 56, 84]
                        Btn {
                            required property int modelData
                            primary: !!p.font_ && Math.round(p.font_.pen) === modelData
                            label: I18n.tr("mod-handwriting.pen." + modelData)
                            onClicked: Store.act("handwriting.font.pen", { id: p.fontId, pen: modelData })
                        }
                    }
                }
                Row {
                    spacing: Theme.pad
                    Column {
                        spacing: Theme.gap
                        DrawBox {
                            id: box
                            objectName: "handwriting-box"
                            width: 400
                            height: 520
                            letter: p.letter
                            pen: p.font_ ? p.font_.pen : 56
                            lines: p.lines
                        }
                        Row {
                            spacing: Theme.gap
                            Btn { objectName: "handwriting-cancel"; label: I18n.tr("mod-handwriting.cancel"); onClicked: p.fontId = "" }
                            Btn { objectName: "handwriting-retry"; label: I18n.tr("mod-handwriting.retry"); onClicked: box.clear() }
                            Btn {
                                objectName: "handwriting-save"
                                primary: true
                                label: I18n.tr("mod-handwriting.save_next")
                                onClicked: p.saveNext()
                            }
                        }
                    }
                    Column {
                        width: p.width - box.width - Theme.pad
                        spacing: Theme.gap
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: I18n.tr("mod-handwriting.overview").replace("{done}", p.doneHere).replace("{all}", p.chars.length)
                            color: Theme.dim
                            font.pixelSize: Theme.fsCaption
                            font.family: Theme.fam(text, Theme.families)
                        }
                        Flow {
                            width: parent.width
                            spacing: 4
                            Repeater {
                                model: p.chars
                                GlyphCell {
                                    required property string modelData
                                    required property int index
                                    width: 44
                                    height: 56
                                    letter: modelData
                                    lines: p.lines
                                    pen: p.font_ ? p.font_.pen : 56
                                    current: index === p.index
                                    strokes: p.glyphs[p.keyOf(p.version, modelData)] || null
                                    onChosen: { p.go(index); keyCatcher.forceActiveFocus() }
                                }
                            }
                        }
                        Row {
                            spacing: Theme.gap
                            Btn {
                                objectName: "handwriting-make"
                                primary: p.complete
                                enabled_: p.doneHere > 0
                                label: I18n.tr("mod-handwriting.make")
                                onClicked: p.make()
                            }
                            Btn {
                                objectName: "handwriting-use"
                                visible: p.made.length > 0
                                primary: true
                                label: I18n.tr("mod-handwriting.use")
                                onClicked: p.use()
                            }
                        }
                    }
                }
            }
        }
    }
    Component.onCompleted: if (p.fonts.length === 0) nameField.forceActiveFocus()
}
