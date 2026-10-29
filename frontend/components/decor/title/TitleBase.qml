import QtQuick
import "../../../core"

// The contract of a caption part (`[slots] title`, W53.0a): TitleHost sets these and listens to the signals. A part reads
// its numbers and colours from `Theme.decor("title.…")` (height, fill, fill_inactive, on, fill_dir, align, weight,
// close, buttons, radius) so one part serves several looks. It draws only buttons that act: `close` while `canClose`,
// and the names in `buttons` (the caller acts on `button(name)`). Static: paints once per size and colour.
Item {
    property string title: ""
    property string icon: ""
    property bool active: true
    property bool canClose: true
    property var buttons: []
    signal close()
    signal button(string name)
    implicitHeight: Theme.crisp(Theme.decor("title.height", 24), Screen.devicePixelRatio)
}
