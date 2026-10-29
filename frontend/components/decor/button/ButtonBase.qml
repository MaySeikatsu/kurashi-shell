import QtQuick

// The contract of a button face (`[slots] button`, W53.0a): drawn under the button's content, filling it (a DecorHost
// with slot "button" in the button; without the slot the button keeps its Block). `primary`: the default/accent button.
Item {
    property bool pressed: false
    property bool hovered: false
    property bool checked: false
    property bool primary: false
}
