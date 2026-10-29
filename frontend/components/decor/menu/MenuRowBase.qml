import QtQuick

// The contract of a menu row's background (`[slots] menu`, W53.0a): loaded under each row's content, filling it. A
// separator row draws the look's separator instead of a highlight.
Item {
    property bool highlighted: false
    property bool enabled: true
    property bool separator: false
    property bool checked: false
}
