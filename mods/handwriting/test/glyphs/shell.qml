import QtQuick
import Quickshell

// Every letter of a font, as the shell's text draws them (distance fields, at a size a bar uses and a size a title uses): what
// frontend text does to a font, in a process of its own, so a font that takes Qt down shows here. See ../../test-outlines.sh.
ShellRoot {
    FontLoader { id: fl; source: "file://" + Quickshell.env("GLYPHS_FONT") }
    FloatingWindow {
        visible: true
        implicitWidth: 1400
        implicitHeight: 500
        color: "white"
        Flow {
            anchors.fill: parent
            spacing: 8
            Repeater {
                model: Quickshell.env("GLYPHS_CHARS").split("")
                Text { required property string modelData; text: modelData; font.family: fl.name; font.pixelSize: 15; renderType: Text.QtRendering }
            }
            Repeater {
                model: Quickshell.env("GLYPHS_CHARS").split("")
                Text { required property string modelData; text: modelData; font.family: fl.name; font.pixelSize: 40; renderType: Text.QtRendering }
            }
        }
    }
}
