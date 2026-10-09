pragma Singleton
import QtQuick
import Quickshell

// All user-facing strings go through tr(key); keys live in i18n/{en,ja}/frontend.toml.
// Strings come from the daemon's `i18n` document (shell.qml watches it); until it arrives, or for a
// key it lacks, the key itself is returned: never invent text the daemon does not own (rule 8).
Singleton {
    readonly property var strings: (Store.docs["i18n"] && Store.docs["i18n"].strings) || ({})
    function tr(key) { var s = strings[key]; return s === undefined ? key : s }
}
