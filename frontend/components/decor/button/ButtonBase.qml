import QtQuick

// The contract of a button face (`[slots] button`, W53.0a): drawn under the button's content, filling it (a DecorHost
// with slot "button" in the button; without the slot the button keeps its Block). `primary`: the default/accent button.
// W53.4: a face may name the ink its label takes (`ink`; transparent = the caller's own: on_accent on a primary).
Item {
    property bool pressed: false
    property bool hovered: false
    property bool checked: false
    property bool primary: false
    property color ink: "transparent"
}
