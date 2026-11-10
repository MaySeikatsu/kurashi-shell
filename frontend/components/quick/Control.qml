import QtQuick
import "../../core"
import "../expanded"

// One control of the control centre (W70, docs/ux/control-centre-modules.md): its state as the daemon reports it, its
// labels, its request and its refusal text, in one place. The centre's tile, the control's bar module and its page in the
// card all read one of these, so a value, a reason and a "connecting" read the same wherever the control shows (Shōjiki).
// Nothing is drawn here. A control watches its document while `live` (Ma): the centre's while it is up, a bar module's
// while its host is shown; Store counts the watches, so two views of one document hold one subscription.
// Each control fills in the same face, so a tile, a glance or a card can bind to any of them:
//   mid, label, glyph, icon                — what it is (its module id, its name, its mark)
//   known, reason, forcedBy                — whether it can be used now, and why not (a reason is short and translated)
//   on, toggles, req, value, pendingText   — what is in effect, whether a press switches it, and the request that does
//   page, settingsPage                     — its page in the card ("" when it has none), the Settings page of its setting
Item {
    id: c
    visible: false
    property bool live: true

    property string mid: ""
    property string label: ""
    property string glyph: ""
    property string icon: ""
    // Its document is there at all (a daemon without the service has none: a reason, never a guessed value).
    property bool known: true
    property string reason: ""
    property string forcedBy: ""
    property bool on: false
    property bool toggles: true
    property var req: null
    property string value: ""
    property string pendingText: I18n.tr("island.quick.changing")
    property string page: ""
    property string settingsPage: ""
    // W71 (f): while on, a click on the control's module switches it off whatever its setting says (a recording stops).
    property bool clickStops: false

    readonly property bool inert: reason !== "" || forcedBy !== ""
    readonly property bool busy: req !== null && req.pending
    readonly property bool failed: req !== null && req.failure !== ""
    // What a view says the control is now: the reason, who holds it, a failure, the pending line, else its value.
    readonly property string stateText: reason !== "" ? reason
        : forcedBy !== "" ? I18n.tr("island.quick.forced").replace("{by}", forcedBy)
        : failed ? req.failure
        : busy ? pendingText
        : value

    // The control's own press: a switch flips (a failed one retries); one that cannot be switched now does nothing.
    function toggle() {
        if (inert || busy || req === null || !toggles) return false
        if (failed) req.retry()
        else req.begin(!on)
        return true
    }

    // A request's answer: a refusal is reported as the daemon's translated reason, else the control's own line.
    Refusal { id: refusal }
    function cb(report, key) {
        return function (done, err) { if (err) report(refusal.text(err, key)) }
    }

    // Formats shared by the controls. Pure: a value is what the document says now.
    function pad(v) { return (v < 10 ? "0" : "") + v }
    function hhmm(ms) {
        var t = new Date(ms)
        return pad(t.getHours()) + ":" + pad(t.getMinutes())
    }
}
