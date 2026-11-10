import QtQuick
import "../core"

// Icon tint (session 26, reworked session 27): the `layer.effect` an icon's Image takes while a tint is on
// (shaders/icon_tint.frag). `mode`: "ink" the text's colour, a picture's drawing kept as lighter and denser ink; "tones"
// the icon's lightness mapped onto the palette's colours, dark to light; "palette" the palette's colours: on a logo
// (`sectors`) as four quarters, the PS2 look's sweep, on an app icon each part by its hue, so its drawing stays.
// The stops: `colors` when given (the console's four), else the accent, secondary and tertiary and the text's colour, as
// the palette has them (its most used colours), ordered dark to light for "tones" and for the greys of "palette".
ShaderEffect {
    id: tint
    property string mode: "ink"
    property color ink: Theme.fg
    // A logo: "palette" as quarters. An app icon: by hue.
    property bool sectors: false
    property var colors: null
    readonly property var stops: {
        if (colors && colors.length === 4) return colors
        var l = [Theme.accent, Theme.secondary, Theme.tertiary, Theme.fg]
        if (mode === "palette" && sectors) return l
        function lum(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
        return l.slice().sort(function (a, b) { return lum(a) - lum(b) })
    }
    readonly property vector4d uMode: Qt.vector4d(mode === "ink" ? 1 : (mode === "palette" ? (sectors ? 2 : 4) : (mode === "tones" ? 3 : 0)),
        stops.length, 0, 0)
    readonly property vector4d uInk: Qt.vector4d(ink.r, ink.g, ink.b, 1)
    readonly property vector4d uStop0: Qt.vector4d(stops[0].r, stops[0].g, stops[0].b, 1)
    readonly property vector4d uStop1: Qt.vector4d(stops[1].r, stops[1].g, stops[1].b, 1)
    readonly property vector4d uStop2: Qt.vector4d(stops[2].r, stops[2].g, stops[2].b, 1)
    readonly property vector4d uStop3: Qt.vector4d(stops[3].r, stops[3].g, stops[3].b, 1)
    fragmentShader: Qt.resolvedUrl("../shaders/icon_tint.frag.qsb")
}
