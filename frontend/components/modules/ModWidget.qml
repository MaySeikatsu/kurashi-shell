import QtQuick
import Quickshell
import "../../core"
import "../../core/mods.js" as Mods
import "../island"

// A mod's glance (K26, K72: zone entry `{id: "mod:<id>:<name>", kind: "mod", mod, provide: "widget:<name>"}`): the mod's
// `widget:<name>` through ModLoader, loaded only while the host shows it (and, in a column, while the fit gives it its
// slot); its panel grows out of it (AnchorReport) and its `peek:<name>` shows on hover or keyboard focus (PeekSource, K35).
// In a column a widget that declares `vertical` is told so; one that does not is drawn as it is, clipped to its slot.
ModuleBase {
    id: m
    property string mod: ""
    property string provide: ""
    readonly property string name: String(provide).substring("widget:".length)
    readonly property var modsDoc: Store.docs["mods"]
    readonly property string url: Mods.qmlOf(modsDoc, provide, mod)
    readonly property string peekSource: Mods.qmlOf(modsDoc, "peek:" + name, mod) !== "" ? "mod:" + mod + ":" + name : ""
    present: url !== ""
    // A column slot's height until the widget has been measured. Small on purpose: an unmeasured widget is then loaded and
    // measured; a large default would keep a widget that does not fit unloaded, so it would never be measured.
    property int measured: 0
    readonly property int slotH: measured > 0 ? measured : thickness
    slotHeights: [slotH]
    width: vertical ? thickness : loader.width
    height: vertical ? slotH : loader.height
    clip: vertical
    function geo() { return [["slot-" + m.mod, m], ["widget-" + m.mod, loader.item]] }
    function measure() {
        if (loader.item && ("vertical" in loader.item) && loader.item.implicitHeight > 0)
            measured = Math.ceil(loader.item.implicitHeight)
    }

    ModLoader {
        id: loader
        anchors.centerIn: m.vertical ? parent : undefined
        anchors.verticalCenter: m.vertical ? undefined : parent.verticalCenter
        url: m.url
        // Past a column's end the widget is not loaded either (Ma).
        shown: m.live && m.fitSlots > 0
    }
    // Measured on the next turn: a widget loaded by the fit must not change the fit in the same pass.
    Connections { target: loader; function onItemChanged() { if (m.vertical) Qt.callLater(m.measure) } }
    Connections {
        target: loader.item
        ignoreUnknownSignals: true
        function onImplicitHeightChanged() { if (m.vertical) Qt.callLater(m.measure) }
    }
    Binding {
        target: loader.item
        property: "vertical"
        value: m.vertical
        when: loader.item !== null && loader.item !== undefined && ("vertical" in loader.item)
    }
    // W34: the mod's panel grows out of its widget (IslandGeom's origins; top and bottom hosts).
    AnchorReport { target: m; key: "mod:" + m.mod + ":" + m.name; output: m.output; enabled: m.anchored && !m.vertical }
    HoverHandler { id: hover }
    PeekSource {
        target: m
        source: m.peekSource
        output: m.output
        hovered: hover.hovered
        focused: loader.item !== null && loader.item.activeFocus === true
    }
    readonly property var qsw: Window.window ? QsWindow.window : null
    readonly property string placeKey: peekSource !== "" && qsw ? [m.output, m.edge, Light.originOf(qsw).x, Light.originOf(qsw).y].join("|") : ""
    onPlaceKeyChanged: if (placeKey !== "") { var o = Light.originOf(qsw); Peeks.place(peekSource, m.output, m.edge, o.x, o.y) }
    Component.onDestruction: if (peekSource !== "") Peeks.unplace(peekSource, m.output)
}
