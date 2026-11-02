import QtQuick
import "../../core"
import ".."

// The Motion page's accessibility line (brief §8 item 6, §11): whether Reduce motion is on, with the link to it. While it
// is on, the profile is forced to `reduced` (short fades; the profile row says so), and the curves, forms and accents below
// wait until it is off. The daemon does not mark those rows yet (CONTRACT-CHANGE, W59.6), so the page says it here, once.
Row {
    id: ra
    signal openKey(string key)
    readonly property bool on: { Store.config; return Store.valueOf("a11y.reduce_motion", "") === true }
    objectName: "motion-a11y:" + (ra.on ? "on" : "off")
    spacing: Theme.gap

    MotionText {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, (ra.parent ? ra.parent.width : 600) - link.width - Theme.gap)
        small: !ra.on
        color: ra.on ? Theme.fg : Theme.dim
        text: (ra.on ? "⊘ " : "") + I18n.tr(ra.on ? "motion.ui.a11y.on" : "motion.ui.a11y.off")
    }
    LinkText {
        id: link
        anchors.verticalCenter: parent.verticalCenter
        text: I18n.tr("settings.ui.open")
        onActivated: ra.openKey("a11y.reduce_motion")
    }
}
