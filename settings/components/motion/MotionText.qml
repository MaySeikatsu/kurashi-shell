import QtQuick
import "../../core"
import ".."

// A line of the Motion page's own controls, set as every Settings text is (pixel looks hint fully, the family by script).
// `small` is the help size (fs − 2).
Label {
    property bool small: false
    wrapMode: Text.WordWrap
    font.pixelSize: small ? Theme.fs - 2 : Theme.fs
}
