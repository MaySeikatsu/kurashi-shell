import QtQuick
import "mods.js" as Mods

// A native mod's QML component (K26, K28), instantiated only while the view that places it is shown. The file
// comes from the `mods` document (the `qml` map of the entry that provides `provide`, of mod `mod` when set) or
// from `url` (a runtime.slots contribution, which wins). Mod files load from `file://` URLs, the shell from `qs:@/qs/`:
// a relative import of `frontend/core` from a mod would create a *second*, disconnected Store/Theme/I18n. Mods import
// the shell by module URI instead (`import qs.core`, `import qs.components` — the same singletons wherever the mod
// lives), and the loader also hands the objects in as `store`, `theme`, `i18n` (declare them; required). Unloading is
// `source = ""`: a disabled mod's entry is gone from `mods`, so its component is destroyed, never kept stale. A file
// that fails to load logs once and shows nothing.
Loader {
    id: ml
    property string provide: ""     // "panel:x", "widget:x", "island-face:x", "island-face:x:expanded"
    property string mod: ""         // optional: the entry that must provide `provide`
    property string url: ""         // a file URL the caller holds (runtime.slots); wins over `provide`
    property bool shown: true       // the placing view's visibility gate (Ma): nothing is loaded while false
    // Values for the loaded component's own properties (W19: `date` of a day mark, row 71; `reason` of a contribution
    // that needs setup, row 72). They are set on each load and whenever they change, and only on a property the
    // component declares: a name it does not declare reads undefined and is skipped, so nothing warns.
    property var extra: ({})

    // Store.docs changes on every document update; this value changes only when `mods` does.
    readonly property var modsDoc: Store.docs["mods"]
    readonly property string resolved: url !== "" ? url
        : (provide !== "" ? Mods.qmlOf(modsDoc, provide, mod) : "")

    onResolvedChanged: refresh()
    onShownChanged: refresh()
    Component.onCompleted: refresh()

    function refresh() {
        var want = shown ? resolved : ""
        if (want === String(source)) return
        if (want === "") { source = ""; return }
        setSource(want, { store: Store, theme: Theme, i18n: I18n })
    }
    // W19: the `extra` values on the component now loaded. An undefined value is not set (it would undo a binding the
    // component keeps on that property).
    function applyExtra() {
        var it = ml.item
        if (!it) return
        for (var k in ml.extra) {
            if (it[k] !== undefined && ml.extra[k] !== undefined) it[k] = ml.extra[k]
        }
    }
    onExtraChanged: applyExtra()
    onItemChanged: applyExtra()
    onStatusChanged: if (status === Loader.Error) console.warn("ModLoader: cannot load " + source)
}
