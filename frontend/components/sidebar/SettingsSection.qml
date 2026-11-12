import QtQuick
import Quickshell
import "../../core"
import ".."
import "../expanded"

// Settings as a sidebar section (W77, K146; docs/ux/settings.md "In a sidebar"; I501, the user's "Full Settings docked"):
// a card that takes the column's free height with a well in it, and the real Settings app — its own process — over that
// well, as the web dock's page shows over its panel. While the well rests this reports where it is (`settings.dock`, the
// rect `Placement` measures: from the usable area's top and the sidebar's side) and the daemon has Settings map its dock
// there; when it goes (the sidebar closes, slides, scrolls it, the "+" picker or a tile's page covers it) the dock is
// withdrawn (`settings.dock {}`) and Settings unmaps (0 frames). The well itself says what is under it: "Opening
// Settings…" until Settings covers it, the reason when Settings cannot open (Shōjiki), and "shown on <output>" with Show
// here while another sidebar's section has it (the last one to rest wins). Ma: it watches `runtime.settings` only while
// the section is made (the column, and its minute after a close); nothing runs at rest.
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
    readonly property string side: qsw && qsw.anchors && qsw.anchors.left && !qsw.anchors.right ? "left" : "right"

    Watch { doc: "runtime.settings" }
    readonly property var dock: (Store.docs["runtime.settings"] || ({})).dock || null
    readonly property bool ours: dock !== null && sentPlace !== null && String(dock.output) === sentPlace.output
        && String(dock.side) === sentPlace.side
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
            visible: ss.err !== "" || ss.elsewhere || (ss.ours && pl.value !== null)
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
        origin: ss.qsw && ss.qsw.placementOrigin !== undefined ? ss.qsw.placementOrigin : Qt.point(0, 0)
        output: ss.Screen.name
        side: ss.side
    }
    readonly property var place: pl.value ? {
        output: String(pl.value.output), side: String(pl.value.side), inset: Math.round(pl.value.inset),
        top: Math.round(pl.value.top), width: Math.round(pl.value.width), height: Math.round(pl.value.height),
        radius: Math.round(well.radius)
    } : null
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
        if (d && String(d.output) === was.output && String(d.side) === was.side) Store.act("settings.dock", {})
    }
    onPlaceChanged: report(false)
    Component.onDestruction: withdraw(sentPlace)
}
