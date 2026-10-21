import QtQuick
import Quickshell
import Quickshell.Io
import "core"

// The greeter's Theme reader (W28). No kurashid runs before login, so this plays the daemon's part for the shared
// frontend singletons: it reads the chosen user's cached look (`<dir>/<user>.json`, written by kurashid's
// greeter_cache.rs) and the greeter's strings (`i18n/<locale>/{lockui,greeter}.toml`, English under the locale), and
// puts them into `Store.docs["theme"]` and `Store.docs["i18n"]`, the documents `Theme` and `I18n` read. Every component
// of frontend/components then draws the user's look unchanged (rule 4: tokens only). A user with no cache gets the
// default tokens (Theme's fallbacks). Reads happen on a user change only (Ma).
Item {
    id: gt

    property string dir: ""
    property string user: ""
    // The user's cached locale wins; else the greeter's own environment.
    readonly property string envLocale: {
        var raw = Quickshell.env("LC_ALL") || Quickshell.env("LC_MESSAGES") || Quickshell.env("LANG") || ""
        var l = raw.split(/[_.@]/)[0].toLowerCase()
        return (l === "" || l === "c" || l === "posix") ? "en" : l
    }
    property var cache: ({})
    readonly property string locale: cache.locale || envLocale
    readonly property string wallpaper: cache.wallpaper || ""
    readonly property string dataDir: Quickshell.env("KURASHI_DATA_DIR")
        || decodeURIComponent(Qt.resolvedUrl("..").toString().replace(/^file:\/\//, "")).replace(/\/$/, "")

    // `"key" = "text"` lines of a flat i18n file (the only shape i18n/ uses); the text is a TOML basic string, which
    // JSON reads the same for the escapes these files use.
    function parseToml(text, into) {
        var lines = (text || "").split("\n")
        var re = /^\s*"?([A-Za-z0-9_.\-]+)"?\s*=\s*("(?:[^"\\]|\\.)*")\s*(?:#.*)?$/
        for (var i = 0; i < lines.length; i++) {
            var m = re.exec(lines[i])
            if (!m) continue
            try { into[m[1]] = JSON.parse(m[2]) } catch (e) {}
        }
    }
    function publishStrings() {
        var s = {}
        parseToml(enLock.text(), s)
        parseToml(enGreeter.text(), s)
        if (gt.locale !== "en") {
            parseToml(locLock.text(), s)
            parseToml(locGreeter.text(), s)
        }
        Store.setDoc("i18n", { locale: gt.locale, fallback: "en", strings: s })
    }
    function publishTheme() {
        Store.setDoc("theme", { tokens: gt.cache.tokens || {} })
    }

    onUserChanged: userFile.reload()
    onLocaleChanged: Qt.callLater(publishStrings)

    FileView {
        id: userFile
        path: gt.dir !== "" && gt.user !== "" ? gt.dir + "/" + gt.user + ".json" : ""
        printErrors: false
        watchChanges: false
        onLoaded: {
            try { gt.cache = JSON.parse(text()) || {} } catch (e) { gt.cache = {} }
            gt.publishTheme()
        }
        onLoadFailed: { gt.cache = {}; gt.publishTheme() }
    }
    FileView { id: enLock; path: gt.dataDir + "/i18n/en/lockui.toml"; blockLoading: true; printErrors: false }
    FileView { id: enGreeter; path: gt.dataDir + "/i18n/en/greeter.toml"; blockLoading: true; printErrors: false }
    FileView { id: locLock; path: gt.dataDir + "/i18n/" + gt.locale + "/lockui.toml"; blockLoading: true; printErrors: false }
    FileView { id: locGreeter; path: gt.dataDir + "/i18n/" + gt.locale + "/greeter.toml"; blockLoading: true; printErrors: false }

    Component.onCompleted: {
        publishTheme()
        publishStrings()
    }
}
