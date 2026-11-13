import QtQuick
import "../../core"
import "appearance.js" as A

// The appearance menu's live preview (docs/ux/appearance-menu.md "Preview session"): Settings' Changes.qml ported to the
// shell's Store, for several keys at once. Every key changed in one visit is held here; each change takes back the
// session's last transaction (`undo`, only while no one committed since — the config document's `history.rev`) and
// applies the whole set as one `apply`, so the visit is one undo step. keep() leaves it in effect; putBack() takes it
// back — by undo, or by setting the starting values again (`set` for the user's own, `reset` otherwise) when another
// change came in between. The owner calls putBack() on every way out but keep (Esc, a close, its own destruction).
//
// The shell's Store answers an apply with null or errors only (no `rev`), and the daemon sends a reply before the
// patches it queued (server.rs: replies are biased first), so the transaction's revision is read from the config
// document once the patch with the session's values has arrived. Unknown after 2 s: the next step stacks instead of
// undoing, and putBack sets the starting values — never an undo of someone else's change.
Item {
    id: ps
    visible: false
    Watch { doc: "config" }
    readonly property var config: Store.docs["config"] || ({})
    readonly property int histRev: config.history && config.history.rev !== undefined ? config.history.rev : -1

    // key -> {value, user}: what each key was when the session first touched it.
    property var start: ({})
    // key -> value: what the session shows now (and applies).
    property var shown: ({})
    readonly property var keys: Object.keys(shown)
    readonly property bool active: keys.length > 0
    property bool txMade: false      // the session's last apply made a transaction
    property int rev: -1             // the config revision that transaction left (-1: not known)
    property bool busy: false        // an apply is out, or its revision is awaited
    property var sent: null          // the values of the apply that is out
    property string ending: ""       // "keep" | "put" while busy
    property string error: ""        // the last refusal's i18n key, until the next change
    property string errorKey: ""     // the key it was about
    property int seq: 0

    signal settled()

    function provOf(key) { return config.values ? config.values[key] : undefined }
    function isUser(p) { return !!p && !!p.source && p.source.kind === "user" }
    // The value the session shows for `key`, else the one in effect.
    function valueOf(key) {
        if (shown[key] !== undefined) return shown[key]
        var p = provOf(key)
        return p ? p.value : undefined
    }
    function has(key) { return shown[key] !== undefined }

    // A value moved to. `pairs` may be {key: value, …} for one gesture that changes several keys.
    function show(key, value) {
        var pairs = {}
        if (typeof key === "object") pairs = key
        else pairs[key] = value
        var s = Object.assign({}, shown)
        for (var k in pairs) {
            if (start[k] === undefined) {
                var p = provOf(k)
                var st = Object.assign({}, start)
                st[k] = { value: p ? p.value : undefined, user: isUser(p) }
                start = st
            }
            s[k] = pairs[k]
        }
        shown = s
        error = ""
        errorKey = ""
        if (!busy) step()
    }
    function ops(values) {
        var out = []
        for (var k in values) out.push({ set: k, value: values[k] })
        return out
    }
    function step() {
        var undoFirst = txMade && rev >= 0 && histRev === rev
        if (undoFirst) Store.send({ t: "undo", id: "apv" + (++seq) })
        busy = true
        sent = Object.assign({}, shown)
        Store.apply(ops(sent), function (errs) {
            if (errs) return ps.refused(errs, undoFirst)
            ps.txMade = true
            ps.rev = -1
            ps.awaitRev()
        })
    }
    // The newest change is refused: the whole batch was (apply is atomic). It leaves the session; the rest is applied
    // again (the undo before it already took the last step back).
    function refused(errs, undone) {
        var e = errs[0] || {}
        error = e.code || "error.internal"
        errorKey = e.key || ""
        // (the refused key's starting value stays in `start`: a put back still restores it if it moved)
        var s = Object.assign({}, shown)
        if (errorKey !== "" && s[errorKey] !== undefined) delete s[errorKey]
        else s = ({})
        if (undone) txMade = false
        shown = s
        busy = false
        if (ending === "put") return finishPut()
        if (ending === "keep") return finishKeep()
        if (keys.length > 0 && !A.same(shown, sent)) step()
    }
    // The patch carrying the session's values (and a new revision) names the transaction's revision.
    property int revBefore: -1
    function awaitRev() {
        revBefore = histRev
        revTimer.restart()
        checkRev()
    }
    function arrived() {
        for (var k in sent) {
            var p = provOf(k)
            if (!p || !A.same(p.value, sent[k])) return false
        }
        return true
    }
    function checkRev() {
        if (!revTimer.running) return
        if (histRev === revBefore || !arrived()) return
        revTimer.stop()
        rev = histRev
        stepDone()
    }
    onHistRevChanged: checkRev()
    onConfigChanged: checkRev()
    Timer {
        id: revTimer
        interval: 2000
        onTriggered: { ps.rev = -1; ps.stepDone() }
    }
    function stepDone() {
        busy = false
        if (ending === "put") return finishPut()
        if (ending === "keep") return finishKeep()
        if (!A.same(shown, sent)) step()
        else settled()
    }

    // Enter: the shown values stay, as the one undo step they already are.
    function keep() {
        if (!active) return
        if (busy) { ending = "keep"; return }
        finishKeep()
    }
    function finishKeep() { clear() }
    // Esc and every other way out: the values the session started from come back.
    function putBack() {
        if (!active && !txMade) return
        if (busy) { ending = "put"; return }
        finishPut()
    }
    function finishPut() {
        var st = start
        var undo = txMade && rev >= 0 && histRev === rev
        clear()
        if (undo) { Store.send({ t: "undo", id: "apv" + (++seq) }); return }
        var o = []
        for (var k in st) {
            var p = provOf(k)
            if (p && A.same(p.value, st[k].value) && isUser(p) === st[k].user) continue
            o.push(st[k].user ? { set: k, value: st[k].value } : { reset: k })
        }
        if (o.length > 0) Store.apply(o, null)
    }
    // Every way out but keep: the menu (and this session with it) is destroyed — the launcher closed, the card closed, a
    // click away. Inline, not putBack(): during teardown an object's own functions may already be gone (Watch.qml). An
    // apply still out is answered first (the daemon takes one connection's requests in order), so the starting values
    // set after it win.
    Component.onDestruction: {
        if (ending === "keep") return
        var ks = Object.keys(start)
        if (ks.length === 0 || (Object.keys(shown).length === 0 && !txMade)) return
        if (!busy && txMade && rev >= 0 && histRev === rev) { Store.send({ t: "undo", id: "apv-end" }); return }
        var o = []
        for (var i = 0; i < ks.length; i++)
            o.push(start[ks[i]].user ? { set: ks[i], value: start[ks[i]].value } : { reset: ks[i] })
        Store.apply(o, null)
    }
    function clear() {
        revTimer.stop()
        start = ({})
        shown = ({})
        sent = null
        txMade = false
        rev = -1
        busy = false
        ending = ""
    }
}
