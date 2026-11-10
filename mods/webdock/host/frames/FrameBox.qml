import QtQuick

// A box of a page frame in the caller's RoundBox (the look's corners: round, or squircle under `shape.corner`), handed
// in as a component (`box`) so these frames resolve in the web host and in the shell alike, each with its own RoundBox;
// without one a Rectangle. Same radius, colour and border as a Rectangle.
Loader {
    id: fb
    property Component box: null
    property real radius: 0
    property color color: "transparent"
    property real borderWidth: 0
    property color borderColor: "transparent"
    sourceComponent: box ? box : plain
    onLoaded: {
        item.radius = Qt.binding(function () { return fb.radius })
        item.color = Qt.binding(function () { return fb.color })
        item.border.width = Qt.binding(function () { return fb.borderWidth })
        item.border.color = Qt.binding(function () { return fb.borderColor })
    }
    property Component plain: Component { Rectangle { antialiasing: true } }
}
