import QtQuick
import "../core"

// The palette editor (I453, docs/ux/palettes.md "Custom palettes"): a name, Dark | Light, one row per role with its
// swatch, hex and provenance (yours or derived), the colour picker under the row being picked, "you picked X, shown as
// Y" where a stage of the theme moves a colour, and a sample card of the side being edited. While it is open the shell
// wears the draft (`palette.draft`: the daemon holds it, writes nothing); Save writes the file and picks the palette,
// Cancel / Escape / leaving end the draft (`palette.draft.clear`, and the daemon ends it itself when Settings goes).
// Everything it shows — the derived colours, the moved ones and why, the file name — is the daemon's answer (rule 1).
Column {
    id: ed
    // "new": a copy of `name` (a palette of any kind); "edit": the user's palette `name` itself.
    property string mode: "new"
    property string name: ""
    // The custom view's `palette.list` reply (the folder, whether it can be written, the picker's quick swatches).
    property var listInfo: null
    signal closed(bool saved)

    property bool loaded: false
    property string loadError: ""
    property string label: ""
    // The palette's roles per side, in the file's shape ({<role>: "#hex", terminal?: {…}}), or null for a side it lacks.
    property var pal: ({ dark: null, light: null })
    property string side: Theme.darkScheme ? "dark" : "light"
    // The daemon's last answer: the file name a save writes, why it is not the label's own, and the draft as shown.
    property var resolved: ({})
    property string fileName: ""
    property string note: ""
    property bool managed: false
    property string saveError: ""
    property bool saved: false
    // The role whose picker is open, and its colour before it opened ("" = it was derived).
    property string picking: ""
    property string pickStart: ""

    readonly property var required: ["surface", "on_surface", "accent", "secondary", "tertiary", "warning"]
    readonly property var groups: [
        { id: "grounds", roles: ["surface", "surface_container", "outline"] },
        { id: "text", roles: ["on_surface", "on_surface_variant", "on_accent"] },
        { id: "colours", roles: ["accent", "secondary", "tertiary"] },
        { id: "states", roles: ["error", "warning", "success"] }
    ]
    readonly property bool writable: !ed.managed && !(ed.listInfo && ed.listInfo.writable === false)
    readonly property string dir: ed.listInfo ? ed.listInfo.dir : ""
    readonly property var shownRoles: (ed.resolved[ed.side] && ed.resolved[ed.side].roles) || ({})
    readonly property var moved: (ed.resolved[ed.side] && ed.resolved[ed.side].moved) || ({})
    readonly property bool hasSide: !!ed.pal[ed.side]
    readonly property bool hasTerminal: !!((ed.pal.dark && ed.pal.dark.terminal) || (ed.pal.light && ed.pal.light.terminal))

    function roleName(r) { return I18n.tr("palettes.editor.role." + r) }
    function own(r) { var p = ed.pal[ed.side]; return p && p[r] !== undefined ? p[r] : "" }
    function shown(r) { return ed.shownRoles[r] || "#808080" }
    // The colour a row shows: the one picked (yours), else the derived one as the shell shows it.
    function colourOf(r) { return ed.own(r) || ed.shown(r) }
    function copy(o) { return JSON.parse(JSON.stringify(o)) }
    function setRole(r, hex) {
        var p = ed.copy(ed.pal)
        if (!p[ed.side]) return
        if (hex === "") delete p[ed.side][r]
        else p[ed.side][r] = hex
        ed.pal = p
        ed.send()
    }
    function addSide() {
        var p = ed.copy(ed.pal)
        var other = ed.side === "dark" ? p.light : p.dark
        var roles = {}
        // The other side's colours as they show in this scheme: a start the user then changes.
        for (var i = 0; i < ed.required.length; i++) roles[ed.required[i]] = ed.shown(ed.required[i])
        if (other) for (var k in other) if (k !== "terminal" && roles[k] === undefined) roles[k] = other[k]
        p[ed.side] = roles
        ed.pal = p
        ed.send()
    }
    function removeSide() {
        var p = ed.copy(ed.pal)
        p[ed.side] = null
        ed.pal = p
        ed.send()
    }
    function args() {
        var a = { label: ed.label, dark: ed.pal.dark, light: ed.pal.light }
        if (ed.mode === "edit") a.replaces = ed.name
        return a
    }
    // One draft in flight at a time; the newest edit goes out when the answer is in (a drag sends at most one per answer).
    property bool inFlight: false
    property bool dirty: false
    function send() {
        if (!ed.loaded) return
        if (ed.inFlight) { ed.dirty = true; return }
        ed.inFlight = true
        ed.dirty = false
        Store.act("palette.draft", ed.args(), function (m) {
            ed.inFlight = false
            if (m.t === "done" && m.data) {
                ed.resolved = m.data.resolved || ({})
                ed.fileName = m.data.name || ""
                ed.note = m.data.note || ""
                ed.saveError = ""
            } else {
                ed.saveError = Store.actError(m, "palettes.error.args")
            }
            if (ed.dirty) ed.send()
        })
    }
    function save() {
        if (!ed.writable || ed.fileName === "") return
        ed.saveError = ""
        var a = ed.args()
        a.select = true
        Store.act("palette.save", a, function (m) {
            if (m.t === "done") { ed.saved = true; ed.closed(true) }
            else ed.saveError = Store.actError(m, "palettes.error.write")
        })
    }
    function cancel() {
        ed.ended = true
        Store.act("palette.draft.clear", {})
        ed.closed(false)
    }
    property bool ended: false
    function load() {
        var action = ed.mode === "edit" ? "palette.get" : "palette.duplicate"
        var a = ed.mode === "edit" ? { name: ed.name } : { from: ed.name }
        Store.act(action, a, function (m) {
            if (m.t !== "done" || !m.data) { ed.loadError = Store.actError(m, "palettes.error.unknown"); return }
            var d = m.data
            var p = d.palette || ({})
            ed.pal = { dark: p.dark || null, light: p.light || null }
            ed.resolved = d.resolved || ({})
            ed.managed = !!d.managed
            if (ed.mode === "edit") ed.label = p.label || ed.name
            else {
                var from = d.from_label || (d.label_key ? I18n.tr(d.label_key) : ed.name)
                ed.label = I18n.fmt("palettes.editor.copy_of", { name: from })
            }
            if (!ed.pal[ed.side]) ed.side = ed.pal.dark ? "dark" : "light"
            ed.loaded = true
            ed.send()
            Qt.callLater(function () { nameField.focusInput() })
        })
    }
    function openPicker(r) {
        ed.pickStart = ed.own(r)
        ed.picking = r
    }
    function closePicker(keep) {
        var r = ed.picking
        if (!keep) ed.setRole(r, ed.pickStart)
        ed.picking = ""
        Qt.callLater(function () { var s = ed.swatchOf(r); if (s) s.forceActiveFocus() })
    }
    function swatchOf(r) {
        var walk = function (item) {
            if (!item) return null
            if (item.objectName === "palette-role:" + r) return item
            var kids = item.children || []
            for (var i = 0; i < kids.length; i++) { var f = walk(kids[i]); if (f) return f }
            return null
        }
        return walk(ed)
    }
    function whyText(m) {
        var st = m.stages || []
        var words = st.map(function (s) {
            if (s === "wcag") return I18n.fmt("palettes.editor.why.wcag", { against: m.against ? ed.roleName(m.against) : "" })
            return I18n.has("palettes.editor.why." + s) ? I18n.tr("palettes.editor.why." + s) : s
        })
        return words.length ? words.join(", ") : I18n.tr("palettes.editor.why.other")
    }

    Component.onCompleted: ed.load()
    // Leaving without Save ends the draft (the daemon also ends it when Settings closes or crashes).
    Component.onDestruction: if (!ed.saved && !ed.ended) Store.act("palette.draft.clear", {})

    objectName: "palette-editor"
    spacing: Theme.pad
    Keys.onEscapePressed: event => {
        if (ed.picking !== "") ed.closePicker(false)
        else ed.cancel()
        event.accepted = true
    }

    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        text: ed.mode === "edit" ? I18n.fmt("palettes.editor.title_edit", { name: ed.label || ed.name }) : I18n.tr("palettes.editor.title_new")
        color: Theme.fg
        font.pixelSize: Theme.fsTitle
        font.weight: Theme.wBold
        font.family: Theme.fam(text, Theme.families)
    }
    Text {
        visible: !ed.loaded
        text: ed.loadError !== "" ? ed.loadError : I18n.tr("palettes.editor.loading")
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        color: ed.loadError !== "" ? Theme.error : Theme.dim
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
    }
    Button {
        visible: !ed.loaded && ed.loadError !== ""
        label: I18n.tr("palettes.editor.cancel")
        onClicked: ed.cancel()
    }

    // --- name and side ------------------------------------------------------------------------------------------------
    Row {
        visible: ed.loaded
        spacing: Theme.pad
        TextField {
            id: nameField
            width: 260
            label: I18n.tr("palettes.editor.name")
            placeholder: I18n.tr("palettes.editor.name")
            value: ed.label
            escapeTaken: false
            onTyping: t => { ed.label = t; ed.send() }
            onAccepted: t => { ed.label = t; ed.send() }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Text {
                objectName: "palette-file:" + ed.fileName
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                text: ed.fileName !== "" ? I18n.fmt("palettes.editor.file", { file: ed.fileName + ".toml" }) : ""
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: "monospace"
            }
            Text {
                visible: ed.note !== ""
                objectName: "palette-name-note"
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                text: ed.note !== "" ? I18n.fmt(ed.note, { file: ed.fileName + ".toml" }) : ""
                color: Theme.fg
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
            }
        }
    }
    Row {
        visible: ed.loaded
        spacing: Theme.pad
        ChoiceSwitch {
            objectName: "palette-side"
            label: I18n.tr("palettes.editor.sides")
            choices: [{ value: "dark", label: "palettes.editor.dark" }, { value: "light", label: "palettes.editor.light" }]
            current: ed.side
            cancellable: false
            onPicked: v => { ed.picking = ""; ed.side = v }
            onPreviewed: v => { ed.picking = ""; ed.side = v }
        }
        Button {
            visible: ed.hasSide && !!ed.pal.dark && !!ed.pal.light
            objectName: "palette-remove-side"
            label: I18n.tr("palettes.editor.remove_side")
            onClicked: ed.removeSide()
        }
    }
    // A side the palette lacks: what the pipeline does instead, and the way to add it.
    Row {
        visible: ed.loaded && !ed.hasSide
        spacing: Theme.pad
        Text {
            objectName: "palette-side-missing"
            anchors.verticalCenter: parent.verticalCenter
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            antialiasing: !Theme.pixelType
            text: I18n.tr(ed.side === "light" ? "palettes.editor.missing_light" : "palettes.editor.missing_dark")
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
        }
        Button {
            objectName: "palette-add-side"
            label: I18n.tr(ed.side === "light" ? "palettes.editor.add_light" : "palettes.editor.add_dark")
            onClicked: ed.addSide()
        }
    }

    // --- the roles and the sample -------------------------------------------------------------------------------------
    Row {
        visible: ed.loaded
        spacing: Theme.pad * 2
        Column {
            id: rolesCol
            width: Math.min(460, Math.max(320, ed.width - sample.width - Theme.pad * 2))
            spacing: Theme.gap
            visible: ed.hasSide
            Repeater {
                model: ed.groups
                delegate: Column {
                    id: grp
                    required property var modelData
                    width: rolesCol.width
                    spacing: 2
                    Text {
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        antialiasing: !Theme.pixelType
                        text: I18n.tr("palettes.editor.group." + grp.modelData.id)
                        color: Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.weight: Theme.wBold
                        font.family: Theme.fam(text, Theme.families)
                    }
                    Repeater {
                        model: grp.modelData.roles
                        delegate: Column {
                            id: row
                            required property string modelData
                            readonly property bool mine: ed.own(modelData) !== ""
                            readonly property bool must: ed.required.indexOf(modelData) >= 0
                            readonly property var mv: ed.moved[modelData] || null
                            width: grp.width
                            spacing: 2
                            Row {
                                spacing: Theme.gap
                                height: Theme.controlH
                                // The swatch: a button named by its role, hex and provenance; it opens the picker.
                                Rectangle {
                                    id: sw
                                    objectName: "palette-role:" + row.modelData
                                    width: 44; height: 26
                                    anchors.verticalCenter: parent.verticalCenter
                                    radius: Theme.rSm
                                    color: ed.colourOf(row.modelData)
                                    border.width: row.mine ? 2 : 1
                                    border.color: row.mine ? Theme.fg : Theme.outline
                                    activeFocusOnTab: true
                                    Accessible.role: Accessible.Button
                                    Accessible.name: I18n.fmt("palettes.editor.swatch_name", {
                                        role: ed.roleName(row.modelData), hex: ed.colourOf(row.modelData),
                                        state: I18n.tr(row.mine ? "palettes.editor.yours" : "palettes.editor.derived") })
                                    Keys.onReturnPressed: event => { ed.openPicker(row.modelData); event.accepted = true }
                                    Keys.onEnterPressed: event => { ed.openPicker(row.modelData); event.accepted = true }
                                    Keys.onSpacePressed: event => { ed.openPicker(row.modelData); event.accepted = true }
                                    // A derived colour is drawn hatched-free but dashed-looking: a second, inner ring.
                                    Rectangle {
                                        visible: !row.mine
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        radius: Math.max(0, parent.radius - 4)
                                        color: "transparent"
                                        border.width: 1
                                        border.color: Qt.alpha(Theme.fg, 0.5)
                                    }
                                    // The colour on screen, where a stage moved the one picked.
                                    Rectangle {
                                        visible: row.mv !== null
                                        objectName: "palette-shown:" + row.modelData
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: -4
                                        width: 14; height: 14; radius: 7
                                        color: row.mv ? row.mv.shown : "transparent"
                                        border.width: 1
                                        border.color: Theme.fg
                                    }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ed.openPicker(row.modelData) }
                                    FocusRing { anchors.fill: parent; shown: sw.activeFocus; corner: sw.radius }
                                }
                                Text {
                                    width: 130
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                                    antialiasing: !Theme.pixelType
                                    text: ed.roleName(row.modelData)
                                    color: Theme.fg
                                    font.pixelSize: Theme.fs
                                    font.family: Theme.fam(text, Theme.families)
                                }
                                Text {
                                    width: 76
                                    anchors.verticalCenter: parent.verticalCenter
                                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                                    antialiasing: !Theme.pixelType
                                    text: ed.colourOf(row.modelData)
                                    color: Theme.fg
                                    font.pixelSize: Theme.fs
                                    font.family: "monospace"
                                }
                                Text {
                                    objectName: "palette-provenance:" + row.modelData + ":" + (row.mine ? "yours" : "derived")
                                    anchors.verticalCenter: parent.verticalCenter
                                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                                    antialiasing: !Theme.pixelType
                                    text: I18n.tr(row.mine ? "palettes.editor.yours" : "palettes.editor.derived")
                                    color: Theme.dim
                                    font.pixelSize: Theme.fsCaption
                                    font.family: Theme.fam(text, Theme.families)
                                }
                                Button {
                                    visible: row.mine && !row.must
                                    objectName: "palette-derive:" + row.modelData
                                    anchors.verticalCenter: parent.verticalCenter
                                    label: I18n.tr("palettes.editor.derive")
                                    accessibleName: I18n.tr("palettes.editor.derive") + " " + ed.roleName(row.modelData)
                                    onClicked: ed.setRole(row.modelData, "")
                                }
                            }
                            // Shōjiki: the colour picked is not the one on screen, and why.
                            Text {
                                visible: row.mv !== null
                                objectName: "palette-moved:" + row.modelData
                                width: row.width
                                wrapMode: Text.Wrap
                                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                                antialiasing: !Theme.pixelType
                                text: row.mv ? I18n.fmt("palettes.editor.shown_as", { picked: row.mv.picked, shown: row.mv.shown, why: ed.whyText(row.mv) }) : ""
                                color: Theme.fg
                                font.pixelSize: Theme.fsCaption
                                font.family: Theme.fam(text, Theme.families)
                            }
                            Loader {
                                active: ed.picking === row.modelData
                                visible: active
                                sourceComponent: ColorPicker {
                                    role: ed.roleName(row.modelData)
                                    hex: ed.colourOf(row.modelData)
                                    swatches: (ed.listInfo && ed.listInfo.swatches) || ({ palette: [], wallpaper: [] })
                                    onMoved: h => ed.setRole(row.modelData, h)
                                    onAccepted: h => { ed.setRole(row.modelData, h); ed.closePicker(true) }
                                    onCancelled: ed.closePicker(false)
                                    Component.onCompleted: Qt.callLater(focusSquare)
                                }
                            }
                        }
                    }
                }
            }
        }
        // The sample: the side being edited as the shell draws it (which may not be the scheme in effect).
        Rectangle {
            id: sample
            objectName: "palette-sample"
            width: 230
            height: sampleCol.implicitHeight + Theme.pad * 2
            radius: Theme.rLg
            color: ed.shown("surface")
            border.width: 1
            border.color: ed.shown("outline")
            Accessible.role: Accessible.Grouping
            Accessible.name: I18n.tr("palettes.editor.sample")
            Column {
                id: sampleCol
                x: Theme.pad; y: Theme.pad
                width: parent.width - Theme.pad * 2
                spacing: Theme.gap
                Text {
                    objectName: "palette-sample-text:" + ed.shown("on_surface")
                    text: I18n.tr("palettes.editor.sample_text")
                    color: ed.shown("on_surface")
                    font.pixelSize: Theme.fs + 1
                    font.weight: Theme.wBold
                    font.family: Theme.fam(text, Theme.families)
                }
                Rectangle {
                    width: parent.width
                    height: 40
                    radius: Theme.rSm
                    color: ed.shown("surface_container")
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.gap
                        text: I18n.tr("palettes.editor.sample_quiet")
                        color: ed.shown("on_surface_variant")
                        font.pixelSize: Theme.fsCaption
                        font.family: Theme.fam(text, Theme.families)
                    }
                }
                Row {
                    spacing: Theme.gap
                    Rectangle {
                        objectName: "palette-sample-accent:" + ed.shown("accent")
                        width: btnText.implicitWidth + Theme.pad * 2
                        height: 30
                        radius: height / 2
                        color: ed.shown("accent")
                        Text {
                            id: btnText
                            anchors.centerIn: parent
                            text: I18n.tr("palettes.editor.sample_button")
                            color: ed.shown("on_accent")
                            font.pixelSize: Theme.fs
                            font.weight: Theme.wMedium
                            font.family: Theme.fam(text, Theme.families)
                        }
                    }
                    // A switch, on.
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40; height: 22; radius: 11
                        color: ed.shown("tertiary")
                        Rectangle { x: parent.width - width - 3; y: 3; width: 16; height: 16; radius: 8; color: ed.shown("on_tertiary") }
                    }
                }
                // A slider at two thirds.
                Item {
                    width: parent.width
                    height: 16
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 6; radius: 3; color: ed.shown("surface_container_highest") }
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.66; height: 6; radius: 3; color: ed.shown("secondary") }
                    Rectangle { x: parent.width * 0.66 - 8; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; radius: 8; color: ed.shown("secondary"); border.width: 2; border.color: ed.shown("surface") }
                }
                Row {
                    spacing: Theme.gap
                    Repeater {
                        model: ["error", "warning", "success"]
                        delegate: Rectangle {
                            required property string modelData
                            width: chip.implicitWidth + Theme.gap * 2
                            height: 22
                            radius: 11
                            color: ed.shown(modelData)
                            Text {
                                id: chip
                                anchors.centerIn: parent
                                text: ed.roleName(parent.modelData)
                                color: ed.shown("on_" + parent.modelData)
                                font.pixelSize: Theme.fsCaption
                                font.family: Theme.fam(text, Theme.families)
                            }
                        }
                    }
                }
            }
        }
    }

    // --- what the editor is doing, and Save -------------------------------------------------------------------------
    Text {
        visible: ed.loaded
        width: ed.width
        wrapMode: Text.Wrap
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        text: I18n.tr("palettes.editor.live")
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
    }
    Text {
        visible: ed.loaded && ed.hasTerminal
        width: ed.width
        wrapMode: Text.Wrap
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        text: I18n.tr("palettes.editor.terminal_kept")
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
    }
    Text {
        visible: ed.loaded && !ed.writable
        objectName: "palette-editor-read-only"
        width: ed.width
        wrapMode: Text.Wrap
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        text: I18n.fmt("palettes.editor.read_only", { dir: ed.dir })
        color: Theme.fg
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
    }
    Text {
        visible: ed.saveError !== ""
        width: ed.width
        wrapMode: Text.Wrap
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        text: ed.saveError
        color: Theme.error
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
    }
    Row {
        visible: ed.loaded
        spacing: Theme.gap
        Button {
            objectName: "palette-save"
            label: I18n.tr("palettes.editor.save")
            primary: true
            enabled: ed.writable && ed.fileName !== "" && !ed.inFlight
            onClicked: ed.save()
        }
        Button {
            objectName: "palette-cancel"
            label: I18n.tr("palettes.editor.cancel")
            onClicked: ed.cancel()
        }
    }
}
