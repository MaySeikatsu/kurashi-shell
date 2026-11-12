import QtQuick
import Quickshell
import "../../core"
import ".."
import "../expanded"

// Settings as a sidebar section (W77, K146; docs/ux/settings.md "In a sidebar"; I501, the user's "Full Settings docked"):
// a card that takes the column's free height with a well in it, and the real Settings app — its own process — over that
// well, as the web dock's page shows over its panel. While the well rests (`Placement`: not moving, not clipped) this
// reports where it is on its output (`settings.dock {output, x, y, width, height, radius}`: the window's origin on the
// output, Light.originOf, plus the well's place in it — zones counted, so a pinned column that keeps a zone and a column
// that ignores zones both land right) and the daemon has Settings map its dock there; when it goes (the sidebar closes,
// slides, scrolls it, the "+" picker or a tile's page covers it) the dock is withdrawn (`settings.dock {}`) and Settings
// unmaps (0 frames). The well itself says what is under it: "Opening Settings…" until Settings covers it, the reason when
// Settings cannot open (Shōjiki), and "shown on <output>" with Show here while another sidebar's section has it (the last
// one to rest wins). Ma: it watches `runtime.settings` while the section is made; nothing runs at rest.
Card {
    id: ss
    // The least height Settings is usable in; the column gives it the rest of the output (as the notifications).
    readonly property int minHeight: 360
    implicitHeight: minHeight
    // Set by the column: something lies over the well (the "+" picker, a tile's page).
    property bool covered: false

    readonly property var qsw: ss.Window.window ? ss.QsWindow.window : null
    // (B102: a sidebar kept after it closed is not shown: nothing is docked in it)
    readonly property bool live: !qsw || qsw.live !== false
    readonly property string outName: qsw && qsw.screen ? String(qsw.screen.name) : ""

    Watch { doc: "runtime.settings" }
    readonly property var dock: (Store.docs["runtime.settings"] || ({})).dock || null
    function same(d, p) { return !!d && !!p && String(d.output) === p.output && d.x === p.x && d.y === p.y }
    readonly property bool ours: same(dock, sentPlace)
    property string err: ""
    Refusal { id: refusal }

    Rectangle {
        id: well
        objectName: "settings-well"
        width: ss.width - 2 * ss.inPad
        height: Math.max(0, ss.height - 2 * ss.inPad)
        radius: Theme.nested(ss.radius, ss.inPad)
        color: Theme.surface
        border.width: 1
        border.color: Theme.containerHigh
        Accessible.role: Accessible.Pane
        Accessible.name: I18n.tr("config.choice.sidebar_section.settings")

        Column {
            anchors.centerIn: parent
            width: parent.width - 2 * Theme.pad
            spacing: Theme.gap
            visible: ss.err !== "" || ss.elsewhere || (ss.ours && ss.place !== null)
            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: ss.err !== "" ? "error" : "settings"
                glyph: ss.err !== "" ? "!" : "⚙"
                size: Theme.fs * 2 + 6
                color: ss.err !== "" ? Theme.error : Theme.dim
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                color: ss.err !== "" ? Theme.error : Theme.dim
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: ss.err !== "" ? ss.err
                    : ss.elsewhere ? I18n.tr("sidebar.settings.elsewhere").replace("{output}", String(ss.dock.output))
                    : I18n.tr("sidebar.settings.starting")
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }
            Button {
                objectName: "settings-show-here"
                visible: ss.elsewhere && ss.err === ""
                anchors.horizontalCenter: parent.horizontalCenter
                label: I18n.tr("sidebar.settings.show_here")
                onClicked: ss.report(true)
            }
        }
    }

    // ---- where the well rests, reported on change only ----
    Placement {
        id: pl
        target: ss.live && !ss.covered ? well : null
        win: ss.Window.window
        output: ss.outName
    }
    // (read when the placement is offered: the well keeps still then)
    readonly property var place: {
        if (!pl.value || !qsw) return null
        var o = Light.originOf(qsw)
        var p = well.mapToItem(null, 0, 0)
        return { output: ss.outName !== "" ? ss.outName : String(pl.value.output), x: Math.round(o.x + p.x),
                 y: Math.round(o.y + p.y), width: Math.round(well.width), height: Math.round(well.height),
                 radius: Math.round(well.radius) }
    }
    // At rest while another section has the dock (it rested after this one).
    readonly property bool elsewhere: place !== null && dock !== null && !ours && sentPlace !== null
    property var sentPlace: null
    property string sent: ""
    function report(force) {
        var key = place ? JSON.stringify(place) : ""
        if (!force && key === sent) return
        if (place) {
            sent = key
            sentPlace = place
            ss.err = ""
            Store.act("settings.dock", place, function (done, e) {
                if (e) ss.err = refusal.text(e, "sidebar.settings.failed")
            })
        } else {
            var was = sentPlace
            sent = ""
            sentPlace = null
            ss.withdraw(was)
        }
    }
    // The dock goes only if it is still this section's (another output's section may have taken it since).
    function withdraw(was) {
        if (!was) return
        var d = (Store.docs["runtime.settings"] || ({})).dock
        if (same(d, was)) Store.act("settings.dock", {})
    }
    onPlaceChanged: report(false)
    Component.onDestruction: withdraw(sentPlace)
}
