import QtQuick
import "../../core"
import "../expanded"
import ".."

// A control's own page (W71, I475 3; docs/ux/control-centre-modules.md): what a click on a control's module opens when the
// control has no richer page — keep awake, dark mode. Small and complete: the back key and the control's name; its switch
// with the value in effect under its name (drawn off and inert while the control cannot be used, and why, once: Shōjiki);
// the request's "Changing…" or its refusal with Retry; what the page adds (`extra`); the control's options from the schema
// (ModuleOptions, as its menu lists them); and a link to its Settings page. Keys: the back key first, then Tab through the
// switch, the options and the link; Esc and Left are the card's (QuickPanel).
Column {
    id: cp
    width: parent.width
    spacing: Theme.gap
    property var ctl: null
    // The module ids whose schema rows the page lists (the control's own, by default) and keys it leaves out.
    property var optionIds: ctl ? [ctl.mid] : []
    property var optionSkip: []
    default property alias extra: more.data
    signal backRequested()

    function focusFirst() { header.forceActiveFocus() }

    PageHeader {
        id: header
        title: cp.ctl ? cp.ctl.label : ""
        backName: I18n.tr("island.quick.back")
        onBack: cp.backRequested()
    }
    Row {
        visible: cp.ctl !== null && cp.ctl.toggles && cp.ctl.req !== null
        width: cp.width
        spacing: Theme.gap
        Column {
            width: parent.width - sw.width - Theme.gap
            anchors.verticalCenter: sw.verticalCenter
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                width: parent.width
                elide: Text.ElideRight
                color: cp.ctl && cp.ctl.inert ? Theme.dim : Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: cp.ctl ? cp.ctl.label : ""
            }
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                visible: !(cp.ctl && cp.ctl.inert)
                width: parent.width
                elide: Text.ElideRight
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: cp.ctl ? cp.ctl.value : ""
            }
        }
        ToggleSwitch {
            id: sw
            checked: cp.ctl !== null && cp.ctl.on && !cp.ctl.inert
            enabled: cp.ctl !== null && !cp.ctl.inert && !cp.ctl.busy
            label: cp.ctl ? cp.ctl.label : ""
            onToggled: on => { if (cp.ctl !== null && cp.ctl.on !== on) cp.ctl.toggle() }
        }
    }
    // Why it cannot be used now (its reason, or who holds it), once, under the switch it explains.
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        visible: cp.ctl !== null && cp.ctl.inert
        width: cp.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: cp.ctl ? cp.ctl.stateText : ""
    }
    StateLine {
        width: cp.width
        req: cp.ctl ? cp.ctl.req : null
        pendingText: cp.ctl ? cp.ctl.pendingText : ""
    }
    Column {
        id: more
        width: cp.width
        spacing: Theme.gap
        visible: children.length > 0
    }
    ModuleOptions {
        width: cp.width
        mids: cp.optionIds
        skip: cp.optionSkip
    }
    Button {
        visible: cp.ctl !== null && cp.ctl.settingsPage !== ""
        label: I18n.tr("quick.page.settings")
        onClicked: Store.act("settings.open", { page: cp.ctl.settingsPage }, function () {})
    }
}
