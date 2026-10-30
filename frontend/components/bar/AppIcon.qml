import QtQuick
import Quickshell
import "../../core"
import ".."
import "appicon.js" as AppIcons

// A window's app icon (W36, docs/ux/window-list.md): the picture from the chain in appicon.js, else the app's first
// letter, else (no app id at all) a generic window symbol. `kind` says which one is drawn (the tests read it).
Item {
    id: ai
    property string appId: ""
    property var entry: null
    property color color: Theme.fg
    // The picture's share of the box (the rest is the tile's margin).
    property real fill: 1
    readonly property string src: AppIcons.iconSource(Quickshell, entry, appId)
    readonly property string kind: img.visible ? "image" : (appId === "" && !entry ? "generic" : "letter")

    Image {
        id: img
        anchors.centerIn: parent
        width: Math.round(ai.width * ai.fill)
        height: width
        source: ai.src
        sourceSize: Qt.size(64, 64)
        asynchronous: true
        visible: ai.src !== "" && status === Image.Ready
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        anchors.centerIn: parent
        visible: ai.kind === "letter"
        color: ai.color
        font.pixelSize: Math.max(9, Math.round(ai.height * 0.5))
        font.weight: Theme.wBold
        font.family: Theme.fam(text, Theme.families)
        text: AppIcons.letterOf(ai.entry, ai.appId) || "?"
    }
    Icon {
        anchors.centerIn: parent
        visible: ai.kind === "generic"
        name: "web_asset"
        glyph: "▢"
        color: ai.color
        size: Math.max(10, Math.round(ai.height * 0.62))
    }
}
