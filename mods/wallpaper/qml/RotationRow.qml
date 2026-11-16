import QtQuick
import qs.core

// Shuffle now (one picture at random on the target) · Rotate every Off / 15 / 30 / 60 min, and the configured interval
// when it is another · the order (In order / Shuffled, while rotating). The interval and order are the mod's settings,
// written at once (they are not part of the appearance menu's preview session).
ChipRow {
    id: rr
    Accessible.role: Accessible.Grouping
    PickButton {
        objectName: "wall-shuffle"
        label: I18n.tr("appearance-menu.wallpaper.shuffle")
        enabled: rr.host.backendUp && rr.host.libraryCount > 0
        onActivated: rr.host.shuffleNow()
    }
    Text {
        height: 28
        verticalAlignment: Text.AlignVCenter
        leftPadding: Theme.gap
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("appearance-menu.wallpaper.rotate")
    }
    Repeater {
        model: {
            var l = [0, 15, 30, 60]
            if (l.indexOf(rr.host.rotate) < 0) l.push(rr.host.rotate)
            return l
        }
        delegate: PickButton {
            required property int modelData
            objectName: "wall-rotate-" + modelData
            label: modelData === 0 ? I18n.tr("appearance-menu.wallpaper.rotate.off")
                : rr.host.tr2("appearance-menu.wallpaper.rotate.min", { n: modelData })
            selected: rr.host.rotate === modelData
            onActivated: rr.host.setRotate(modelData)
        }
    }
    PickButton {
        objectName: "wall-rotate-order"
        visible: rr.host.rotate > 0
        label: I18n.tr(rr.host.rotateOrder === "shuffle" ? "appearance-menu.wallpaper.order.shuffle" : "appearance-menu.wallpaper.order.name")
        selected: rr.host.rotateOrder === "shuffle"
        Accessible.description: I18n.tr("appearance-menu.wallpaper.order")
        onActivated: rr.host.setOrder(rr.host.rotateOrder === "shuffle" ? "alphabetical" : "shuffle")
    }
}
