import QtQuick
import "../core"

// Generic renderer for a mod `ui` tree (row | column | text | icon). Recursive, no recompilation.
Item {
    id: n
    property var node: ({})
    property var wstate: ({})
    property color fg: "white"
    property int size: 13
    property var families: []

    implicitWidth: ld.item ? ld.item.implicitWidth : 0
    implicitHeight: ld.item ? ld.item.implicitHeight : 0

    readonly property var glyphs: ({ leaf: "❦", star: "★", heart: "♥", bell: "♪", music: "♪", sun: "☀", moon: "☾" })

    Loader {
        id: ld
        sourceComponent: n.node.type === "row" ? rowC : n.node.type === "column" ? colC
                       : n.node.type === "icon" ? iconC : textC
    }
    Component {
        id: rowC
        Row {
            spacing: 6
            Repeater {
                model: n.node.children || []
                delegate: Loader {
                    id: child
                    required property var modelData
                    source: "ModNode.qml"   // dynamic: QML forbids static self-instantiation
                    onLoaded: {
                        item.node = Qt.binding(() => child.modelData)
                        item.wstate = Qt.binding(() => n.wstate)
                        item.fg = Qt.binding(() => n.fg)
                        item.size = Qt.binding(() => n.size)
                        item.families = Qt.binding(() => n.families)
                    }
                }
            }
        }
    }
    Component {
        id: colC
        Column {
            spacing: 4
            Repeater {
                model: n.node.children || []
                delegate: Loader {
                    id: child
                    required property var modelData
                    source: "ModNode.qml"   // dynamic: QML forbids static self-instantiation
                    onLoaded: {
                        item.node = Qt.binding(() => child.modelData)
                        item.wstate = Qt.binding(() => n.wstate)
                        item.fg = Qt.binding(() => n.fg)
                        item.size = Qt.binding(() => n.size)
                        item.families = Qt.binding(() => n.families)
                    }
                }
            }
        }
    }
    Component {
        id: iconC
        Text {
            color: n.fg
            font.pixelSize: n.size + 2
            font.family: Theme.fam(text, n.families)
            text: n.glyphs[n.node.name] !== undefined ? n.glyphs[n.node.name] : ("[" + (n.node.name || "?") + "]")
        }
    }
    Component {
        id: textC
        Text {
            color: n.fg
            font.pixelSize: n.size
            font.family: Theme.fam(text, n.families)
            text: n.node.bind !== undefined ? String(n.wstate[n.node.bind] ?? "") : String(n.node.text ?? "")
        }
    }
}
