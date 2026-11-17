import QtQuick
import qs.core

// Where a picture goes (docs/ux/wallpaper.md "Per output, honestly"): every output, one output (its chip shows the
// picture it has now), and Span, greyed and saying it is not available yet (I83). Shown only with more than one output:
// with one, "All outputs" and the output are the same choice.
ChipRow {
    id: targets
    visible: host !== null && host.outputNames.length > 1
    Accessible.role: Accessible.Grouping
    PickButton {
        objectName: "wall-target-all"
        label: I18n.tr("mod-wallpaper.target.all")
        selected: targets.host.target === ""
        onActivated: targets.host.target = ""
    }
    Repeater {
        model: targets.host.outputNames
        delegate: PickButton {
            required property string modelData
            readonly property var out: targets.host.outputs[modelData] || ({})
            objectName: "wall-target-" + modelData
            label: modelData
            selected: targets.host.target === modelData
            thumb: out.path ? targets.host.fileUrl(out.path) : ""
            onActivated: targets.host.target = modelData
        }
    }
    // Not focusable (nothing to choose); the reason is for assistive tech.
    PickButton {
        label: I18n.tr("mod-wallpaper.target.span") + " · " + I18n.tr("mod-wallpaper.target.span.short")
        enabled: false
        Accessible.description: I18n.tr("mod-wallpaper.target.span.reason")
    }
}
