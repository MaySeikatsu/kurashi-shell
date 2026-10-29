import QtQuick

// The contract of a slider face (`[slots] slider`, W53.0a): track, fill and thumb for `value` (0..1), filling the
// slider; the slider keeps its input handling.
Item {
    property real value: 0
    property bool pressed: false
    property bool vertical: false
}
