import QtQuick
import Quickshell
import "../../core"
import "rows.js" as Rows

// The desktop's right-click menu (W82, docs/ux/context-menus.md "Rows per place"): the rows the enabled mods declare for
// it (K154: `[[menu]] at = "desktop"` — the wallpaper's, today), dark mode, the desktop page's own settings from the schema (rule 3: the page the schema puts them on, no list of
// keys here), and the way on to Settings. A pure view, as ModuleMenu: TrayMenu draws `tree`, `choose` runs a row. Ma: the
// documents are watched only while the menu is open.
Scope {
    id: dm
    // `desktop` or `desktop:<output>` while this menu is open, else "".
    property string target: ""
    // BarConfig of the output the menu is on (the value in effect there).
    property var bars: null
    readonly property bool active: target === "desktop" || target.indexOf("desktop:") === 0
    readonly property string output: bars ? bars.outName : ""

    Watch { doc: "schema.settings"; active: dm.active }
    Watch { doc: "theme"; active: dm.active }
    Watch { doc: "mods"; active: dm.active }
    readonly property var schema: active ? Store.docs["schema.settings"] : null
    // What the enabled mods put on the desktop's menu (rows of a mod that is off are not offered).
    readonly property var modRows: active ? Rows.modRows(Store.docs["mods"], "desktop", "", { output: output }, 800100, I18n.tr) : []
    // The scheme in effect (a mode may follow the system or the wallpaper), as the darkmode module reads it.
    readonly property bool dark: {
        var ap = active ? ((Store.docs["theme"] || {}).appearance || {}) : {}
        return String(ap.scheme_effective || ap.scheme || "") === "dark"
    }
    readonly property var rows: Rows.rowsWhere(schema, function (p) { return p.id === "desktop" }, false)
    readonly property string title: I18n.tr("menus.desktop")

    readonly property var tree: {
        var kids = []
        if (modRows.length > 0) {
            kids = kids.concat(modRows)
            kids.push({ id: 800003, separator: true })
        }
        kids.push({ id: 800010, label: I18n.tr("menus.desktop.dark"), toggle: "checkmark", checked: dark,
                    act: { key: "theme.colors.scheme", value: dark ? "light" : "dark" } })
        kids.push({ id: 800011, separator: true })
        if (schema) kids = kids.concat(Rows.entries(schema, rows, bars, 1, I18n.tr))
        kids.push({ id: 800020, separator: true })
        kids.push({ id: 800021, label: I18n.tr("menus.desktop.settings"), act: { open: { page: "desktop" } } })
        kids.push({ id: 800022, label: I18n.tr("menus.desktop.appearance"), act: { open: { page: "appearance" } } })
        return { children: kids }
    }
    function choose(id) { return Rows.run(Store, bars, Rows.find(id, tree.children)) }
}
