import QtQuick
import qs.core
import qs.components

// The selected picture and what applying it does (both pickers): the picture (unless the host shows it elsewhere: the
// appearance menu's live preview), its name and notes (light/dark half, the outputs showing it, monochrome), its palette
// chips, the theme diff — each role now and as this picture would make it, in the chosen scheme —, and the actions in
// one wrapping row: the quiet choices (the theme switch, Dark, Light), Apply (the one accent fill), Wallpaper only, the
// look (★), Apply look. `side`: a column beside the grid (a wide picker: the picture, its name, the actions, then the
// notes and the diff, so the actions stay in view on a short card), else a row under it (the picture beside the notes,
// the actions under both).
Column {
    id: pp
    required property var host
    property bool side: false
    property bool showImage: true
    property bool showDiff: true        // the theme diff (the appearance menu's live preview shows the colours itself)
    property real fitHeight: 0          // beside the grid: the column's height (the picture shrinks to fit it)
    readonly property var row: host.selectedRow
    spacing: Theme.gap

    // The notes, the palette chips, the diff and its caption (beside the picture, or under the actions).
    component Details: Column {
        required property var pane
        spacing: 4
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            visible: text !== ""
            text: {
                var r = pane.row
                if (!r) return ""
                var bits = []
                if (r.pair) bits.push(I18n.tr("mod-wallpaper.pair." + r.pair.role))
                if (r.on && r.on.length > 0) bits.push(I18n.tr("mod-wallpaper.on") + " " + r.on.join(", "))
                if (r.mono === true) bits.push(I18n.tr("mod-wallpaper.mono.warning"))
                return bits.join(" · ")
            }
        }
        Row {
            spacing: Theme.xs
            visible: pane.row !== null && pane.row.palette !== undefined
            Repeater {
                model: pane.row && pane.row.palette ? pane.row.palette : []
                delegate: Rectangle {
                    required property string modelData
                    width: 14
                    height: 14
                    radius: 3
                    color: modelData
                    border.width: 1
                    border.color: Theme.outline
                }
            }
        }
        // The theme diff: each role now (left) and as this picture would make it (right). Swatches are 18 px with their
        // role under them (I83: readable); the row wraps when the room is narrow. Not while the theme switch is off:
        // nothing would change.
        Flow {
            width: parent.width
            spacing: Theme.gap
            visible: pane.showDiff && pane.host.withTheme
            Item {
                width: headText.implicitWidth
                height: 34
                Text {
                    id: headText
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr("mod-wallpaper.theme.diff")
                }
            }
            Repeater {
                model: [
                    { role: "accent", label: "mod-wallpaper.role.accent", now: "color.accent" },
                    { role: "surface", label: "mod-wallpaper.role.surface", now: "color.surface" },
                    { role: "on_surface", label: "mod-wallpaper.role.text", now: "color.on_surface" },
                    { role: "secondary", label: "mod-wallpaper.role.secondary", now: "color.secondary" }
                ]
                delegate: Column {
                    id: pair
                    required property var modelData
                    readonly property string nowHex: String(pane.host.theme.tok(pair.modelData.now, "#777777"))
                    readonly property string nextHex: pane.host.themePreview && pane.host.themePreview.roles
                        ? String(pane.host.themePreview.roles[pair.modelData.role] || "") : ""
                    spacing: 2
                    Row {
                        spacing: 3
                        Rectangle {
                            width: 18; height: 18; radius: 4
                            color: pair.nowHex
                            border.width: 1; border.color: Theme.outline
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.dim
                            font.pixelSize: Theme.fsCaption
                            text: "→"
                        }
                        Rectangle {
                            width: 18; height: 18; radius: 4
                            color: pair.nextHex !== "" ? pair.nextHex : "transparent"
                            border.width: 1; border.color: Theme.outline
                            opacity: pane.host.previewBusy ? 0.4 : 1
                        }
                    }
                    Text {
                        color: Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.tr(pair.modelData.label)
                    }
                }
            }
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            visible: pane.showDiff && pane.host.withTheme
            color: pane.host.previewError !== "" ? Theme.error : Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: {
                if (pane.host.previewError !== "") return I18n.tr(pane.host.previewError)
                if (pane.host.previewBusy || !pane.host.previewCurrent) return I18n.tr("mod-wallpaper.theme.previewing")
                return I18n.tr("mod-wallpaper.theme.axes")
            }
        }
    }
    component Name: Text {
        required property var pane
        elide: Text.ElideMiddle
        color: Theme.fg
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: pane.row ? pane.row.name : ""
    }

    Item {
        id: head
        width: pp.width
        readonly property real imgW: !pp.showImage ? 0 : (pp.side ? pp.width : Math.min(208, Math.round(pp.width * 0.34)))
        // Beside the grid the picture gives way first: it shrinks (16:9 kept, 72 px at least) so its name, the actions,
        // the notes and the theme diff fit the column's height; only below that does the column scroll.
        readonly property real sideH: Math.round(Math.max(72, Math.min(pp.width * 9 / 16,
            pp.fitHeight - sideName.height - actions.height - sideDetails.implicitHeight - 3 * Theme.gap)))
        height: pp.side ? img.height + Theme.gap + sideName.height : Math.max(img.height, info.implicitHeight)
        Image {
            id: img
            visible: pp.showImage
            Component.onCompleted: Light.addPicture(img, Window.window)
            Component.onDestruction: Light.removePicture(img)
            width: pp.side && pp.fitHeight > 0 ? Math.min(head.imgW, Math.round(height * 16 / 9)) : head.imgW
            // 16:9; beside the grid no taller than the column leaves for the rest (head.sideH)
            height: !pp.showImage ? 0 : pp.side && pp.fitHeight > 0 ? head.sideH : Math.round(head.imgW * 9 / 16)
            source: pp.showImage && pp.row && pp.row.thumb ? pp.host.fileUrl(pp.row.thumb) : ""
            sourceSize.width: pp.side ? 480 : 256
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: 1
                border.color: Theme.outline
                radius: Theme.rSm
            }
        }
        Name {
            id: sideName
            pane: pp
            visible: pp.side
            y: img.height + Theme.gap
            width: pp.width
        }
        // beside the picture (a row under the grid)
        Column {
            id: info
            visible: !pp.side
            x: pp.showImage ? head.imgW + Theme.gap : 0
            width: pp.width - x
            spacing: 4
            Name { pane: pp; width: parent.width }
            Details { pane: pp; width: parent.width }
        }
    }

    // The actions. Tab from the grid comes here (the theme switch first), Shift+Tab goes back (I32).
    Flow {
        id: actions
        width: pp.width
        spacing: Theme.xs
        PickButton {
            id: themeSwitch
            objectName: "wall-theme-switch"
            label: pp.host.withTheme ? I18n.tr("mod-wallpaper.theme.on") : I18n.tr("mod-wallpaper.theme.off")
            selected: pp.host.withTheme
            onActivated: pp.host.withTheme = !pp.host.withTheme
            Accessible.description: I18n.tr("mod-wallpaper.theme.switch")
        }
        PickButton {
            objectName: "wall-scheme-dark"
            visible: pp.host.withTheme
            label: I18n.tr("mod-wallpaper.scheme.dark")
            selected: pp.host.previewScheme === "dark"
            onActivated: pp.host.schemeChoice = "dark"
        }
        PickButton {
            objectName: "wall-scheme-light"
            visible: pp.host.withTheme
            label: I18n.tr("mod-wallpaper.scheme.light")
            selected: pp.host.previewScheme === "light"
            onActivated: pp.host.schemeChoice = "light"
        }
        Button {
            objectName: "wall-apply"
            label: pp.host.target === "" ? I18n.tr("mod-wallpaper.apply.all") : I18n.tr("mod-wallpaper.apply")
            primary: true
            enabled: pp.host.canUse(pp.row)
            onClicked: pp.host.applySelected(false, false, null)
        }
        Button {
            objectName: "wall-apply-only"
            visible: pp.host.withTheme
            label: I18n.tr("mod-wallpaper.apply.wallpaper_only")
            enabled: pp.host.canUse(pp.row)
            onClicked: pp.host.applySelected(false, true, null)
        }
        Button {
            objectName: "wall-look"
            label: pp.host.isLook(pp.row) ? I18n.tr("mod-wallpaper.favourite.remove") : I18n.tr("mod-wallpaper.favourite.add")
            enabled: pp.host.canUse(pp.row)
            onClicked: pp.host.toggleLook(pp.row)
        }
        Button {
            objectName: "wall-look-apply"
            // Shown for a saved look only: its stored image, scheme and variant go on together.
            visible: pp.host.lookOf(pp.row) !== null
            label: I18n.tr("mod-wallpaper.look.apply")
            enabled: pp.host.canUse(pp.row)
            onClicked: pp.host.applyLookOf(pp.row)
        }
    }
    // beside the grid: the notes and the diff after the actions
    Details { id: sideDetails; pane: pp; visible: pp.side; width: pp.width }
    readonly property Item firstAction: themeSwitch
}
