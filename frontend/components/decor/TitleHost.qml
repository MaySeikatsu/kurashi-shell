import QtQuick
import "../../core"

// TitleHost (W53.0a, K80): the look's window caption (`[slots] title`, e.g. "caption") on top of a Stage card, the
// launcher, the polkit dialog or the session menu. Contract: `title/TitleBase.qml`. Without a title slot nothing is made
// and the host is 0 px tall (today's cards). Shōjiki: a caption draws only buttons that act — the close button only
// with `canClose`, and `close` does what Esc does (the caller wires it to `ui.close`); minimize and maximize are the
// caller's (W53.0b's title-bar switch and actions) and are drawn only where it sets `buttons`.
DecorHost {
    id: th
    slot: "title"
    property string title: ""
    property string icon: ""
    // The window has focus (an inactive caption greys, as 9x/XP/7 do).
    property bool focused: true
    property bool canClose: true
    // Extra buttons the caller gives actions to, in order from the close button inward: e.g. ["maximize", "minimize"].
    property var buttons: []
    signal close()
    signal button(string name)
    // (A Loader's implicit size is its part's: 0 px tall without one.)
    onLoaded: {
        item.title = Qt.binding(function () { return th.title })
        item.icon = Qt.binding(function () { return th.icon })
        item.active = Qt.binding(function () { return th.focused })
        item.canClose = Qt.binding(function () { return th.canClose })
        item.buttons = Qt.binding(function () { return th.buttons })
        item.close.connect(th.close)
        item.button.connect(th.button)
    }
}
