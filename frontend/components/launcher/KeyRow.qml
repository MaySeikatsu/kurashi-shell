import QtQuick
import "../../core"
import ".."

// One row of the keybind cheat sheet (`?`, W26; DMS's KeybindsModal and niri's own hotkey overlay: the label on the
// left, the keys as caps on the right): a group header (`keygroup`) or a bind (`key`). Read-only. The selected row also
// names the compositor action it runs, so the label never hides what the key does (Shōjiki).
Item {
    id: kr
    property var entry: ({})
    property bool selected: false
    readonly property bool header: entry.kind === "keygroup"

    Text {
        visible: kr.header
        x: 10
        anchors { bottom: parent.bottom; bottomMargin: 5 }
        color: Theme.accent
        font.pixelSize: Theme.fsCaption
        font.weight: Theme.wBold
        font.letterSpacing: 0.6
        font.family: Theme.fam(text, Theme.families)
        text: kr.entry.name || ""
    }
    Row {
        visible: !kr.header
        x: 12
        width: parent.width - caps.width - 34
        anchors { verticalCenter: parent.verticalCenter; verticalCenterOffset: -Theme.shadowDy / 2 }
        spacing: 8
        Text {
            id: label
            width: Math.min(implicitWidth, parent.width)
            elide: Text.ElideRight
            textFormat: Text.PlainText
            color: kr.selected ? Theme.fgOnSelected : Theme.fg
            font.pixelSize: Theme.fs
            font.weight: kr.selected ? Theme.wBold : Theme.wMedium
            font.family: Theme.fam(text, Theme.families)
            text: kr.entry.name || ""
        }
        Text {
            visible: kr.selected && !!kr.entry.generic && kr.entry.generic !== kr.entry.name
            width: Math.max(0, parent.width - label.width - parent.spacing)
            anchors.baseline: label.baseline
            elide: Text.ElideRight
            textFormat: Text.PlainText
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: kr.entry.generic || ""
        }
    }
    Row {
        id: caps
        visible: !kr.header
        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter; verticalCenterOffset: -Theme.shadowDy / 2 }
        spacing: 4
        Repeater {
            model: kr.header ? [] : (kr.entry.keys || [])
            delegate: Block {
                id: cap
                required property var modelData
                height: 24 + Theme.shadowDy
                width: Math.max(26, capText.implicitWidth + 14)
                radius: Theme.rSm
                ringScale: 0.4
                softScale: 0.25
                animate: false
                fill: Theme.containerHigh
                flatBorder: Theme.outline
                Text {
                    id: capText
                    anchors.centerIn: parent
                    color: Theme.fg
                    font.pixelSize: Theme.fsCaption
                    font.weight: Theme.wBold
                    font.family: Theme.fam(text, Theme.families)
                    text: cap.modelData
                }
            }
        }
    }
}
