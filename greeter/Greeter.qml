import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import "core"

// The greeter's state and its greetd conversation (W28, docs/ux/greeter.md). Views (one per output) render it and
// call submit/cancel/pick*/power; nothing here draws. No kurashid exists before login, so this is the one place in the
// tree that reads files and runs a command itself: /etc/passwd, the wayland-sessions folders, its own memory file, and
// `systemctl suspend|reboot|poweroff` on a key press (logind; the active greeter session may).
// Sources: DMS Modules/Greetd (GreetdMemory: last user and session; GreeterContent: session discovery from desktop
// files, the auth flow — the typed secret waits for greetd's first secret prompt, is answered and dropped).
// Test hooks (greeter/test.sh): KURASHI_GREETER_DIR, KURASHI_GREETER_PASSWD, KURASHI_GREETER_SESSIONS (`:`-separated),
// KURASHI_GREETER_POWER (the power command), KURASHI_GREETER_TIME (a fixed "HH:MM").
Item {
    id: g

    readonly property string dir: Quickshell.env("KURASHI_GREETER_DIR") || "/var/lib/kurashi-greeter"
    readonly property string passwdPath: Quickshell.env("KURASHI_GREETER_PASSWD") || "/etc/passwd"
    readonly property var sessionDirs: (Quickshell.env("KURASHI_GREETER_SESSIONS")
        || "/run/current-system/sw/share/wayland-sessions:/usr/local/share/wayland-sessions:/usr/share/wayland-sessions")
        .split(":").filter(function (d) { return d !== "" })
    readonly property string powerCmd: Quickshell.env("KURASHI_GREETER_POWER") || "systemctl"
    readonly property string fixedTime: Quickshell.env("KURASHI_GREETER_TIME") || ""

    // [{name, display, icon}] and [{id, name, exec, desktops}]
    property var users: []
    property var sessions: []
    property int userIndex: -1
    property int sessionIndex: -1
    readonly property var user: userIndex >= 0 && userIndex < users.length ? users[userIndex] : null
    readonly property var session: sessionIndex >= 0 && sessionIndex < sessions.length ? sessions[sessionIndex] : null
    property var memory: ({})
    property bool memoryRead: false

    // The lock surface's state shape (runtime.lock: busy, prompt, prompt_echo, message_key, pam_message), so the view
    // is LockContent unchanged. Always replaced, never mutated (bindings follow the object).
    property var lock: ({})
    property var clock: ({})
    property int failures: 0
    property bool launching: false

    // The secret typed before greetd asked for it: held only until the first secret prompt answers it (DMS's flow).
    property var stash: null
    property bool awaiting: false   // greetd asked and waits for a response

    function tr(k) { return I18n.tr(k) }
    function promptFor(u) { return u ? tr("greeter.prompt.password_for").replace("{user}", u.display) : "" }
    function setLock(o) { lock = Object.assign({ prompt_echo: false, busy: false }, o || {}) }
    // What the view gets: the user's prompt unless greetd asked something else (a binding, so it follows the strings).
    readonly property var viewLock: {
        var o = Object.assign({}, lock)
        if (o.prompt === undefined) o.prompt = promptFor(g.user)
        return o
    }
    function fail(key, arg) {
        stash = null
        awaiting = false
        launching = false
        // A message with a detail goes as text (LockContent fills no placeholders in message_key).
        if (arg) setLock({ pam_message: { text: tr(key).replace("{msg}", arg), kind: "error" } })
        else setLock({ message_key: key })
    }

    // ---- users -------------------------------------------------------------------------------------------------
    FileView {
        id: passwd
        path: g.passwdPath
        printErrors: false
        onLoaded: {
            var out = []
            var lines = text().split("\n")
            for (var i = 0; i < lines.length; i++) {
                var f = lines[i].split(":")
                if (f.length < 7) continue
                var uid = parseInt(f[2])
                if (!(uid >= 1000 && uid < 60000) || /(nologin|false)$/.test(f[6])) continue
                var gecos = (f[4] || "").split(",")[0]
                out.push({ name: f[0], display: gecos || f[0], icon: "/var/lib/AccountsService/icons/" + f[0] })
            }
            g.users = out
            g.pickInitial()
        }
    }

    // ---- sessions (desktop files) ------------------------------------------------------------------------------
    property var found: ({})   // desktop id → entry; the first folder that has an id wins
    function parseDesktop(text, path) {
        var id = path.substring(path.lastIndexOf("/") + 1).replace(/\.desktop$/, "")
        if (found[id] !== undefined) return
        var e = { id: id, name: "", exec: "", desktops: "" }
        var lines = text.split("\n"), inEntry = false, hidden = false
        for (var i = 0; i < lines.length; i++) {
            var l = lines[i].trim()
            if (l.charAt(0) === "[") { inEntry = l === "[Desktop Entry]"; continue }
            if (!inEntry) continue
            if (l.indexOf("Name=") === 0 && !e.name) e.name = l.substring(5)
            else if (l.indexOf("Exec=") === 0) e.exec = l.substring(5)
            else if (l.indexOf("DesktopNames=") === 0) e.desktops = l.substring(13).replace(/;$/, "").replace(/;/g, ":")
            else if (/^(Hidden|NoDisplay)=true$/.test(l)) hidden = true
        }
        var f = Object.assign({}, found)
        f[id] = hidden || !e.exec ? null : e
        found = f
        var list = []
        for (var k in found) if (found[k]) list.push(found[k])
        list.sort(function (a, b) { return a.name.localeCompare(b.name) })
        var keep = g.session ? g.session.id : ""
        g.sessions = list
        g.sessionIndex = indexOfSession(keep || (g.memory.session || ""))
        if (g.sessionIndex < 0 && list.length > 0) g.sessionIndex = 0
    }
    function indexOfSession(id) {
        for (var i = 0; i < sessions.length; i++) if (sessions[i].id === id) return i
        return -1
    }
    // `Exec=` → argv: field codes dropped, double quotes honoured (the desktop entry spec's quoting, simplified).
    function argv(exec) {
        var out = [], cur = "", q = false, any = false
        for (var i = 0; i < exec.length; i++) {
            var c = exec.charAt(i)
            if (c === "\\" && i + 1 < exec.length) { cur += exec.charAt(++i); any = true; continue }
            if (c === "\"") { q = !q; any = true; continue }
            if (!q && (c === " " || c === "\t")) { if (any) out.push(cur); cur = ""; any = false; continue }
            cur += c; any = true
        }
        if (any) out.push(cur)
        return out.filter(function (a) { return !/^%[a-zA-Z]$/.test(a) })
    }
    Repeater {
        model: g.sessionDirs
        delegate: Item {
            required property string modelData
            FolderListModel {
                id: folder
                folder: "file://" + modelData
                nameFilters: ["*.desktop"]
                showDirs: false
                onStatusChanged: {
                    if (status !== FolderListModel.Ready) return
                    for (var i = 0; i < count; i++) {
                        var p = get(i, "filePath").toString().replace(/^file:\/\//, "")
                        desktopFile.createObject(g, { path: p })
                    }
                }
            }
        }
    }
    Component {
        id: desktopFile
        FileView {
            id: fv
            printErrors: false
            onLoaded: { g.parseDesktop(text(), path); fv.destroy() }
            onLoadFailed: fv.destroy()
        }
    }

    // ---- memory (DMS GreetdMemory): the last user and session that started ---------------------------------------
    FileView {
        id: memFile
        path: g.dir + "/memory.json"
        printErrors: false
        blockWrites: true       // written right before launch: it must be on disk before the greeter quits
        atomicWrites: true
        onLoaded: {
            try { g.memory = JSON.parse(text()) || {} } catch (e) { g.memory = {} }
            g.memoryRead = true
            g.pickInitial()
        }
        onLoadFailed: { g.memoryRead = true; g.pickInitial() }
    }
    function pickInitial() {
        if (!memoryRead || users.length === 0 || userIndex >= 0) return
        var i = 0
        for (var k = 0; k < users.length; k++) if (users[k].name === memory.user) i = k
        userIndex = i
        var s = indexOfSession(memory.session || "")
        if (s >= 0) sessionIndex = s
    }
    function remember() {
        memFile.setText(JSON.stringify({ user: g.user ? g.user.name : "", session: g.session ? g.session.id : "" }) + "\n")
    }

    // ---- flow --------------------------------------------------------------------------------------------------
    onUserChanged: {
        if (Greetd.state !== GreetdState.Inactive && !launching) Greetd.cancelSession()
        stash = null
        awaiting = false
        failures = 0
        // An empty prompt for one turn clears what was typed for the previous user (LockContent clears on a change).
        lock = { prompt: "" }
        Qt.callLater(function () { g.setLock(Greetd.available ? {} : { message_key: "greeter.error.no_greetd" }) })
    }
    function pickUser(i) { if (i >= 0 && i < users.length && !launching) userIndex = i }
    function pickSession(i) { if (i >= 0 && i < sessions.length && !launching) sessionIndex = i }

    function submit(secret) {
        if (launching || !g.user) return
        if (!Greetd.available) { fail("greeter.error.no_greetd"); return }
        if (!g.session) { fail("greeter.error.no_session"); return }
        setLock({ busy: true })
        if (awaiting) {
            awaiting = false
            Greetd.respond(secret)
        } else if (Greetd.state === GreetdState.Inactive) {
            stash = secret
            Greetd.createSession(g.user.name)
        }
    }
    function cancel() {
        if (launching) return
        stash = null
        awaiting = false
        if (Greetd.state !== GreetdState.Inactive) Greetd.cancelSession()
        setLock({})
    }

    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) {
                if (g.stash !== null && !echoResponse) {
                    var s = g.stash
                    g.stash = null
                    Greetd.respond(s)
                    s = ""
                    return
                }
                // A further question (a one-time code, a visible prompt): ask it in the field.
                g.awaiting = true
                var p = message.replace(/[:\s]+$/, "")
                g.setLock(p ? { prompt: p, prompt_echo: echoResponse } : { prompt_echo: echoResponse })
                return
            }
            // Info and error lines from PAM (Quickshell answers them itself).
            g.setLock({ busy: g.lock.busy === true, pam_message: { text: message, kind: error ? "error" : "info" } })
        }
        function onAuthFailure(message) {
            g.failures++
            g.fail("greeter.error.auth")
            Greetd.cancelSession()
        }
        function onError(error) {
            g.fail("greeter.error.greetd", error)
            Greetd.cancelSession()
        }
        function onReadyToLaunch() {
            g.stash = null
            g.launching = true
            var name = g.session ? g.session.name : ""
            g.setLock({ busy: true, pam_message: { text: g.tr("greeter.starting").replace("{session}", name), kind: "info" } })
            g.remember()
            var env = ["XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=" + g.session.id]
            if (g.session.desktops) env.push("XDG_CURRENT_DESKTOP=" + g.session.desktops)
            Greetd.launch(g.argv(g.session.exec), env)
        }
    }

    // ---- power keys --------------------------------------------------------------------------------------------
    property string powerVerb: ""
    Process {
        id: power
        onExited: function (code) {
            if (code !== 0) g.fail("greeter.power.failed", g.tr("greeter.power." + g.powerVerb))
        }
    }
    function powerAction(verb) {
        if (launching || power.running) return
        powerVerb = verb
        power.command = [powerCmd, verb]
        power.running = true
    }

    // ---- clock: one tick a minute, on the minute ---------------------------------------------------------------
    function tick() {
        var d = new Date()
        var hh = ("0" + d.getHours()).slice(-2), mm = ("0" + d.getMinutes()).slice(-2)
        if (fixedTime !== "") { hh = fixedTime.substring(0, 2); mm = fixedTime.substring(3, 5) }
        var iso = d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" + ("0" + d.getDate()).slice(-2)
        clock = { hh: hh, mm: mm, date: iso }
        minute.interval = Math.max(1000, 60000 - (d.getSeconds() * 1000 + d.getMilliseconds()))
        minute.restart()
    }
    Timer { id: minute; repeat: false; onTriggered: g.tick() }

    Component.onCompleted: {
        tick()
        setLock(Greetd.available ? {} : { message_key: "greeter.error.no_greetd" })
    }
}
