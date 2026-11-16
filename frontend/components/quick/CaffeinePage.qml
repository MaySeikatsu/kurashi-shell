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
    Label {
        visible: kp.others.length > 0
        width: kp.width
        dim: true
        font.pixelSize: Theme.fsCaption
        text: I18n.tr("quick.caffeine.others")
    }
    Repeater {
        model: kp.others
        delegate: Label {
            required property var modelData
            width: kp.width
            wrapMode: Text.WordWrap
            text: String(modelData.who || "") + (modelData.why ? " — " + String(modelData.why) : "")
        }
    }
}
