import QtQuick
import "../../core"
import "../../core/mods.js" as Mods
import ".."
import "appearance.js" as A

// The appearance menu (W84, docs/ux/appearance-menu.md): an icon rail on the left (Wallpaper, Colours, Style, Material,
// Motion, Effects, Fonts) and the chosen pane on the right — the live preview on top (a section the user can switch
// off), the pane's rows under it, the keep bar at its foot while something is previewed. One component for both hosts:
// the launcher (`host: "launcher"`, its card turns into the menu) and the Stage (`host: "card"`, panel `appearance:<pane>`).
// A view: the rows are the schema's (`appearance = "<pane>"`), the values the config document's, every change one step
// of the preview session (Enter keeps, Esc puts back — and so does every way out but Keep, on destruction).
// Ma: made only while its host shows it; `theme.previews` is watched only by the panes that draw tiles, the wallpaper
// mod's picker exists only on the Wallpaper pane.
FocusScope {
    id: am
    property string pane: "wallpaper"
    property string host: "launcher"
    property string output: ""            // the output it was asked on (the picture's target, the preview's picture)
    property string note: ""              // one line over the pane (the host's: "opened here instead")
    // The Stage card's width (W53.5 `cardWant`); the launcher sizes its own card.
    readonly property int cardWant: host === "card" ? 760 : 0
    signal back()                         // Esc with nothing to put back (the launcher goes back to its search)

    implicitWidth: 712
    implicitHeight: 540
    Accessible.role: Accessible.Pane
    Accessible.name: I18n.tr("appearance-menu.title")

    Watch { doc: "schema.settings" }
    Watch { doc: "mods" }
    Watch { doc: "mod.wallpaper"; active: am.wallpaperMod }
    Watch { doc: "theme.previews"; active: am.shownPane === "colours" || am.shownPane === "style" }
    readonly property var schema: Store.docs["schema.settings"] || null
    readonly property var previews: Store.docs["theme.previews"] || null
    readonly property var modsDoc: Store.docs["mods"]
    readonly property string pickerUrl: {
        var u = Mods.qmlOf(modsDoc, "panel:wallpaper", "wallpaper")
        return u !== "" ? u.replace(/Panel\.qml$/, "Picker.qml") : ""
    }
    readonly property bool wallpaperMod: pickerUrl !== ""
    readonly property var wallDoc: Store.docs["mod.wallpaper"] || ({})
    // The picture on the asked output (else the first one's): the preview's ground outside the Wallpaper pane.
    readonly property string currentPicture: {
        var outs = wallDoc.outputs || {}
        if (output !== "" && outs[output] && outs[output].path) return outs[output].path
        var names = Object.keys(outs).sort()
        for (var i = 0; i < names.length; i++) if (outs[names[i]].path) return outs[names[i]].path
        return ""
    }
    readonly property bool previewOn: {
        var v = previewSession.config.values ? previewSession.config.values["launcher.appearance_preview"] : undefined
        return !v || v.value !== false
    }
    function setPreview(on) { Store.apply([{ set: "launcher.appearance_preview", value: on }], null) }

    // (it puts back what was not kept when the menu goes, whichever way: its own onDestruction)
    PreviewSession { id: previewSession }

    // ---- panes ---------------------------------------------------------------------------------------------------
    // `shownPane` follows `pane` through the change's fade (the old pane out, the new one in).
    property string shownPane: pane
    readonly property int paneIndex: A.indexOf(pane)
    onPaneChanged: {
        if (pane === shownPane) return
        if (!Theme.springOn || Theme.quickMs <= 0) { shownPane = pane; return }
        paneSwap.restart()
    }
    SequentialAnimation {
        id: paneSwap
        NumberAnimation { target: body; property: "opacity"; to: 0; duration: Theme.quickMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.continuousCurve }
        ScriptAction { script: { am.shownPane = am.pane; paneFlick.contentY = 0; body.y = 8 } }
        ParallelAnimation {
            NumberAnimation { target: body; property: "opacity"; to: 1; duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
            NumberAnimation { target: body; property: "y"; to: 0; duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
        }
    }
    readonly property var rows: A.rowsOf(schema, shownPane)
    function pendingIn(p) {
        var rs = A.rowsOf(schema, p)
        for (var i = 0; i < rs.length; i++) if (previewSession.has(rs[i].key)) return true
        return false
    }
    function choose(i) {
        if (i < 0 || i >= A.panes.length) return
        pane = A.panes[i].id
    }
    // "More in Settings…": the page that holds the pane's rows (the mod's page for pictures). What is previewed is kept —
    // Settings shows it next — and the host closes first (Settings is a window of its own).
    function openSettings(key) {
        previewSession.keep()
        var args = key ? { key: key } : (shownPane === "wallpaper" && wallpaperMod ? { page: "mod:wallpaper" }
            : (rows.length > 0 ? { key: rows[0].key } : { page: "appearance" }))
        Store.act("ui.close", {}, function () { Store.act("settings.open", args) })
    }
    function enterPane() {
        var first = paneCol.nextItemInFocusChain(true)
        if (first && first !== rail) first.forceActiveFocus()
    }
    function focusRail() { rail.forceActiveFocus() }
    Component.onCompleted: Qt.callLater(focusRail)

    Keys.onPressed: event => {
        var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
        if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_7) {
            choose(event.key - Qt.Key_1)
            focusRail()
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            if (previewSession.active || previewSession.busy) { previewSession.putBack(); event.accepted = true }
            else if (host === "launcher") { back(); event.accepted = true }
            else event.accepted = false     // the Stage closes the card
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (previewSession.active) { previewSession.keep(); event.accepted = true }
        } else if ((event.key === Qt.Key_Down || event.key === Qt.Key_Up) && !rail.activeFocus) {
            // In the pane, Up/Down a control does not use go from row to row, as Tab and Shift+Tab do.
            var it = am.Window.window ? am.Window.window.activeFocusItem : null
            var next = it ? it.nextItemInFocusChain(event.key === Qt.Key_Down) : null
            if (next && next !== rail && !isAncestor(rail, next)) next.forceActiveFocus()
            event.accepted = true
        }
    }
    function isAncestor(a, b) {
        for (var p = b; p; p = p.parent) if (p === a) return true
        return false
    }
    // The control with the keyboard stays in view (the keep bar coming up shortens the pane).
    function revealFocus() {
        var it = am.Window.window ? am.Window.window.activeFocusItem : null
        if (!it || !it.mapToItem || !isAncestor(paneCol, it)) return
        var p = it.mapToItem(paneCol, 0, 0)
        if (p.y < paneFlick.contentY) paneFlick.contentY = Math.max(0, p.y - 8)
        else if (p.y + it.height > paneFlick.contentY + paneFlick.height)
            paneFlick.contentY = Math.min(Math.max(0, paneFlick.contentHeight - paneFlick.height), p.y + it.height - paneFlick.height + 8)
    }

    // ---- the rail ------------------------------------------------------------------------------------------------
    FocusScope {
        id: rail
        x: 0
        y: 0
        width: 76
        height: railCol.implicitHeight
        activeFocusOnTab: true
        Accessible.role: Accessible.PageTabList
        Accessible.name: I18n.tr("appearance-menu.title")
        Keys.onUpPressed: am.choose(Math.max(0, am.paneIndex - 1))
        Keys.onDownPressed: am.choose(Math.min(A.panes.length - 1, am.paneIndex + 1))
        Keys.onRightPressed: am.enterPane()
        // the highlight springs to the chosen entry
        Rectangle {
            id: railHi
            width: rail.width
            height: 58
            radius: Theme.rSm + 4
            color: Theme.selected
            y: am.paneIndex >= 0 ? am.paneIndex * (58 + railCol.spacing) : 0
            Behavior on y {
                enabled: Theme.springOn
                NumberAnimation { duration: Theme.stdMs; easing.type: Easing.OutBack; easing.overshoot: Theme.overshoot * 0.6 }
            }
            FocusRing { anchors.fill: parent; corner: parent.radius; shown: rail.activeFocus }
        }
        Column {
            id: railCol
            width: rail.width
            spacing: 4
            Repeater {
                model: A.panes
                delegate: Item {
                    id: entry
                    required property var modelData
                    required property int index
                    readonly property bool on: am.paneIndex === index
                    width: rail.width
                    height: 58
                    Accessible.role: Accessible.PageTab
                    Accessible.name: I18n.tr("appearance-menu.pane." + modelData.id)
                    Accessible.selected: on
                    Column {
                        anchors.centerIn: parent
                        spacing: 3
                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: entry.modelData.icon
                            glyph: entry.modelData.glyph
                            filled: entry.on
                            size: 20
                            color: entry.on ? Theme.fgOnSelected : Theme.dim
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: rail.width - 6
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            color: entry.on ? Theme.fgOnSelected : Theme.dim
                            font.pixelSize: Theme.fsCaption
                            font.weight: entry.on ? Theme.wBold : Theme.wRegular
                            font.family: Theme.fam(text, Theme.families)
                            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                            text: I18n.tr("appearance-menu.pane." + entry.modelData.id)
                        }
                    }
                    // a pane with a change not kept yet
                    Rectangle {
                        visible: am.pendingIn(entry.modelData.id)
                        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 8
                        width: 7; height: 7; radius: 3.5
                        color: Theme.accent
                    }
                    HoverHandler { id: railHover; cursorShape: Qt.PointingHandCursor }
                    Rectangle { anchors.fill: parent; radius: Theme.rSm + 4; color: Theme.fg; opacity: railHover.hovered && !entry.on ? 0.06 : 0 }
                    TapHandler { onTapped: { am.choose(entry.index); am.focusRail() } }
                }
            }
        }
    }
    // a hairline between the rail and the pane
    Rectangle {
        x: rail.width + Theme.gap
        y: 0
        width: 1
        height: am.height
        color: Theme.outline
        opacity: 0.5
    }

    // ---- the pane ------------------------------------------------------------------------------------------------
    Item {
        id: paneArea
        x: rail.width + 2 * Theme.gap + 1
        width: am.width - x
        height: am.height

        // the heading: the pane's name, "Show preview" while the preview is off, "More in Settings…"
        Item {
            id: head
            width: parent.width
            height: Theme.controlH
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fg
                font.pixelSize: Theme.fsTitle
                font.weight: Theme.wBold
                font.family: Theme.fam(text, Theme.families)
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                text: I18n.tr("appearance-menu.pane." + am.shownPane)
                TextFx { title: true }
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.xs
                IconButton {
                    visible: !am.previewOn
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "preview"
                    glyph: "◫"
                    a11y: I18n.tr("appearance-menu.preview.show")
                    onClicked: am.setPreview(true)
                }
                Button {
                    objectName: "appearance-more"
                    anchors.verticalCenter: parent.verticalCenter
                    label: I18n.tr("appearance-menu.more")
                    icon: "open_in_new"
                    onClicked: am.openSettings("")
                }
            }
        }
        Text {
            id: noteLine
            visible: am.note !== ""
            y: head.height + Theme.xs
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            text: am.note
        }
        MiniDesk {
            id: desk
            visible: am.previewOn
            y: (noteLine.visible ? noteLine.y + noteLine.height : head.height) + Theme.gap
            width: parent.width
            height: visible ? implicitHeight : 0
            picture: am.shownPane === "wallpaper" && wallLoader.item && wallLoader.item.previewPath
                ? wallLoader.item.previewPath : am.currentPicture
            roles: am.shownPane === "wallpaper" && wallLoader.item ? wallLoader.item.previewRoles : null
            caption: I18n.tr(am.shownPane === "wallpaper" ? "appearance-menu.preview.caption.picture"
                : "appearance-menu.preview.caption")
            onHideRequested: am.setPreview(false)
        }

        Flickable {
            id: paneFlick
            y: (desk.visible ? desk.y + desk.height : (noteLine.visible ? noteLine.y + noteLine.height : head.height)) + Theme.gap
            width: parent.width
            height: keepBar.y - y - Theme.gap
            contentHeight: body.height + 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            KineticWheel { view: paneFlick }
            // keep the focused row in view
            Connections {
                target: am.Window.window
                function onActiveFocusItemChanged() { am.revealFocus() }
            }
            onHeightChanged: Qt.callLater(am.revealFocus)
            Item {
                id: body
                width: paneFlick.width - 10
                height: paneCol.implicitHeight
                Column {
                    id: paneCol
                    width: parent.width
                    spacing: Theme.pad + 2

                    // the pictures: the wallpaper mod's compact picker, beside its own panel
                    ModLoader {
                        id: wallLoader
                        width: paneCol.width
                        visible: am.shownPane === "wallpaper" && am.wallpaperMod
                        shown: visible
                        url: am.pickerUrl
                        extra: ({ menu: am, output: am.output })
                        height: item ? item.implicitHeight : 0
                    }
                    // without the mod: what it would bring, and a way to turn it on
                    Column {
                        visible: am.shownPane === "wallpaper" && !am.wallpaperMod
                        width: paneCol.width
                        spacing: Theme.gap
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            color: Theme.fg
                            font.pixelSize: Theme.fs
                            font.weight: Theme.wMedium
                            font.family: Theme.fam(text, Theme.families)
                            text: I18n.tr("appearance-menu.wallpaper.no_mod")
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            color: Theme.dim
                            font.pixelSize: Theme.fsCaption
                            font.family: Theme.fam(text, Theme.families)
                            text: I18n.tr("appearance-menu.wallpaper.no_mod.hint")
                        }
                        Button {
                            objectName: "appearance-enable-wallpaper"
                            label: I18n.tr("appearance-menu.wallpaper.enable")
                            icon: "wallpaper"
                            onClicked: {
                                var known = (am.modsDoc && am.modsDoc.mods || []).some(function (m) { return m.id === "wallpaper" })
                                if (known) Store.act("mod.enable", { id: "wallpaper" })
                                else Store.act("mod.load", { id: "wallpaper" }, function () { Store.act("mod.enable", { id: "wallpaper" }) })
                            }
                        }
                    }
                    Repeater {
                        model: am.rows
                        delegate: SchemaRow {
                            required property var modelData
                            row: modelData
                            session: previewSession
                            schema: am.schema
                            previews: am.previews
                            width: paneCol.width
                            onWantsSettings: k => am.openSettings(k)
                        }
                    }
                    // a pane the daemon has not described yet
                    Text {
                        visible: am.schema === null
                        color: Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.tr("appearance-menu.loading")
                    }
                }
            }
        }
        ScrollEdge { view: paneFlick }

        // the keep bar: only while something is previewed
        Item {
            id: keepBar
            width: parent.width
            height: previewSession.active ? Theme.controlH + Theme.shadowDy + 2 : 0
            y: parent.height - height
            clip: true
            Behavior on height { enabled: Theme.springOn; NumberAnimation { duration: Theme.quickMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.continuousCurve } }
            Rectangle { width: parent.width; height: 1; color: Theme.outline; opacity: 0.5 }
            Text {
                anchors.left: parent.left
                anchors.right: keepButtons.left
                anchors.rightMargin: Theme.gap
                anchors.verticalCenter: keepButtons.verticalCenter
                elide: Text.ElideRight
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                text: I18n.tr(previewSession.count === 1 ? "appearance-menu.keep.one" : "appearance-menu.keep.many")
                    .replace("{n}", previewSession.count)
            }
            Row {
                id: keepButtons
                anchors.right: parent.right
                y: 4
                spacing: Theme.xs
                Button {
                    objectName: "appearance-putback"
                    label: I18n.tr("appearance-menu.putback")
                    onClicked: previewSession.putBack()
                }
                Button {
                    objectName: "appearance-keep"
                    primary: true
                    label: I18n.tr("appearance-menu.keep")
                    onClicked: previewSession.keep()
                }
            }
        }
    }
}
