pragma Singleton
import QtQuick
import Quickshell

// All user-facing strings go through tr(key); keys live in i18n/{en,ja}/frontend.toml.
// The daemon does not serve strings yet (CONTRACT-CHANGE row requests an `i18n` document), so
// until then the key itself is returned: never invent text the daemon does not own (rule 8).
Singleton {
    property var strings: ({})
    function tr(key) { var s = strings[key]; return s === undefined ? key : s }
}
