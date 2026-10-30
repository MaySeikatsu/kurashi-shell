import QtQuick
import Quickshell
import "../../core"
import ".."

// One clipboard history row (`;`, W26; docs/ux/launcher.md): text shows two lines, an image its thumbnail (the daemon
// decodes it once into the cache when this row asks — rows exist only while visible, so only visible images are ever
// decoded, Ma), a pin marks a pinned entry. Text from the clipboard is always plain text, never markup.
Item {
    id: cr
    property var entry: ({})
    property bool selected: false
    // The cached thumbnail's path; "" while unknown, "!" when there is none (decoding refused or failed).
    property string thumb: ""
    signal wantThumb()
    readonly property bool isImage: !!entry.image
    readonly property bool failed: thumb === "!"
    readonly property color ink: selected ? Theme.fgOnSelected : Theme.fg
    // K61 (docs/ux/texture.md "Controls"): the lead tile of a text entry is opaque and carries the relief over its glyph; a
    // thumbnail is a picture and never does. Only in a window that shares its sheet (Relief makes its own otherwise).
    readonly property var qsw: Window.window ? QsWindow.window : null
    readonly property bool shared: !!(qsw && qsw.tileSheet)

    Component.onCompleted: if (isImage && thumb === "") wantThumb()

    Item {
        id: lead
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -Theme.shadowDy / 2
        width: cr.isImage ? 84 : 30
        height: cr.isImage ? 56 : 30
        Rectangle {
            id: leadTile
            anchors.fill: parent
            radius: Theme.rSm
            color: Theme.surface
            border.width: Theme.outlineW > 0 ? Theme.outlineW : 1
            border.color: Theme.outlineW > 0 ? Theme.outlineColor : Theme.outline
            visible: !img.visible
            Icon {
                anchors.centerIn: parent
                name: cr.isImage ? (cr.failed ? "hide_image" : "image") : (cr.entry.binary ? "draft" : "content_paste")
                glyph: cr.isImage ? "▣" : "⎘"
                color: Theme.dim
            }
            Loader {
                active: Theme.texControls && cr.shared && !img.visible
                anchors.fill: parent
                anchors.margins: leadTile.border.width
                sourceComponent: Relief { anchors.fill: parent; radius: Math.max(0, leadTile.radius - leadTile.border.width) }
            }
        }
        Image {
            id: img
            anchors.fill: parent
            source: cr.thumb !== "" && !cr.failed ? "file://" + cr.thumb : ""
            sourceSize: Qt.size(168, 112)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
            visible: status === Image.Ready
        }
    }
    Column {
        anchors { left: lead.right; leftMargin: Theme.gap + 2; right: side.left; rightMargin: 8
                  verticalCenter: lead.verticalCenter }
        spacing: 2
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            maximumLineCount: cr.isImage ? 1 : 2
            elide: Text.ElideRight
            color: cr.ink
            font.pixelSize: Theme.fs
            font.weight: cr.selected ? Theme.wBold : Theme.wMedium
            font.family: Theme.fam(text, Theme.families)
            text: cr.entry.binary ? I18n.tr("launcher.clip.binary") + " · " + (cr.entry.name || "") : (cr.entry.name || "")
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            width: parent.width
            visible: cr.isImage
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.dim
            font.pixelSize: Theme.fs - 2
            font.family: Theme.fam(text, Theme.families)
            text: (cr.entry.generic || "") + (img.visible ? ""
                : " · " + I18n.tr(cr.failed ? "launcher.clip.no_preview" : "launcher.clip.loading"))
        }
    }
    // A pinned entry's pin, and what Enter does on the selected row.
    Row {
        id: side
        anchors { right: parent.right; rightMargin: 12; verticalCenter: lead.verticalCenter }
        spacing: 8
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: !!cr.entry.pinned
            name: "push_pin"
            glyph: "●"
            filled: true
            size: Theme.fs + 2
            color: Theme.accent
            Accessible.ignored: false
            Accessible.name: I18n.tr("launcher.clip.pinned")
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            anchors.verticalCenter: parent.verticalCenter
            visible: cr.selected
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: "↵ " + I18n.tr("launcher.copy")
        }
    }
}
