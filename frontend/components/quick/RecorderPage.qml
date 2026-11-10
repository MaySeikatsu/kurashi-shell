import QtQuick
import Quickshell
import "../../core"
import "../expanded"
import ".."

// The recorder's card (W71 f, I475 6; docs/ux/control-centre-modules.md "The recorder"): what the bar's `recorder` button
// opens. A big round key that starts a recording (the error red, a white dot: a camera's) and, while one runs, stops it (a
// white square) with the running time beside it; which screen (one choice per output when there are several); the
// desktop's sound and the module's click (the schema's rows, ModuleOptions); where the file goes; the last recording.
// What the daemon cannot do yet (a region, a window, the microphone) is one dim line, not dead keys (Shōjiki;
// CONTRACT-CHANGE 716). States: no recorder program (the key inert, the reason under it), starting, recording, failed
// (the reason and Retry), no service at all. Keys: the back key, the record key (Enter or Space), the screens, the
// options, Settings. The running time ticks once a second only while this card shows a recording (RecordControl).
Column {
    id: rp
    width: parent.width
    spacing: Theme.gap
    property var ctl: null
    property var optionIds: ["recorder"]
    signal backRequested()

    function focusFirst() { header.forceActiveFocus() }

    readonly property var d: Store.docs["svc.recorder"] || ({})
    readonly property bool recording: ctl !== null && ctl.recording
    readonly property bool canStart: ctl !== null && !ctl.inert && !ctl.busy
    // The screens: the shell's outputs by name; the first is chosen until the user picks another.
    readonly property var outputs: {
        var out = [], s = Quickshell.screens
        for (var i = 0; i < s.length; i++) out.push(String(s[i].name))
        return out
    }
    property string chosen: ""
    readonly property string output: chosen !== "" && outputs.indexOf(chosen) >= 0 ? chosen : (outputs.length > 0 ? outputs[0] : "")
    readonly property var cfg: (Store.docs["config"] || {}).values || ({})
    readonly property string folder: {
        var e = cfg["recorder.directory"]
        var v = e && e.value !== undefined ? String(e.value) : ""
        return v !== "" ? v : I18n.tr("quick.recorder.videos")
    }
    readonly property string lastFile: String(d.file || "")
    function press() {
        if (ctl === null) return
        if (recording) { ctl.toggle(); return }
        if (!canStart) return
        ctl.output = rp.outputs.length > 1 ? rp.output : ""
        ctl.toggle()
    }

    PageHeader {
        id: header
        title: I18n.tr("power.quick.record")
        backName: I18n.tr("island.quick.back")
        onBack: rp.backRequested()
    }
    // The record key and what it does now.
    Row {
        width: rp.width
        spacing: Theme.pad
        Item {
            id: key
            width: 56
            height: 56
            activeFocusOnTab: rp.recording || rp.canStart
            Keys.onReturnPressed: rp.press()
            Keys.onEnterPressed: rp.press()
            Keys.onSpacePressed: rp.press()
            Accessible.role: Accessible.Button
            Accessible.name: rp.recording ? I18n.tr("quick.recorder.stop").replace("{t}", rp.ctl ? rp.ctl.elapsed : "")
                : I18n.tr("quick.recorder.start")
            opacity: rp.recording || rp.canStart ? 1 : 0.4
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Theme.error
                border.width: 3
                border.color: Qt.alpha(Theme.fg, 0.25)
                scale: keyTap.pressed ? 0.94 : 1
                // idle: a white dot (record); recording: a white rounded square (stop)
                Rectangle {
                    anchors.centerIn: parent
                    width: rp.recording ? 18 : 22
                    height: width
                    radius: rp.recording ? 4 : width / 2
                    color: "white"
                }
            }
            TapHandler { id: keyTap; onTapped: rp.press() }
            FocusRing {
                anchors.fill: parent
                anchors.margins: -3
                shown: key.activeFocus
                corner: width / 2
            }
        }
        Column {
            anchors.verticalCenter: key.verticalCenter
            width: rp.width - key.width - Theme.pad
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                width: parent.width
                elide: Text.ElideRight
                color: rp.recording ? Theme.error : Theme.fg
                font.pixelSize: rp.recording ? Theme.fsTitle + 2 : Theme.fs
                font.weight: Theme.wBold
                font.family: Theme.fam(text, Theme.families)
                text: rp.recording && rp.ctl ? rp.ctl.elapsed
                    : rp.ctl && rp.ctl.busy ? rp.ctl.pendingText
                    : I18n.tr("quick.recorder.idle")
            }
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: rp.ctl && rp.ctl.inert ? rp.ctl.stateText
                    : rp.recording ? I18n.tr("quick.recorder.recording_hint")
                    : I18n.tr("quick.recorder.idle_hint")
            }
        }
    }
    StateLine {
        width: rp.width
        req: rp.ctl ? rp.ctl.req : null
        pendingText: rp.ctl ? rp.ctl.pendingText : ""
    }
    // What is recorded: the screen (one choice per output when there are several).
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        width: rp.width
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("quick.recorder.what")
    }
    Repeater {
        model: rp.outputs.length > 1 ? rp.outputs : []
        delegate: ChoiceRow {
            required property string modelData
            width: rp.width
            radio: true
            title: modelData
            checked: rp.output === modelData
            inert: rp.recording || rp.output === modelData
            onActivated: rp.chosen = modelData
        }
    }
    ChoiceRow {
        visible: rp.outputs.length <= 1
        width: rp.width
        radio: true
        checked: true
        inert: true
        title: I18n.tr("quick.recorder.this_screen")
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        width: rp.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("quick.recorder.not_yet")
    }
    // The desktop's sound and the module's click: the schema's rows for the module.
    ModuleOptions {
        width: rp.width
        mids: rp.optionIds
    }
    // Where it goes, and the last recording.
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        width: rp.width
        wrapMode: Text.WrapAnywhere
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("quick.recorder.folder").replace("{dir}", rp.folder)
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        visible: rp.lastFile !== "" && !rp.recording
        width: rp.width
        wrapMode: Text.WrapAnywhere
        color: Theme.fg
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("quick.recorder.last").replace("{file}", rp.lastFile.split("/").pop())
    }
    Button {
        label: I18n.tr("quick.page.settings")
        onClicked: Store.act("settings.open", { page: "power" }, function () {})
    }
}
