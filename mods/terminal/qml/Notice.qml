import QtQuick
import qs.core
import qs.components

// What a place's well says when the terminal's text is not there (docs/ux/terminal.md "States"): the host is missing,
// starting, stopped (crashed or failed: a press restarts it), the last shell exited, or another place shows the terminal
// (a press brings it here). A directory that could not be opened is said along the well's foot. Nothing is drawn while
// the terminal shows here: the host's text lies over the well then.
Item {
    id: n
    property var doc: ({})
    property string place: "dropdown"
    readonly property var host: doc.host || ({})
    readonly property string state: String(host.state || "off")
    readonly property bool crashed: host.crashed === true || state === "failed"
    readonly property bool hasTabs: (doc.tabs || []).length > 0
    readonly property string shownIn: doc.shown_in || ""
    readonly property bool elsewhere: shownIn !== "" && shownIn !== place && (doc.open || []).indexOf(place) >= 0
    // The state that holds, most pressing first.
    readonly property string what: state === "missing" ? "missing"
        : crashed ? "crashed"
        : elsewhere ? "elsewhere"
        : !hasTabs ? "exited"
        : state !== "ready" ? "starting"
        : ""
    readonly property string action: what === "crashed" ? "terminal.restart"
        : what === "elsewhere" ? "terminal.bring"
        : what === "exited" ? "terminal.new_tab" : ""

    Column {
        visible: n.what !== ""
        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * Theme.pad, 520)
        spacing: Theme.gap
        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: n.what === "crashed" ? "refresh" : "terminal"
            glyph: "›_"
            color: n.what === "crashed" || n.what === "missing" ? Theme.error : Theme.dim
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: n.what === "" ? "" : I18n.tr("terminal.state." + n.what)
                .replace("{place}", I18n.tr("terminal.place." + n.shownIn))
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
        }
        Text {
            visible: n.what === "crashed" && !!n.host.detail
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: String(n.host.detail || "")
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
        }
        Button {
            visible: n.action !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            label: n.action === "" ? "" : I18n.tr("terminal.press." + n.what)
            primary: true
            onClicked: Store.act(n.action, n.action === "terminal.bring" ? { where: n.place } : {})
        }
    }
    // Enter does what the button says (the well holds no terminal now, so the keys are not a shell's).
    Keys.onReturnPressed: if (action !== "") Store.act(action, action === "terminal.bring" ? { where: place } : {})

    // A favourite or a typed directory that is not one (Shōjiki: said, never a silent `cd`).
    Text {
        visible: !!n.doc.notice
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.xs
        anchors.horizontalCenter: parent.horizontalCenter
        text: n.doc.notice ? I18n.tr(String(n.doc.notice.key)).replace("{path}", String(n.doc.notice.path || "")) : ""
        color: Theme.error
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
    }
}
