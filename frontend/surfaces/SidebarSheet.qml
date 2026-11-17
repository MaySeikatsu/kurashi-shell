import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components"
import "../components/sidebar"

// A sidebar on the top or the bottom edge (K165, docs/ux/edge-sidebars.md): `side` top or bottom. A sheet that comes
// out of its edge — joined to the bar or the frame's band there, as the bar's cards and the terminal's sheet are — and
// holds the sidebars' sections, one page each with tabs (LeftColumn). Its width is the whole edge or a centred part of
// it (`sidebar.<side>.span`, `.length`), its height a share of the screen (`.height`). Open while `runtime.ui.sidebar`
// names its side, on the output that asked (else the focused one); one at a time with the Stage's panels, the launcher
// and the other sidebars (the daemon decides). Esc, the same toggle, a click outside it, `sidebar.close` and `ui.close`
// close it. No window while it is closed and its motion has ended (0 frames, no section watched: Ma).
Scope {
    id: es
    required property string side            // "top" | "bottom"
    property var focusedScreen: null

    OpenOn { id: openOn; side: es.side; focusedScreen: es.focusedScreen }
    BarConfig { id: cfg; screen: null }
    readonly property var sections: {
        var v = cfg.valueOf("sidebar." + side + ".sections", [])
        return Array.isArray(v) ? v.filter(function (s) { return typeof s === "string" && s !== "" }) : []
    }
    readonly property bool full: String(cfg.valueOf("sidebar." + side + ".span", "part")) === "full"
    readonly property real lengthPct: full ? 100 : Math.max(30, Math.min(100, Number(cfg.valueOf("sidebar." + side + ".length", 66))))
    readonly property real heightFrac: Math.max(20, Math.min(95, Number(cfg.valueOf("sidebar." + side + ".height", 45)))) / 100
    // The page each output's sheet showed last (the column is made again each time it opens).
    property var pages: ({})

    readonly property bool want: openOn.toggled && openOn.toggledOn !== "" && sections.length > 0
    readonly property bool still: Theme.motionKind === "none"
    property real out: 0                  // 0 in, 1 out
    readonly property bool shown: out > 0 || want
    // The output stays while the sheet leaves.
    property string onName: ""
    onWantChanged: {
        if (want) onName = openOn.toggledOn
        outAnim.to = want ? 1 : 0
        if (still) out = outAnim.to
        else outAnim.restart()
    }
    NumberAnimation {
        id: outAnim
        target: es
        property: "out"
        duration: Theme.stdMs
        easing.type: Easing.BezierSpline
        easing.bezierCurve: es.want ? Theme.enterCurve : Theme.continuousCurve
    }

    Loader {
        active: es.shown
        sourceComponent: PanelWindow {
            id: win
            readonly property var scr: openOn.screenNamed(es.onName)
            Watch { doc: "runtime.layout" }
            SheetGeom {
                id: sg
                outName: es.onName
                scrW: win.scr ? win.scr.width : 1920
                scrH: win.scr ? win.scr.height : 1080
                place: "edge"
                edgeSet: es.side
                lengthPct: es.lengthPct
                heightFrac: es.heightFrac
            }
            screen: win.scr
            anchors.top: true
            anchors.left: true
            margins.top: sg.winY
            margins.left: sg.winX
            implicitWidth: Math.max(1, sg.winW)
            implicitHeight: Math.max(1, sg.winH)
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "kurashi-sidebar-" + es.side
            WlrLayershell.keyboardFocus: es.want ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            // A click elsewhere on this output closes it (niri has no focus grab for layer surfaces).
            PanelWindow {
                screen: win.scr
                visible: es.want
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                exclusiveZone: 0
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.namespace: "kurashi-sidebar-away"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                anchors { top: true; bottom: true; left: true; right: true }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onPressed: Store.act("sidebar.close", {})
                }
            }

            SheetFrame {
                anchors.fill: parent
                geom: sg
                out: es.out
                still: es.still
                penSeed: 0x51DE
                Keys.onEscapePressed: Store.act("sidebar.close", {})
                LeftColumn {
                    id: column
                    objectName: "sidebar-sheet-" + es.side
                    x: Theme.pad
                    y: Theme.pad
                    width: parent.width - 2 * Theme.pad
                    height: parent.height - 2 * Theme.pad
                    tabs: es.sections
                    side: es.side
                    outName: es.onName
                    pageId: es.pages[es.onName] || ""
                    onPageChosen: page => { var p = Object.assign({}, es.pages); p[es.onName] = page; es.pages = p }
                    focus: true
                }
            }
        }
    }
}
