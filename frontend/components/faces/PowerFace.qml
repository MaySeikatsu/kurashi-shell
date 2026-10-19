import QtQuick
import "../../core"

// power (K30): the charger in or out, and the battery low or critical (the same face, kind `battery`). The pill
// says the percent svc.power reports and the source (▮ on battery, ⚡ on AC). The daemon's line with the time left
// or to full is the peek, not the pill (a transient face is glanced at, not read). Without a percent it says what
// the face is, never a guessed number (Shōjiki). On a side bar: the glyph over the bare percent.
FaceBase {
    id: f
    // The daemon's peek line for `power`; shown only when no percent is known.
    property string line: ""
    readonly property var d: Store.docs["svc.power"] || ({})
    readonly property bool onBattery: d.on_battery === true
    readonly property bool hasPct: typeof d.percent === "number"
    readonly property string full: f.hasPct ? Math.round(f.d.percent) + " %" : (f.line !== "" ? f.line : I18n.tr("island.face.power"))
    Watch { doc: "svc.power"; active: f.live }

    wantW: row.implicitWidth
    wantH: col.implicitHeight
    Row {
        id: row
        visible: !f.vertical
        anchors.centerIn: parent
        spacing: Theme.gap - 2
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.accent
            font.pixelSize: Theme.fs
            // U+FE0E: text presentation, so the glyph does not turn into a coloured emoji.
            text: f.onBattery ? "▮" : "⚡︎"
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: f.full
        }
    }
    Column {
        id: col
        visible: f.vertical
        anchors.centerIn: parent
        Accessible.role: Accessible.StaticText
        Accessible.name: f.full
        Text {
            Accessible.ignored: true
            color: Theme.accent
            font.pixelSize: Theme.fs
            text: f.onBattery ? "▮" : "⚡︎"
        }
        Text {
            Accessible.ignored: true
            visible: f.hasPct
            color: Theme.fg
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: f.hasPct ? Math.round(f.d.percent) : ""
        }
    }
}
