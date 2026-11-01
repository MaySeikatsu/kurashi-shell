import QtQuick

// The contract of a menu row's background (`[slots] menu`, W53.0a): loaded under each row's content, filling it. A
// separator row draws the look's separator instead of a highlight.
Item {
    property bool highlighted: false
    property bool enabled: true
    property bool separator: false
    property bool checked: false
    // I332: where the row's label stands (px from the row's start, and its drawn width): a part that marks the label (an
    // underline) marks it there. -1 / 0: the caller does not say (the part keeps its own place).
    property real labelX: -1
    property real labelW: 0
}
