import QtQuick

// Declarative document subscription: lives exactly as long as its owner is alive and `active`.
// `Watch { doc: "svc.media" }` -> Store.watch on creation, Store.unwatch on destruction.
QtObject {
    id: w
    property string doc: ""
    property bool active: true
    property string _held: ""

    function sync() {
        var want = (active && doc !== "") ? doc : ""
        if (want === _held) return
        if (_held !== "") Store.unwatch(_held)
        _held = want
        if (want !== "") Store.watch(want)
    }
    onDocChanged: sync()
    onActiveChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: { active = false; sync() }
}
