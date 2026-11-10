import QtQuick
import "../../core"
import ".."

// A wide tile of the control centre (W71 d, I475 8): a whole row of `quick.tiles` — the sound level (`volume_level`: the
// slider, and the output under it, a link to the sound page), the display's brightness (`brightness_level`) or the session
// row (`session`: lock, suspend, the power menu). There by default, after the switch tiles; in the centre's edit mode a
// thing to arrange as they are (a drag moves it among the wide rows, its remove key or Delete takes it out, Alt with Up or
// Down moves it); otherwise its own controls work and are the Tab stops. A brightness row without a backlight is shown only
// while editing (where it says so): a card never draws a level it cannot set (Shōjiki).
Item {
    id: wt
    property string kind: ""
    property var audio: null            // AudioControl
    property var bright: null           // BrightnessControl
    property bool sessionOk: false
    property bool editing: false
    property Item dragArea: null
    property string intentOrigin: "qs:quick"
    signal removeRequested()
    signal dragTo(real ax, real ay)
    signal dragEnded()
    signal pageRequested(string page, Item from)
    readonly property bool isWide: true
    readonly property string mid: kind
    readonly property string label: I18n.tr("layout.module." + kind)
    readonly property bool shown: kind !== "brightness_level" || editing || (bright !== null && bright.ok)
    visible: shown
    implicitHeight: shown ? body.implicitHeight : 0
    height: implicitHeight
    // While editing, the whole row is one Tab stop (the edit's keys move it); otherwise its controls are.
    activeFocusOnTab: editing
    Accessible.role: Accessible.Grouping
    Accessible.name: label
    Accessible.description: editing ? I18n.tr("quick.edit.wide_hint") : ""

    Column {
        id: body
        width: wt.width
        spacing: Theme.xs
        LevelRow {
            visible: wt.kind === "volume_level"
            width: wt.width
            glyph: "♪"
            icon: wt.audio ? wt.audio.icon : ""
            value: wt.audio ? wt.audio.level : 0
            readout: wt.audio && wt.audio.ok ? wt.audio.value : ""
            unavailable: !(wt.audio && wt.audio.ok)
            a11y: I18n.tr("island.quick.level.volume")
            onMoved: v => Store.intent("audio.volume", v, wt.intentOrigin)
        }
        // The output device under its level: a link to the sound page (a Tab stop, Enter opens it).
        Item {
            id: chip
            width: wt.width
            height: visible ? 24 : 0
            visible: wt.kind === "volume_level" && !!wt.audio && wt.audio.ok && wt.audio.sinkName !== ""
            activeFocusOnTab: visible && !wt.editing
            Keys.onReturnPressed: wt.pageRequested("audio", chip)
            Keys.onEnterPressed: wt.pageRequested("audio", chip)
            Keys.onSpacePressed: wt.pageRequested("audio", chip)
            Accessible.role: Accessible.Button
            Accessible.name: wt.audio ? wt.audio.sinkName : ""
            Rectangle {
                id: pill
                x: 20 + Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                height: 22
                width: Math.min(pillText.implicitWidth + 2 * Theme.gap, chip.width - x)
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: Theme.outline
                Text {
                    id: pillText
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    antialiasing: !Theme.pixelType
                    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                    x: Theme.gap
                    width: pill.width - 2 * Theme.gap
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: wt.audio ? wt.audio.sinkName : ""
                }
            }
            MouseArea {
                anchors.fill: parent
                enabled: !wt.editing
                onClicked: wt.pageRequested("audio", chip)
            }
            FocusRing {
                anchors.fill: pill
                shown: chip.activeFocus
                corner: pill.radius
            }
        }
        LevelRow {
            visible: wt.kind === "brightness_level"
            width: wt.width
            glyph: "☼"
            icon: "light_mode"
            value: wt.bright ? wt.bright.level : 0
            // (no backlight: only seen while editing; the reason stands in the readout's place)
            readout: wt.bright && wt.bright.ok ? wt.bright.value : (wt.bright ? wt.bright.reason : "")
            unavailable: !(wt.bright && wt.bright.ok)
            a11y: I18n.tr("island.brightness.heading")
            onMoved: v => Store.intent("brightness.set", v, wt.intentOrigin)
        }
        QuickFooter {
            visible: wt.kind === "session"
            width: wt.width
            sessionOk: wt.sessionOk
        }
    }

    // Made only in edit mode: the drag over the whole row (its controls take no press then), and the remove key.
    Loader {
        active: wt.editing
        anchors.fill: parent
        z: 10
        sourceComponent: Item {
            MouseArea {
                id: drag
                anchors.fill: parent
                preventStealing: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onPressed: wt.forceActiveFocus()
                onPositionChanged: mouse => {
                    if (!pressed || wt.dragArea === null) return
                    var p = drag.mapToItem(wt.dragArea, mouse.x, mouse.y)
                    wt.dragTo(p.x, p.y)
                }
                onReleased: wt.dragEnded()
                onCanceled: wt.dragEnded()
            }
            Rectangle {
                width: 22
                height: 22
                radius: 11
                x: parent.width - width + 6
                y: -6
                color: rm.containsMouse ? Theme.error : Theme.containerHigh
                border.width: 1
                border.color: Theme.outline
                Icon {
                    anchors.centerIn: parent
                    name: "remove"
                    glyph: "−"
                    size: 16
                    color: rm.containsMouse ? Theme.surface : Theme.fg
                }
                MouseArea {
                    id: rm
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    onClicked: wt.removeRequested()
                }
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr("quick.edit.remove").replace("{name}", wt.label)
            }
        }
    }
    FocusRing {
        anchors.fill: parent
        shown: wt.activeFocus && wt.editing
        corner: Theme.rLg
    }
}
