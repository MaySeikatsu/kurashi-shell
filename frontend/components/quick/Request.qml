import QtQuick
import "../../core"

// A request that changes a value the card shows (W13, docs/ux/quick-settings.md). `value` is the value in effect, as the
// daemon reports it. `begin(to)` sends the request through `start(to, report)`. Until the value reads `to` the request is
// pending, and its owner shows "connecting"; after 30 s without that, or when the daemon refuses (`report(text)`),
// `failure` holds the translated reason and `retry()` sends the same request again. Nothing is shown as in effect before
// the daemon says so (Shōjiki). The timer runs only while a request is pending (Ma).
Item {
    id: req
    visible: false
    property var value: undefined
    property var start: null
    property var want: undefined          // the value asked for until the daemon confirms it; undefined when none
    property string failure: ""
    property var lastTo: undefined

    readonly property bool pending: want !== undefined

    function begin(to) {
        if (pending || start === null) return
        lastTo = to
        failure = ""
        want = to
        start(to, fail)
    }
    function retry() { if (failure !== "") begin(lastTo) }
    function fail(text) { want = undefined; failure = text }

    // Any change of the value ends a pending request that it confirms, and an old refusal: the value in effect is new.
    onValueChanged: {
        if (pending && value === want) want = undefined
        failure = ""
    }

    Timer {
        interval: 30000
        running: req.pending
        onTriggered: req.fail(I18n.tr("island.quick.timeout"))
    }
}
