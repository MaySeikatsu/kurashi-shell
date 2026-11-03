import QtQuick
import "../core"

// Under "Quick settings opens the right sidebar" (I154; K71 folded the bar buttons into the zones): a switch per side for its
// button in the bar, the sidebars open from here too — "Open now" for each side — and the line naming the
// keys the Home-Manager module binds by default (they need its niri binds file included; Settings cannot see niri's
// binds, so it names the defaults and where they come from). The left one only while the left sidebar has tabs.
Column {
    id: so
    spacing: Theme.gap
    width: parent ? parent.width : 400
    objectName: "sidebar-open"
    readonly property var tabs: Store.valueOf("sidebar.left.sections")
    readonly property bool hasLeft: Array.isArray(so.tabs) && so.tabs.length > 0
    property string error: ""

    // Session 20: each sidebar's button in the bar, as a switch — on when a zone of the bar's edge lists its module
    // (`sidebar_left` / `sidebar_right`, K71), so the switch is the layout's own state, not a second one. On adds it at
    // that end of the bar (left: the start zone's front, right: the end zone's end); off takes it out of every zone.
    readonly property var edgeNames: ["top", "bottom", "left", "right"]
    readonly property var zoneNames: ["start", "center", "end"]
    readonly property string barEdge: {
        for (var i = 0; i < so.edgeNames.length; i++) {
            var e = so.edgeNames[i]
            if (Store.valueOf("edges." + e + ".bar") === true) return e
        }
        return "top"
    }
    function zone(e, z) {
        var v = Store.valueOf("edges." + e + "." + z)
        return Array.isArray(v) ? v.slice() : []
    }
    function inBar(side) {
        var id = "sidebar_" + side
        for (var i = 0; i < so.zoneNames.length; i++)
            if (so.zone(so.barEdge, so.zoneNames[i]).indexOf(id) >= 0) return true
        return false
    }
    function setInBar(side, on) {
        var id = "sidebar_" + side, ops = []
        if (on) {
            var z = side === "left" ? "start" : "end"
            var l = so.zone(so.barEdge, z)
            if (side === "left") l.unshift(id); else l.push(id)
            ops.push({ set: "edges." + so.barEdge + "." + z, value: l })
        } else {
            for (var i = 0; i < so.zoneNames.length; i++) {
                var cur = so.zone(so.barEdge, so.zoneNames[i])
                if (cur.indexOf(id) >= 0)
                    ops.push({ set: "edges." + so.barEdge + "." + so.zoneNames[i],
                               value: cur.filter(function (x) { return x !== id }) })
            }
        }
        if (ops.length) Store.apply(ops)
    }

    function open(side) {
        Store.act("sidebar.open", { side: side }, function (m) {
            so.error = m.t === "done" ? "" : Store.actError(m, "sidebar.header.failed")
        })
    }

    Flow {
        width: so.width
        spacing: Theme.gap
        Repeater {
            model: ["right", "left"]
            Row {
                required property string modelData
                spacing: Theme.gap / 2
                visible: modelData === "right" || so.hasLeft
                Toggle {
                    objectName: "sidebar-in-bar-" + parent.modelData
                    label: I18n.tr("sidebar.in_bar." + parent.modelData)
                    checked: so.inBar(parent.modelData)
                    enabled: Store.live
                    onToggled: v => so.setInBar(parent.modelData, v)
                }
                Text {
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    antialiasing: !Theme.pixelType
                    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                    height: Theme.controlH
                    verticalAlignment: Text.AlignVCenter
                    color: Theme.fg
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr("sidebar.in_bar." + parent.modelData)
                }
            }
        }
    }
    Flow {
        width: so.width
        spacing: Theme.gap
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            antialiasing: !Theme.pixelType
            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
            height: Theme.controlH
            verticalAlignment: Text.AlignVCenter
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("sidebar.open_now")
        }
        Button {
            objectName: "sidebar-open-right"
            label: I18n.tr("action.sidebar.right.toggle")
            enabled: Store.live
            onClicked: so.open("right")
        }
        Button {
            objectName: "sidebar-open-left"
            visible: so.hasLeft
            label: I18n.tr("action.sidebar.left.toggle")
            enabled: Store.live
            onClicked: so.open("left")
        }
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        width: so.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fs - 1
        font.family: Theme.fam(text, Theme.families)
        text: I18n.fmt("sidebar.keys", { right: "Mod+Shift+N", left: "Mod+A" })
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        visible: so.error !== ""
        width: so.width
        wrapMode: Text.WordWrap
        color: Theme.error
        font.pixelSize: Theme.fs - 1
        font.family: Theme.fam(text, Theme.families)
        text: "⊘ " + so.error
    }
}
