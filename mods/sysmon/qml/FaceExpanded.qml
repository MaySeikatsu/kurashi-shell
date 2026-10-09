import QtQuick
import "format.js" as F

// The expanded view of the trouble face (docs/ux/sysmon.md "Island face"): the trouble in words, then the
// panel's process list, so the culprit can be ended in place. It watches the processes only while it is open.
Column {
    id: view
    required property var store
    required property var theme
    required property var i18n

    readonly property var s: store.docs["mod.sysmon"]
    readonly property var trouble: s !== undefined ? s.trouble : undefined
    readonly property var procs: store.docs["mod.sysmon.procs"]

    function tr(key) {
        return i18n.tr(key)
    }

    width: parent ? parent.width : 400
    spacing: view.theme.gap

    Component.onCompleted: {
        store.watch("mod.sysmon")
        store.watch("mod.sysmon.procs")
    }
    Component.onDestruction: {
        store.unwatch("mod.sysmon")
        store.unwatch("mod.sysmon.procs")
    }

    Text {
        visible: view.trouble !== undefined
        width: view.width
        text: view.trouble !== undefined
            ? F.fill(view.tr("sysmon.face.expanded"), {kind: view.tr("sysmon.face.kind." + view.trouble.kind)})
            : ""
        color: view.theme.fg
        font.pixelSize: view.theme.fsTitle
        font.family: view.theme.fam(text, view.theme.families)
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }

    Text {
        visible: view.trouble !== undefined
        width: view.width
        text: view.trouble !== undefined && view.trouble.culprit !== undefined
            ? F.fill(view.tr("sysmon.face.culprit"), {name: view.trouble.culprit.name}) : ""
        color: view.theme.dim
        font.pixelSize: view.theme.fsLabel
        font.family: view.theme.fam(text, view.theme.families)
    }

    ProcessList {
        width: view.width
        store: view.store
        theme: view.theme
        i18n: view.i18n
        doc: view.procs
    }
}
