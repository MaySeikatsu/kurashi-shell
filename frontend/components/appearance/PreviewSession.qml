import QtQuick
import "../../core"
import "appearance.js" as A

// The appearance menu's live preview (docs/ux/appearance-menu.md "Preview session"): Settings' Changes.qml ported to the
// shell's Store, for several keys at once. Every key changed in one visit is held here; each change takes back the
// session's last transaction (`undo`, only while no one committed since) and applies what differs as one `apply`, so the
// visit is one undo step. keep() leaves it in effect; putBack() takes it back — by undo, or, when the session cannot be
// sure its transaction is the last one, by setting the starting values again (`set` for the user's own, `reset`
// otherwise). Every way out but keep puts back (Esc, a close, the session's destruction).
//
// The transaction's revision: the shell's Store answers an apply with null or errors only (no `rev`, CONTRACT-CHANGE row
// 794), and the reply and the config patch may arrive in either order. So the session reads the config's revision
// before it sends and expects exactly one more per request (an undo and an apply: two); it takes the revision once the
// config document shows it with the session's values. Anything else — someone else's change in between, a patch that
// does not come within 2 s — leaves the revision unknown, and an unknown revision is never undone.
//
// A style or a look is not a value but an action (`theme.style.apply` / `theme.look.apply`: it resets the kind's keys,
// K53, as Settings' pickPack does); it is a step of its own: a key session open is kept first, the pack's step answers
// its revision (`{rev, undo}`), and the next pick or Esc undoes it while it is still the last change.
Item {
    id: ps
    visible: false
    Watch { doc: "config" }
    readonly property var config: Store.docs["config"] || ({})
    readonly property int histRev: config.history && config.history.rev !== undefined ? config.history.rev : -1

    // key -> {value, user}: what each key was when the session first touched it.
    property var start: ({})
    // key -> value: what the session shows now.
    property var shown: ({})
    readonly property var keys: Object.keys(shown)
    // A pack step held: {key, action, name, rev (-1 unknown), busy}; null without one.
    property var pack: null
    property string packWant: ""           // a pick made while the pack's action is out
    readonly property int count: keys.length + (pack ? 1 : 0)
    readonly property bool active: count > 0
    property bool txMade: false      // the session's last apply made a transaction
    property int rev: -1             // the config revision that transaction left (-1: not known)
    property bool busy: false        // a request is out, or its revision is awaited
    property var sent: null          // the values of the apply that is out
    property int expect: -1          // the revision the request out should leave
    property string ending: ""       // "keep" | "put" while busy
    property string error: ""        // the last refusal's i18n key, until the next change
    property string errorKey: ""     // the key it was about
    property int seq: 0

    function provOf(key) { return config.values ? config.values[key] : undefined }
    function isUser(p) { return !!p && !!p.source && p.source.kind === "user" }
    function effective(key) { var p = provOf(key); return p ? p.value : undefined }
    // The value the session shows for `key`, else the one in effect.
    function valueOf(key) {
        if (shown[key] !== undefined) return shown[key]
        if (pack && pack.key === key) return pack.name
        return effective(key)
    }
    function has(key) { return shown[key] !== undefined || (!!pack && pack.key === key) }
    function undo() { Store.send({ t: "undo", id: "apv" + (++seq) }) }

    // ---- keys ----
    // A value moved to. `key` may be {key: value, …}: one gesture that changes several keys.
    function show(key, value) {
        if (pack) keepPack()
        var pairs = {}
        if (typeof key === "object") pairs = key
        else pairs[key] = value
        var s = Object.assign({}, shown), st = Object.assign({}, start)
        for (var k in pairs) {
            if (st[k] === undefined) { var p = provOf(k); st[k] = { value: p ? p.value : undefined, user: isUser(p) } }
            s[k] = pairs[k]
        }
        start = st
        shown = s
        error = ""
        errorKey = ""
        if (!busy) step()
    }
    function step() {
        var undoFirst = txMade && rev >= 0 && histRev === rev
        // What is in effect under the apply: the starting values once the last step is undone, else what the config says.
        var o = []
        for (var k in shown) {
            var base = undoFirst ? start[k].value : effective(k)
            if (!A.same(shown[k], base)) o.push({ set: k, value: shown[k] })
        }
        var before = histRev
        stepShown = Object.assign({}, shown)
        if (undoFirst) undo()
        txMade = false
        rev = -1
        if (o.length === 0) {
            // Back where it started (or nothing to change): no apply, nothing of the session's left to take back.
            sent = null
            if (undoFirst) { busy = true; expect = before + 1; awaitRev(); return }
            return stepDone()
        }
        busy = true
        sent = {}
        for (var i = 0; i < o.length; i++) sent[o[i].set] = o[i].value
        expect = before + (undoFirst ? 2 : 1)
        Store.apply(o, function (errs) {
            if (errs) return ps.refused(errs, undoFirst)
            ps.txMade = true
            ps.awaitRev()
        })
    }
    // The newest change is refused: the whole batch was (apply is atomic). Its key leaves the session; the rest is applied
    // again (the undo before it already took the last step back).
    function refused(errs, undone) {
        var e = errs[0] || {}
        error = e.code || "error.internal"
        errorKey = e.key || ""
        // (the refused key's starting value stays in `start`: a put back still restores it if it moved)
        var s = Object.assign({}, shown)
        if (errorKey !== "" && s[errorKey] !== undefined) delete s[errorKey]
        else s = ({})
        shown = s
        txMade = false
        rev = -1
        revTimer.stop()
        busy = false
        if (ending === "put") return finishPut()
        if (ending === "keep") return finishKeep()
        if (keys.length > 0) step()
    }
    function awaitRev() {
        revTimer.restart()
        checkRev()
    }
    function arrived() {
        for (var k in sent) if (!A.same(effective(k), sent[k])) return false
        return true
    }
    function checkRev() {
        if (!revTimer.running) return
        if (histRev > expect) { revTimer.stop(); rev = -1; return stepDone() }     // someone else's change came in too
        if (histRev !== expect || !arrived()) return
        revTimer.stop()
        rev = sent === null ? -1 : histRev
        stepDone()
    }
    onHistRevChanged: checkRev()
    onConfigChanged: checkRev()
    Timer {
        id: revTimer
        interval: 2000
        onTriggered: { ps.rev = -1; ps.stepDone() }
    }
    // A value moved again while the step was out: one more step for it.
    function stepDone() {
        busy = false
        if (ending === "put") return finishPut()
        if (ending === "keep") return finishKeep()
        if (!A.same(shown, stepShown)) step()
    }
    property var stepShown: ({})

    // ---- packs (a style, a look) ----
    function showPack(key, action, name) {
        if (keys.length > 0) finishKeep()
        error = ""
        errorKey = ""
        if (pack && pack.busy) { packWant = name; pack = Object.assign({}, pack, { name: name }); return }
        var undoFirst = !!pack && pack.rev >= 0 && histRev === pack.rev
        if (undoFirst) undo()
        pack = { key: key, action: action, name: name, rev: -1, busy: true }
        Store.act(action, { name: name }, function (done, err) {
            if (!ps.pack) return
            if (err) {
                ps.error = err.msg || "error.internal"
                ps.errorKey = key
                ps.pack = null
                return
            }
            var r = done && done.data && done.data.rev !== undefined ? Number(done.data.rev) : -1
            ps.pack = Object.assign({}, ps.pack, { rev: r, busy: false })
            if (ps.ending === "put") { ps.ending = ""; return ps.putPack() }
            if (ps.ending === "keep") { ps.ending = ""; return ps.keepPack() }
            if (ps.packWant !== "") { var w = ps.packWant; ps.packWant = ""; ps.showPack(key, action, w) }
        })
    }
    function keepPack() { pack = null; packWant = "" }
    // Undone while it is the last change; else it stays (a pack resets many keys: only its own undo restores them).
    function putPack() {
        var p = pack
        pack = null
        packWant = ""
        if (p && p.rev >= 0 && histRev === p.rev) undo()
    }

    // ---- the ends ----
    // Enter: what is shown stays, as the one undo step it already is.
    function keep() {
        if (pack) { if (pack.busy) ending = "keep"; else keepPack() }
        if (keys.length === 0) return
        if (busy) { ending = "keep"; return }
        finishKeep()
    }
    function finishKeep() { clear() }
    // Esc and every other way out: the values the session started from come back.
    function putBack() {
        if (pack) { if (pack.busy) ending = "put"; else putPack() }
        if (keys.length === 0 && !txMade) return
        if (busy) { ending = "put"; return }
        finishPut()
    }
    function finishPut() {
        var st = start
        var mine = txMade && rev >= 0 && histRev === rev
        clear()
        if (mine) { undo(); return }
        var o = []
        for (var k in st) {
            var p = provOf(k)
            if (p && A.same(p.value, st[k].value) && isUser(p) === st[k].user) continue
            o.push(st[k].user ? { set: k, value: st[k].value } : { reset: k })
        }
        if (o.length > 0) Store.apply(o, null)
    }
    // Every way out but keep: the menu (and this session with it) is destroyed — the launcher closed, the card closed, a
    // click away. Inline, not putBack(): during teardown an object's own functions may already be gone (Watch.qml). A
    // request still out is answered first (the daemon takes one connection's requests in order), so what is sent here
    // comes after it.
    Component.onDestruction: {
        if (pack && !pack.busy && pack.rev >= 0 && histRev === pack.rev) Store.send({ t: "undo", id: "apv-pack-end" })
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
