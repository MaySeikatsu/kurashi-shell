import QtQuick
import "mods.js" as Mods

// A native mod's QML component (K26, K28), instantiated only while the view that places it is shown. The file
// comes from the `mods` document (the `qml` map of the entry that provides `provide`, of mod `mod` when set) or
// from `url` (a runtime.slots contribution, which wins). QML resolves imports relative to the importing file and
// refuses absolute paths, so a mod component cannot import the shell's singletons: the loader hands it the same
// objects as required properties `store`, `theme` and `i18n` (declare all three). Unloading is `source = ""`: a
// disabled mod's entry is gone from `mods`, so its component is destroyed, never kept stale. A file that fails to
// load logs once and shows nothing.
Loader {
    id: ml
    property string provide: ""     // "panel:x", "widget:x", "island-face:x", "island-face:x:expanded"
    property string mod: ""         // optional: the entry that must provide `provide`
    property string url: ""         // a file URL the caller holds (runtime.slots); wins over `provide`
    property bool shown: true       // the placing view's visibility gate (Ma): nothing is loaded while false

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
    onStatusChanged: if (status === Loader.Error) console.warn("ModLoader: cannot load " + source)
}
