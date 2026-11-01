import QtQuick
import "../core"

// LoadingText (W53.5): a status line that says something is loading as the look says it (`[decor] loading.form`; data,
// rule 4) — the caller's words (`text`, today's), the look's loading line with three dots stepping after it (`dots`: a
// 16-bit game's "NOW LOADING...", the dots padded so the line keeps its width) or the words under a slow pulse (`pulse`:
// the PS2's glow). The steps and the pulse run only while `loading` and visible, with motion on (reduce motion: the line
// still, its dots whole) — never at rest (Ma).
Text {
    id: lt
    property bool loading: false
    property string words: ""
    readonly property string form: Theme.decor("loading.form", "text")
    readonly property bool moving: loading && visible && Theme.springOn
    property int dots: 3
    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
    antialiasing: !Theme.pixelType
    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
    font.family: Theme.fam(text, Theme.families)
    text: loading && form === "dots" ? I18n.tr("frontend.loading.line") + ".".repeat(dots) + " ".repeat(3 - dots) : words
    Timer {
        running: lt.moving && lt.form === "dots"
        interval: 267
        repeat: true
        onRunningChanged: lt.dots = running ? 0 : 3
        onTriggered: lt.dots = (lt.dots + 1) % 4
    }
    SequentialAnimation on opacity {
        running: lt.moving && lt.form === "pulse"
        loops: Animation.Infinite
        onRunningChanged: if (!running) lt.opacity = 1
        NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
    }
}
