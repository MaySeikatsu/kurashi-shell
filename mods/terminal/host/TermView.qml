import QtQuick
import Quickshell
import QMLTermWidget 2.0
import "core"
import "palette.js" as Pal

// One tab: its session (the pty and the user's shell) and the display that draws it (docs/ux/terminal.md). The session
// lives as long as the tab is in `mod.terminal.tabs`; the display draws only while its tab is the active one and the
// window is mapped. Its background is transparent: the shell's material under the window is the terminal's ground.
Item {
    id: view
    required property string tabId
    // Its entry in the document ({id, title, dir, …}); the delegate is keyed by id, so a title change never remakes it.
    property var tab: ({ id: tabId })
    property bool active: false
    property var settings: ({})
    property var report: null
    // Lines the daemon asks this tab to type (`runs` for this tab); each is sent once and acknowledged.
    property var runs: []
    readonly property alias term: term
    readonly property alias session: sess
    property bool started: false
    property var sent: ({})

    visible: active

    // The shell's environment without this process's own: the scope token (it must never reach a program the user runs),
    // the plugin's lookup paths and the wrapper's import path (docs/ux/terminal.md "Security").
    readonly property string shellPath: {
        var s = String(settings.shell || "")
        if (s === "") s = Quickshell.env("SHELL") || "/bin/sh"
        return s
    }
    readonly property var scrub: ["KURASHI_SCOPE_TOKEN", "KURASHI_SCOPE_MOD", "COLORSCHEMES_DIR", "KB_LAYOUT_DIR",
        "NIXPKGS_QT6_QML_IMPORT_PATH"]
    function envArgs() {
        var a = []
        for (var i = 0; i < scrub.length; i++) a.push("-u", scrub[i])
        // (a shell command with arguments, `fish -l`, is split on spaces: the setting is a command, not a script)
        return a.concat(shellPath.split(" ").filter(function (w) { return w !== "" }))
    }

    function paint() {
        term.setColors(Pal.colours(Theme))
        term.setBackgroundOpacity(0)
    }
    Connections {
        target: Theme
        function onTokensChanged() { view.paint() }
    }

    QMLTermWidget {
        id: term
        anchors.fill: parent
        font.family: String(view.settings.font || "") !== "" ? String(view.settings.font) : Theme.tok("font.family_mono", "monospace")
        font.pixelSize: Number(view.settings.font_size || 13)
        // (Ma: a blinking cursor is a timer; the cursor stands still)
        blinkingCursor: false
        session: QMLTermSession {
            id: sess
            initialWorkingDirectory: String(view.tab.dir || "")
            shellProgram: "env"
            shellProgramArgs: view.envArgs()
            onFinished: if (view.report) view.report("terminal.host.exited", { tab: view.tab.id })
            onTitleChanged: if (view.report) view.report("terminal.host.title", { tab: view.tab.id, title: String(sess.title || "") })
        }
        Component.onCompleted: {
            view.paint()
            sess.setHistorySize(Number(view.settings.scrollback || 10000))
            sess.startShellProgram()
            view.started = true
            view.sendRuns()
        }
    }

    // The tab's scrollbar: a thin rail in the look's text colour, there only while there is history.
    QMLTermScrollbar {
        terminal: term
        width: 6
        visible: term.scrollbarMaximum > 0
        Rectangle { anchors.fill: parent; radius: 3; color: Theme.fg; opacity: 0.35 }
    }

    onRunsChanged: sendRuns()
    function sendRuns() {
        if (!started) return
        for (var i = 0; i < runs.length; i++) {
            var r = runs[i]
            if (sent[r.id]) continue
            sent[r.id] = true
            sess.sendText(String(r.text) + "\r")
            if (report) report("terminal.host.ran", { run: r.id })
        }
    }
}
