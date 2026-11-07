import QtQuick
import qs.core
import qs.components

// The handwriting mod's bar widget (K102): a pen; a click opens the panel (ModWidget). Nothing runs behind it: it watches no
// document and draws once.
Item {
    required property var store
    required property var theme
    required property var i18n
    id: w
    property bool vertical: false
    implicitWidth: Theme.barH
    implicitHeight: Theme.barH
    Accessible.name: I18n.tr("mods.handwriting.widget")
    Icon {
        anchors.centerIn: parent
        name: "draw"
        color: Theme.fg
        size: Math.round(Theme.barH * 0.56)
    }
}
