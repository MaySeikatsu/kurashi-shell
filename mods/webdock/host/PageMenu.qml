import QtQuick
import QtWebEngine
import "core"
import "components"
import "components/menus/rows.js" as Rows

// A web page's right-click menu (W82, docs/ux/context-menus.md, target `page:<pin>`): the shell's menu — TrayMenu, its
// rows, marks, keys and look — drawn in the page's own window, because the request, the page's actions and the pointer
// live in this process. Rows from what the request offers: Back, Forward, Reload; a link's Open in browser and Copy link;
// an image's address; Cut / Copy / Paste / Select all as the engine allows them; Open page in browser. A page that handles
// `contextmenu` itself raises no request (its own menu wins, as in a browser). The menu holds the keyboard while it is
// open and gives it back to the page; a press outside it closes it and goes nowhere else. Ma: made only while open.
Item {
    id: pm
    property string pinId: ""
    property var report: null
    property bool debugLog: false
    // The open menu's view (the page, or its sign-in sheet) and what its request said; null while closed.
    property var view: null
    property var req: null
    readonly property bool open: req !== null
    visible: open
    // Test only (KURASHI_WEBDOCK_DEBUG=1, test-page-menu.sh): where the page stands in its window, and the window's size.
    property bool shownPage: false
    readonly property string boxLine: {
        if (!debugLog || !shownPage || width <= 0) return ""
        var w = Window.window, p = mapToItem(null, 0, 0)
        return [pinId, Math.round(p.x), Math.round(p.y), Math.round(width), Math.round(height),
                w ? w.width : 0, w ? w.height : 0].join(" ")
    }
    onBoxLineChanged: if (boxLine !== "") console.log("webdock-debug pagebox " + boxLine)

    // Opens the menu for `request` (a ContextMenuRequest of `v`): its data is copied now, the request is answered here.
    function show(v, request) {
        request.accepted = true
        var f = request.editFlags
        req = {
            x: request.position.x, y: request.position.y,
            link: String(request.linkUrl || ""), media: String(request.mediaUrl || ""),
            image: request.mediaType === ContextMenuRequest.MediaTypeImage,
            editable: request.isContentEditable === true, selected: String(request.selectedText || "") !== "",
            canCut: (f & ContextMenuRequest.CanCut) !== 0, canCopy: (f & ContextMenuRequest.CanCopy) !== 0,
            canPaste: (f & ContextMenuRequest.CanPaste) !== 0, canAll: (f & ContextMenuRequest.CanSelectAll) !== 0
        }
        view = v
        if (debugLog) console.log("webdock-debug menu " + pinId + " at " + Math.round(req.x) + "," + Math.round(req.y)
            + " link=" + (req.link !== "") + " image=" + req.image + " editable=" + req.editable + " rows="
            + JSON.stringify(tree.children.filter(function (e) { return !e.separator }).map(function (e) { return e.id })))
        Qt.callLater(function () { if (pm.open && body.item) body.item.forceActiveFocus() })
    }
    function close() {
        var v = view
        req = null
        view = null
        if (v) v.forceActiveFocus()
    }

    // TrayMenu's tree; ids stable per row (the test chooses by them).
    readonly property var tree: {
        var r = req, v = view, kids = []
        if (!r || !v) return { children: [] }
        kids.push({ id: 1, label: I18n.tr("menus.page.back"), enabled: v.canGoBack === true, act: { web: "back" } })
        kids.push({ id: 2, label: I18n.tr("menus.page.forward"), enabled: v.canGoForward === true, act: { web: "forward" } })
        kids.push({ id: 3, label: I18n.tr("menus.page.reload"), act: { web: "reload" } })
        if (r.link !== "") {
            kids.push({ id: 10, separator: true })
            kids.push({ id: 11, label: I18n.tr("menus.page.open_link"), enabled: web(r.link), act: { browser: r.link } })
            kids.push({ id: 12, label: I18n.tr("menus.page.copy_link"), act: { web: WebEngineView.CopyLinkToClipboard } })
        }
        if (r.image && r.media !== "") {
            kids.push({ id: 20, separator: true })
            kids.push({ id: 21, label: I18n.tr("menus.page.copy_image"), act: { web: WebEngineView.CopyImageUrlToClipboard } })
        }
        if (r.editable || r.selected) {
            kids.push({ id: 30, separator: true })
            if (r.editable) kids.push({ id: 31, label: I18n.tr("menus.page.cut"), enabled: r.canCut, act: { web: WebEngineView.Cut } })
            kids.push({ id: 32, label: I18n.tr("menus.page.copy"), enabled: r.canCopy || r.selected, act: { web: WebEngineView.Copy } })
            if (r.editable) kids.push({ id: 33, label: I18n.tr("menus.page.paste"), enabled: r.canPaste, act: { web: WebEngineView.Paste } })
            kids.push({ id: 34, label: I18n.tr("menus.page.select_all"), enabled: r.canAll || r.editable, act: { web: WebEngineView.SelectAll } })
        }
        kids.push({ id: 90, separator: true })
        kids.push({ id: 91, label: I18n.tr("menus.page.open_page"), enabled: web(String(v.url)), act: { browser: String(v.url) } })
        // (the browser takes web addresses only, K38: say so where a row above is grey for it — Shōjiki)
        if (!web(String(v.url)) || (r.link !== "" && !web(r.link)))
            kids.push({ id: 92, label: I18n.tr("menus.page.web_only"), enabled: false })
        return { children: kids }
    }
    // An address the system browser is handed (`webdock.open_external` refuses the rest: file pages, custom schemes).
    function web(u) { return /^https?:\/\//i.test(String(u)) }
    // Every row ends the menu (a page's action is one step, not a setting to tune).
    function choose(id) {
        var a = Rows.find(id, tree.children), v = view
        if (debugLog) console.log("webdock-debug menu " + pinId + " chose " + id)
        close()
        if (!a || !v) return
        if (a.browser !== undefined) { if (report) report("webdock.open_external", { url: a.browser }); return }
        if (a.web === "back") v.goBack()
        else if (a.web === "forward") v.goForward()
        else if (a.web === "reload") v.reload()
        else v.triggerWebAction(a.web)
    }

    // Made while open only: a kept page that shows no menu holds none of it.
    Loader {
        id: body
        anchors.fill: parent
        active: pm.open
        sourceComponent: Item {
            // (fades in on the look's quick step; with reduced motion that step is 0: no fade)
            opacity: 0
            Component.onCompleted: opacity = 1
            Behavior on opacity { NumberAnimation { duration: Theme.quickMs } }
            Keys.onPressed: event => {
                if (menu.handleKey(event.key)) { event.accepted = true; return }
                if (event.key === Qt.Key_Escape) pm.close()
                event.accepted = true   // (the page under it gets no key while the menu is open)
            }
            // A press outside the card closes it and reaches nothing under it.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: pm.close()
            }
            Rectangle {
                id: box
                readonly property real pad: Theme.pad
                width: Math.min(pm.width - 2 * Theme.xs, 280)
                height: Math.min(pm.height - 2 * Theme.xs, col.implicitHeight + 2 * pad)
                // At the pointer, turned left or up where the page ends; kept inside the page.
                x: !pm.req ? 0 : Math.max(Theme.xs, pm.req.x + width <= pm.width - Theme.xs ? pm.req.x
                    : (pm.req.x - width >= Theme.xs ? pm.req.x - width : pm.width - width - Theme.xs))
                y: !pm.req ? 0 : Math.max(Theme.xs, Math.min(pm.height - height - Theme.xs, pm.req.y))
                radius: Theme.rSm
                color: Theme.surface
                border.width: 1
                border.color: Theme.outline
                clip: true
                Accessible.role: Accessible.PopupMenu
                Accessible.name: title.text
                Column {
                    id: col
                    x: box.pad
                    y: box.pad
                    width: box.width - 2 * box.pad
                    spacing: Theme.gap
                    Text {
                        id: title
                        width: col.width
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.pixelSize: Theme.fsTitle
                        font.family: Theme.fam(text, Theme.families)
                        text: pm.view && String(pm.view.title || "") !== "" ? pm.view.title : I18n.tr("menus.page")
                    }
                    TrayMenu {
                        id: menu
                        width: col.width
                        tree: pm.tree
                        onChosen: item => pm.choose(item)
                    }
                }
            }
        }
    }
}
