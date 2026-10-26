import QtQuick
import "../core"

// Settings › Layout: a bar with no modules in any of its zones is an empty strip, and the page says so under the edge's header
// (UX brief, docs/ux/layout.md "States": "empty bar zone … Settings warns"). The line uses the page's problem style: the error
// colour, and a glyph, so the warning is not colour alone. Whether the bar is empty is the daemon's (Store.barIsEmpty, the
// resolved zones of runtime.layout); the document is watched while the note is shown (Ma).
Item {
    id: note
    property string edge: ""
    property string output: ""
    readonly property bool empty: { Store.docs; return Store.barIsEmpty(note.edge, note.output) }
    objectName: "empty-bar:" + note.edge
    visible: note.empty
    width: parent.width
    height: visible ? warning.implicitHeight + Theme.gap * 2 : 0
    Component.onCompleted: Store.watch("runtime.layout")
    Component.onDestruction: Store.unwatch("runtime.layout")

    Text {
        id: warning
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        wrapMode: Text.WordWrap
        color: Theme.error
        font.pixelSize: Theme.fs - 2
        font.family: Theme.fam(text, Theme.families)
        text: "⚠ " + I18n.tr("settings.layout.empty_bar")
    }
}
