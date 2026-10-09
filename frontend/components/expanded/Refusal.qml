import QtQuick
import "../../core"

// The translated line for a refused action (K24 cards). The daemon's `err.msg` is an i18n key and
// is shown as its text, never raw. A key without text, or no key, falls back to the card's own line.
QtObject {
    function text(err, fallback) {
        var k = err && err.msg ? String(err.msg) : ""
        var t = k === "" ? "" : I18n.tr(k)
        return (t !== "" && t !== k) ? t : I18n.tr(fallback)
    }
}
