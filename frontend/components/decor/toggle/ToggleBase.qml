import QtQuick

// The contract of a toggle face (`[slots] toggle`, W53.0a): a switch, a check box (9x, XP) or a gel switch for
// `checked`, filling the toggle; the toggle keeps its input handling.
Item {
    property bool checked: false
    property bool pressed: false
}
