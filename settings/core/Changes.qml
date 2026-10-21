pragma Singleton
import QtQuick
import Quickshell

// Live preview (UX brief, settings 3) and the reset plans (2). A preview is the daemon's own change, so the shell shows
// the value as it is moved to. Each step takes back the one before with `undo`: a kept preview is one undo step.
// Keep (Enter) keeps it. Put back (Esc, leaving the page, closing the window) undoes it, and the undone step is hidden
// from Redo. If the config changed since the last step (another client), the original value is applied as a change of
// its own, so that change is never undone by mistake.
Singleton {
    id: root
    // The open preview, or null: {id, key, output, wasValue, wasUser, shown, value, txMade, rev, busy, ending}.
    property var session: null
    property int serial: 0
    // The keys whose change is a live preview (UX brief, settings 3). The schema does not mark them yet: this list is
    // the settings app's policy until a schema flag exists (docs/CONTRACT-CHANGE.md).
    readonly property var previewKeys: ["theme.colors.palette", "theme.colors.scheme", "theme.shape.radius_scale",
                                        "bar.edge", "theme.typography.family"]

    function previewable(key) { return previewKeys.indexOf(key) >= 0 }
    function activeFor(key, output) {
        return session !== null && session.key === key && session.output === (output || "")
    }
    function isUser(prov) { return !!prov && !!prov.source && prov.source.kind === "user" }
    function update(fields) { session = Object.assign({}, session, fields) }
    function setOp(key, output, value) {
        var op = { set: key, value: value }
        if (output) op.output = output
        return op
    }

    // A value moved to: it is shown at once, and the daemon gets it as one change (steps run in order).
    function show(key, output, value, prov) {
        if (!Store.live) return
        if (session !== null && !activeFor(key, output)) putBack()
        if (session === null) {
            serial++
            session = { id: serial, key: key, output: output || "", wasValue: prov ? prov.value : undefined,
                        wasUser: isUser(prov), shown: value, value: undefined, txMade: false, rev: -1,
                        busy: false, ending: "" }
        } else {
            update({ shown: value })
        }
        if (!session.busy) step()
    }
    // One change for the shown value. The step before is taken back first, when this session made one and the config
    // has not changed since; the two requests are answered in order by the daemon. "Not changed since" compares the
    // config's own revision (`history.rev`, the `rev` an apply answers) with this step's: one apply patches the document
    // several times, so the document's revision cannot say it. The patch may still be on its way: at or below is ours.
    function step() {
        var s = session
        var id = s.id
        var hist = (Store.config && Store.config.history) || ({})
        var undoFirst = s.txMade && hist.rev !== undefined && hist.rev <= s.rev
        if (undoFirst) Store.request({ t: "undo" }, null)
        // The apply's reply says whether this step made a change (txMade) and at which config revision (rev).
        update({ busy: true })
        var value = s.shown
        Store.apply([setOp(s.key, s.output, value)], function (m) {
            if (!session || session.id !== id) return
            // Refused: the row says why and shows the daemon's value again.
            if (m.t !== "applied") { session = null; return }
            update({ busy: false, txMade: !!m.undo, rev: m.rev, value: value })
            if (session.ending === "put") return revertNow()
            if (session.shown !== session.value) return step()
            if (session.ending === "keep") session = null
        })
    }
    // Enter: the shown value stays, as the one undo step it already is.
    function keep() {
        if (session === null) return
        if (session.busy) update({ ending: "keep" })
        else session = null
    }
    // Esc and the other ways out: the value the session started from comes back.
    function putBack() {
        if (session === null) return
        if (session.busy) update({ ending: "put" })
        else revertNow()
    }
    function revertNow() {
        var s = session
        session = null
        if (!s || !s.txMade) return
        if (s.rev === Store.revs.config) {
            Store.request({ t: "undo" }, function (m) {
                if (m.t !== "applied") return
                Store.noteApplied()
                Store.redoHidden = true
            })
        } else {
            Store.apply([s.wasUser ? setOp(s.key, s.output, s.wasValue) : Store.resetOp(s.key, s.output)], null)
        }
    }

    // The dry run of a reset: the diff the daemon would make (`preview`), for the confirm line. cb(diff) or cb(null).
    function planReset(ops, cb) {
        Store.dryRun(ops, function (m) { cb(m.t === "preview" ? m.diff : null) })
    }
    // A confirmed reset is one change (one undo step).
    function applyReset(ops, cb) { Store.apply(ops, cb) }
}
