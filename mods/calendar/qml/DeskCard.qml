import QtQuick
import qs.core
import qs.components

// The desk's card shape, copied from mods/tasks/qml/DeskCard.qml (as Desktop.qml draws its core cards, K43): a Block
// with the panel's padding, the surface fill and a hairline in flat chrome. Children go into the padded body.
Block {
    id: card
    default property alias body: inner.data
    height: inner.childrenRect.height + 2 * Theme.pad + 2 * inset + Theme.shadowDy
    implicitHeight: height
    radius: Theme.rLg + 4
    fill: Theme.surfaceAlpha
    flatBorder: Theme.outline
    Item {
        id: inner
        x: Theme.pad
        y: Theme.pad
        width: parent.width - 2 * Theme.pad
        height: childrenRect.height
    }
}
