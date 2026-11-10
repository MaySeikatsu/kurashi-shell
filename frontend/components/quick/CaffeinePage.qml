import QtQuick
import "../../core"
import ".."

// Keep awake's page (W71, I475 3): its switch (svc.idle `caffeine`), who else keeps the screen awake now (the inhibitors the
// idle service reports, each by its name and why), and its options — idle actions at all, stay awake while media plays — as
// its menu lists them. Without an idle service, or a compositor that reports no idle time, the switch is off and inert and
// the reason stands under it (ControlPage).
ControlPage {
    id: kp
    readonly property var d: Store.docs["svc.idle"] || ({})
    readonly property var others: d.inhibitors || []
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        visible: kp.others.length > 0
        width: kp.width
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("quick.caffeine.others")
    }
    Repeater {
        model: kp.others
        delegate: Text {
            required property var modelData
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            antialiasing: !Theme.pixelType
            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
            width: kp.width
            wrapMode: Text.WordWrap
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: String(modelData.who || "") + (modelData.why ? " — " + String(modelData.why) : "")
        }
    }
}
