import QtQuick
import "../../core"
import ".."
import "../../surfaces" as S

// Module `workspaces`: this output's workspaces (svc.workspaces `outputs`, or the "*" list for every output). In a row:
// flat chrome a dot each, the focused one a wider accent bar; chromes with groups a small numbered key — focused lit in
// the accent, occupied on the container (an outlined box under line chrome), empty on the ring (keycap) or bare — that
// sinks, shrinks or flashes while pressed. In a column: dots, the focused one taller. A click focuses the workspace (niri's
// own action through the daemon). The chips are the drop targets of the window list (the link's `chips`).
ModuleBase {
    id: m
    Watch { doc: "svc.workspaces"; active: m.live }
    readonly property var doc: Store.docs["svc.workspaces"] || ({})
    // I408: its own options (`modules.workspaces.*`, its right-click menu).
    S.BarConfig { id: cfg; screen: null }
    readonly property bool showEmpty: cfg.valueOf("modules.workspaces.empty", true) === true
    readonly property string marks: String(cfg.valueOf("modules.workspaces.marks", "look"))
    readonly property bool scrolls: cfg.valueOf("modules.workspaces.scroll", false) === true
    // I285: last-seen stills while this module is out and its previews are on; the pointer's arrival keeps what is on screen.
    readonly property bool previews: cfg.valueOf("modules.workspaces.previews", true) === true
    Watch { doc: "svc.previews"; active: m.live && m.previews }
    HoverHandler { onHoveredChanged: if (hovered && m.previews) Store.act("preview.refresh", { output: m.output }) }
    readonly property var allPills: {
        var o = doc.outputs || {}
        return o[m.output] || o["*"] || []
    }
    readonly property var pills: showEmpty ? allPills
        : allPills.filter(function (p) { return p.focused || p.occupied })
    readonly property int dragWs: m.link ? m.link.dragWs : -1
    implicitWidth: vertical ? col.implicitWidth : row.implicitWidth
    implicitHeight: vertical ? col.implicitHeight : row.implicitHeight
    width: implicitWidth
    height: implicitHeight

    function publish(rep) {
        if (!m.link) return
        var a = []
        for (var i = 0; i < rep.count; i++) a.push(rep.itemAt(i))
        m.link.chips = a
    }
    function geo() { return [["workspaces", m]] }

    // The next workspace along the list; a notch at a time, a touchpad's small steps adding up to one.
    property real wheelSum: 0
    function scrollBy(steps) {
        var at = -1
        for (var i = 0; i < pills.length; i++) if (pills[i].focused) at = i
        var to = Math.max(0, Math.min(pills.length - 1, at + steps))
        if (at >= 0 && to !== at) Store.act("workspace.focus", { id: pills[to].id })
    }
    WheelHandler {
        enabled: m.scrolls
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function (ev) {
            m.wheelSum += ev.angleDelta.y !== 0 ? ev.angleDelta.y : ev.angleDelta.x
            var steps = m.wheelSum > 0 ? Math.floor(m.wheelSum / 120) : Math.ceil(m.wheelSum / 120)
            if (steps === 0) return
            m.wheelSum -= steps * 120
            m.scrollBy(-steps)
        }
    }

    Component {
        id: dotPill
        Rectangle {
            required property var modelData
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            height: modelData.focused ? 10 : 8
            width: modelData.focused ? 24 : 8
            radius: height / 2
            color: modelData.focused ? Theme.accent : (modelData.occupied ? Theme.fg : "transparent")
            border.width: (!modelData.focused && !modelData.occupied) ? 1 : 0
            border.color: Theme.dim
            Behavior on width {
                enabled: m.live
                NumberAnimation { duration: Theme.stdMs; easing.type: Easing.OutBack; easing.overshoot: Theme.overshoot }
            }
            TapHandler { margin: 4; onTapped: Store.act("workspace.focus", { id: modelData.id }) }
            PreviewSource { source: "workspace:" + modelData.id; output: m.output; enabled_: m.previews && !modelData.focused && m.dragWs < 0 }
            // A window dragged over this workspace (W36): a ring round the dot.
            Rectangle {
                visible: m.dragWs === modelData.id
                anchors.centerIn: parent
                width: parent.width + 8
                height: parent.height + 8
                radius: height / 2
                color: "transparent"
                border.width: 2
                border.color: Theme.accent
            }
        }
    }
    Component {
        id: keyPill
        Block {
            id: kp
            required property var modelData
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            anchors.verticalCenterOffset: Theme.shadowDy / 2
            width: modelData.focused ? 34 : 22
            height: 20 + Theme.shadowDy
            radius: Theme.rFull
            ringScale: 0
            softScale: 0
            pressed: wsTap.pressed
            fill: modelData.focused ? Theme.accent
                : (modelData.occupied ? (Theme.lifted ? Theme.containerHigh : "transparent")
                    : (Theme.ringW > 0 ? Theme.ring : "transparent"))
            opacity: modelData.focused || modelData.occupied ? 1 : 0.7
            Behavior on width {
                enabled: m.live && Theme.springOn
                NumberAnimation { duration: Theme.stdMs + 80; easing.type: Easing.OutBack; easing.overshoot: Theme.overshoot }
            }
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                anchors.centerIn: parent
                color: kp.modelData.focused ? Theme.fgOnAccent : (kp.modelData.occupied ? Theme.fg : Theme.dim)
                font.pixelSize: Theme.fsCaption
                font.weight: Theme.wBold
                font.family: Theme.fam(text, Theme.families)
                text: kp.modelData.idx ?? ""
            }
            TapHandler { id: wsTap; onTapped: Store.act("workspace.focus", {id: kp.modelData.id}) }
            PreviewSource { source: "workspace:" + kp.modelData.id; output: m.output; enabled_: m.previews && !kp.modelData.focused && m.dragWs < 0 }
            // A window dragged over this workspace (W36): a ring round the key.
            Rectangle {
                visible: m.dragWs === kp.modelData.id
                anchors.fill: parent
                anchors.margins: -3
                radius: height / 2
                color: "transparent"
                border.width: 2
                border.color: Theme.accent
            }
        }
    }
    // W53.8 (`[decor] workspace.mark = indicator`): M3's navigation bar — each workspace its number, the focused one on the
    // active indicator (a full-round pill in the tonal `selected` with its ink: md.comp.navigation-bar.active-indicator,
    // secondary-container, 64 x 32 in an 80 dp bar; here twice as wide as tall, the bar's height less its pad), the
    // others bare in the variant ink, empty ones fainter. The pill widens to the focused item.
    readonly property bool navMark: Theme.decor("workspace.mark", "own") === "indicator"
    Component {
        id: navPill
        Item {
            id: np
            required property var modelData
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            height: Math.max(22, Math.min(32, m.thickness - 8))
            width: modelData.focused ? Math.round(height * 2) : Math.round(height * 1.1)
            Behavior on width {
                enabled: m.live && Theme.motionKind !== "none"
                NumberAnimation { duration: Theme.stdMs; easing.type: Easing.OutCubic }
            }
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                visible: np.modelData.focused || navTap.pressed || navHover.hovered
                color: np.modelData.focused ? Theme.selected : Qt.alpha(Theme.fg, navTap.pressed ? 0.10 : 0.08)
            }
            Text {
                anchors.centerIn: parent
                color: np.modelData.focused ? Theme.color("color.on_selected", Theme.fg)
                    : Qt.alpha(Theme.color("color.on_surface_variant", Theme.dim), np.modelData.occupied ? 1 : 0.6)
                font.pixelSize: Theme.fsCaption + 1
                font.weight: np.modelData.focused ? Theme.wBold : Theme.wMedium
                font.family: Theme.fam(text, Theme.families)
                text: np.modelData.idx ?? ""
            }
            HoverHandler { id: navHover }
            TapHandler { id: navTap; onTapped: Store.act("workspace.focus", {id: np.modelData.id}) }
            PreviewSource { source: "workspace:" + np.modelData.id; output: m.output; enabled_: m.previews && !np.modelData.focused && m.dragWs < 0 }
            // A window dragged over this workspace (W36): a ring round the item.
            Rectangle {
                visible: m.dragWs === np.modelData.id
                anchors.fill: parent
                anchors.margins: -3
                radius: height / 2
                color: "transparent"
                border.width: 2
                border.color: Theme.accent
            }
        }
    }
    Component {
        id: columnPill
        Item {
            required property var modelData
            width: m.thickness
            height: modelData.focused ? 24 : 8
            PreviewSource { source: "workspace:" + modelData.id; output: m.output; enabled_: m.previews && !modelData.focused && m.dragWs < 0 }
            Rectangle {
                anchors.centerIn: parent
                width: modelData.focused ? 10 : 8
                height: parent.height
                radius: width / 2
                color: modelData.focused ? Theme.accent : (modelData.occupied ? Theme.fg : "transparent")
                border.width: (!modelData.focused && !modelData.occupied) ? 1 : 0
                border.color: Theme.dim
            }
            // A window dragged over this workspace (W36): a ring round the dot.
            Rectangle {
                visible: m.dragWs === modelData.id
                anchors.centerIn: parent
                width: 18
                height: parent.height + 8
                radius: width / 2
                color: "transparent"
                border.width: 2
                border.color: Theme.accent
            }
        }
    }

    Row {
        id: row
        visible: !m.vertical
        spacing: m.marks === "look" && m.navMark ? 2 : ((m.marks === "look" ? Theme.groups : m.marks === "numbers") ? Theme.xs + 1 : Theme.gap)
        Repeater {
            id: repH
            model: m.vertical ? [] : m.pills
            delegate: m.marks === "dots" ? dotPill : m.marks === "numbers" ? keyPill
                : (m.navMark ? navPill : (Theme.groups ? keyPill : dotPill))
            onItemAdded: Qt.callLater(m.publish, repH)
            onItemRemoved: Qt.callLater(m.publish, repH)
        }
    }
    Column {
        id: col
        visible: m.vertical
        spacing: Theme.gap
        Repeater {
            id: repV
            model: m.vertical ? m.pills : []
            delegate: columnPill
            onItemAdded: Qt.callLater(m.publish, repV)
            onItemRemoved: Qt.callLater(m.publish, repV)
        }
    }
}
