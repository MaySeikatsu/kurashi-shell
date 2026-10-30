import QtQuick
import "../../core"
import ".."

// The status sentence on top of the card (docs/ux/quick-settings.md, Design 1): the values in effect in one line, each
// segment a link to its page, wrapping onto a second line when it must. `segments` is [{text, page}], made by QuickPanel.
// A segment is a Tab stop: Enter or a click opens its page; the focused one is underlined and ringed.
Flow {
    id: st
    property var segments: []
    signal opened(string page, var from)
    spacing: 0

    Repeater {
        model: st.segments
        delegate: Item {
            id: seg
            required property var modelData
            required property int index
            width: row.width + 6
            height: row.height + 2

            activeFocusOnTab: true
            Keys.onReturnPressed: st.opened(seg.modelData.page, seg)
            Keys.onEnterPressed: st.opened(seg.modelData.page, seg)
            Keys.onSpacePressed: st.opened(seg.modelData.page, seg)
            Accessible.role: Accessible.Link
            Accessible.name: seg.modelData.text

            // The separator follows its segment, so a wrapped line never starts with one.
            Row {
                id: row
                anchors.centerIn: parent
                spacing: 6
                Text {
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    antialiasing: !Theme.pixelType
                    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.fg
                    font.pixelSize: Theme.fs
                    font.underline: seg.activeFocus || hover.hovered
                    font.family: Theme.fam(text, Theme.families)
                    text: seg.modelData.text
                }
                Text {
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    antialiasing: !Theme.pixelType
                    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                    visible: seg.index < st.segments.length - 1
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.dim
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    text: "·"
                }
            }
            HoverHandler { id: hover }
            MouseArea {
                anchors.fill: parent
                onClicked: st.opened(seg.modelData.page, seg)
            }
            FocusRing {
                anchors.fill: parent
                shown: seg.activeFocus
                corner: Theme.rSm
            }
        }
    }
}
