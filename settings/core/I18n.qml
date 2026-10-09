pragma Singleton
import QtQuick
import Quickshell

// Strings come from the daemon's `i18n` document (the app never reads i18n/*.toml, PROTOCOL §5).
// A key the daemon does not know is returned as-is: never invent text it does not own (rule 8).
Singleton {
    readonly property var strings: (Store.i18n && Store.i18n.strings) ? Store.i18n.strings : ({})
    function tr(key) { var s = strings[key]; return s === undefined ? key : s }
    function has(key) { return strings[key] !== undefined }
    // "Only applies while {key} is {value}." with a map of replacements.
    function fmt(key, vars) {
        var s = tr(key)
        for (var k in vars) s = s.split("{" + k + "}").join(String(vars[k]))
        return s
    }
}
