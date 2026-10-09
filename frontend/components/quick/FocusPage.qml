import QtQuick
import "../../core"
import "../expanded"
import ".."

// The focus page (docs/ux/quick-settings.md, Design 2): do-not-disturb with its end. The switch turns it on for good or off
// (`notify.dnd {on}`); the choices turn it on until a time (`until`, ms since the epoch: the daemon ends it by itself).
// The state line says the value in effect: "Until 14:00" when a time is set. No calendar choice: no calendar service is
// served. The switch's request comes from QuickPanel, shared with the tile.
Column {
    id: fp
    width: parent.width
    spacing: Theme.gap
    property var dndReq: null
    signal backRequested()

    function focusFirst() { header.forceActiveFocus() }

    readonly property var n: Store.docs["svc.notifications"] || ({})
    readonly property bool dnd: n.dnd === true
    readonly property bool timed: typeof n.dnd_until === "number"
    property string errText: ""
    Refusal { id: refusal }

    function pad(v) { return (v < 10 ? "0" : "") + v }
    function hhmm(ms) {
        var t = new Date(ms)
        return pad(t.getHours()) + ":" + pad(t.getMinutes())
    }
    // Tomorrow at 08:00, local time: the end of a night's focus.
    function tomorrowMs() {
        var t = new Date()
        t.setDate(t.getDate() + 1)
        t.setHours(8, 0, 0, 0)
        return t.getTime()
    }
    function choose(args) {
        fp.errText = ""
        Store.act("notify.dnd", args, function (done, err) {
            if (err) fp.errText = refusal.text(err, "island.quick.focus.failed")
        })
    }

    PageHeader {
        id: header
        title: I18n.tr("island.quick.tile.focus")
        backName: I18n.tr("island.quick.back")
        onBack: fp.backRequested()
    }
    // The switch's label carries the value in effect: "Off", "On", or "Until 14:00" when a time is set.
    Row {
        width: fp.width
        spacing: Theme.gap
        Column {
            width: parent.width - dndSwitch.width - Theme.gap
            anchors.verticalCenter: dndSwitch.verticalCenter
            Text {
                width: parent.width
                elide: Text.ElideRight
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("island.quick.focus.dnd")
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: fp.dnd ? (fp.timed ? I18n.tr("island.quick.tile.until").replace("{t}", fp.hhmm(fp.n.dnd_until)) : I18n.tr("island.quick.on"))
                    : I18n.tr("island.quick.off")
            }
        }
        ToggleSwitch {
            id: dndSwitch
            checked: fp.dnd
            enabled: !(fp.dndReq !== null && fp.dndReq.pending)
            label: I18n.tr("island.quick.focus.dnd")
            onToggled: on => { if (fp.dndReq !== null) fp.dndReq.begin(on) }
        }
    }
    StateLine {
        width: fp.width
        req: fp.dndReq
        pendingText: I18n.tr("island.quick.changing")
    }
    Text {
        width: fp.width
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.quick.focus.choose")
    }
    ChoiceRow {
        width: fp.width
        title: I18n.tr("island.quick.focus.hour")
        sub: I18n.tr("island.quick.tile.until").replace("{t}", fp.hhmm(Date.now() + 3600000))
        onActivated: fp.choose({on: true, until: Date.now() + 3600000})
    }
    ChoiceRow {
        width: fp.width
        title: I18n.tr("island.quick.focus.tomorrow")
        onActivated: fp.choose({on: true, until: fp.tomorrowMs()})
    }
    ChoiceRow {
        width: fp.width
        title: I18n.tr("island.quick.focus.indefinite")
        onActivated: fp.choose({on: true})
    }
    Text {
        visible: fp.errText !== ""
        width: fp.width
        wrapMode: Text.WordWrap
        color: Theme.error
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: fp.errText
    }
}
