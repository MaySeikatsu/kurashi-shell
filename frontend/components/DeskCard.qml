import QtQuick
import qs.core

// The desk's card shape for a mod's `desk:<name>` (as Desktop.qml draws its core cards, K43): a Block with the panel's
// padding, the surface fill and a hairline in flat chrome. Children go into the padded body; the card's height follows
// them. One place (rule 10): the tasks, calendar and weather mods' cards use it.
Block {
    id: card
    default property alias body: inner.data
    height: inner.childrenRect.height + 2 * Theme.pad + 2 * inset + Theme.shadowDy
    implicitHeight: height
    radius: Theme.rWidget
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
