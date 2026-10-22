import QtQuick

// W34: registers a bar widget as an origin a Stage panel grows out of (IslandGeom's registry, see there). Declared inside
// the widget: `AnchorReport { target: <the widget>; key: "quick"; output: <its bar's output> }`. Only on a top or bottom
// bar (`enabled`); registers on a change of key, output or enabled, and leaves on destruction. Nothing per frame (Ma).
QtObject {
    id: ar
    property Item target: null
    property string key: ""
    property string output: ""
    property bool enabled: true
    property string _key: ""
    property string _out: ""
    function sync() {
        if (_key !== "" && (_key !== key || _out !== output || !enabled)) { IslandGeom.unregister(_out, _key, ar); _key = "" }
        if (enabled && key !== "" && output !== "" && target) {
            IslandGeom.register(output, key, target, ar)
            _key = key
            _out = output
        }
    }
    onKeyChanged: sync()
    onOutputChanged: sync()
    onEnabledChanged: sync()
    onTargetChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: if (_key !== "") IslandGeom.unregister(_out, _key, ar)
}
