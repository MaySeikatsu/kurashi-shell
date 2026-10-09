import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"

// Launcher (M5): centred overlay with exclusive keyboard focus while open. The daemon owns the
// open state (runtime.ui.launcher), the index, ranking and launching; this only renders results
// of `query launcher` and sends `launcher.launch` / `ui.close`.
//
// Same idle discipline as Stage (K16): permanently mapped but transparent, input-less and
// focus-less while hidden, so it renders 0 frames; the reveal is a slide that starts on the first
// presented frame. Typing never animates: the result list is replaced, the highlight just moves.
PanelWindow {
    id: lp

    readonly property bool want: (Store.docs["runtime.ui"] && Store.docs["runtime.ui"].launcher) === true
    readonly property int slide: 12
    readonly property int rowH: 44
    readonly property int maxRows: 7
    property real p: 0
    property bool gate: false
    property bool shown: false
    property var results: []
    property int sel: 0
    property string err: ""
    property var scr: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null   // latched on open so the card never jumps outputs

    function focusedScreen() {
        var o = (Store.docs["svc.workspaces"] && Store.docs["svc.workspaces"].outputs) || {}
        var s = Quickshell.screens
        for (var i = 0; i < s.length; i++) {
            var l = o[s[i].name] || []
            for (var j = 0; j < l.length; j++)
                if (l[j].focused) return s[i]
        }
        return s.length > 0 ? s[0] : null
    }
    function run(q) {
        Store.query("launcher", q, function (items, e) {
            if (!lp.want) return
            lp.results = items || []
            lp.sel = 0
            lp.err = e ? e.msg : ""
        })
    }
    function launch() {
        if (sel < 0 || sel >= results.length) return
        Store.act("launcher.launch", { id: results[sel].id }, function (done, e) {
            if (e) lp.err = e.msg
        })
        Store.act("ui.close")
    }

    screen: scr
    // No anchors: the compositor centres the surface.
    implicitWidth: card.width
    implicitHeight: card.height
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: want ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "kurashi-launcher"
    color: "transparent"
    mask: shown ? cardRegion : emptyRegion
    BackgroundEffect.blurRegion: shown ? cardRegion : emptyRegion
    Region { id: cardRegion; item: card }
    Region { id: emptyRegion }

    onWantChanged: {
        if (want) {
            scr = focusedScreen()
            field.text = ""
            results = []; sel = 0; err = ""
            anim.stop()
            if (!shown) { p = 0; gate = true; shown = true }
            else { anim.from = p; anim.to = 1; anim.start() }
            run("")
            field.forceActiveFocus()
        } else if (shown) {
            gate = false
            anim.stop(); anim.from = p; anim.to = 0; anim.start()
        }
    }
    NumberAnimation {
        id: anim
        target: lp; property: "p"
        duration: Theme.stdMs
        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve
        onFinished: if (lp.p <= 0 && !lp.want) { lp.shown = false; lp.results = [] }
    }
    Connections {
        target: card.Window.window
        function onFrameSwapped() {
            if (lp.gate) { lp.gate = false; anim.from = lp.p; anim.to = 1; anim.start() }
        }
    }

    Rectangle {
        id: card
        visible: lp.shown
        width: 560
        height: 2 * Theme.pad + 40 + Theme.gap + lp.maxRows * lp.rowH
        y: -lp.slide * (1 - lp.p)
        radius: Theme.rLg
        color: Theme.container
        border.width: 1
        border.color: Theme.outline

        Rectangle {
            id: box
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.pad }
            height: 40
            radius: Theme.rSm
            color: Theme.surface
            border.width: 1
            border.color: field.activeFocus ? Theme.accent : Theme.outline
            TextInput {
                id: field
                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                color: Theme.fg
                font.pixelSize: Theme.fsTitle
                font.family: Theme.fam(text, Theme.families)
                verticalAlignment: TextInput.AlignVCenter
                selectByMouse: true
                clip: true
                onTextChanged: if (lp.want) lp.run(text)
                Keys.onEscapePressed: Store.act("ui.close")
                Keys.onDownPressed: if (lp.sel < lp.results.length - 1) lp.sel++
                Keys.onUpPressed: if (lp.sel > 0) lp.sel--
                Keys.onReturnPressed: lp.launch()
                Keys.onEnterPressed: lp.launch()
                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: field.text === "" && field.preeditText === ""
                    color: Theme.dim
                    font: field.font
                    text: I18n.tr("launcher.placeholder")
                }
            }
        }

        ListView {
            id: list
            anchors { left: parent.left; right: parent.right; top: box.bottom; bottom: parent.bottom
                      margins: Theme.pad; topMargin: Theme.gap }
            clip: true
            interactive: false
            model: lp.results
            currentIndex: lp.sel
            highlightMoveDuration: 0
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                width: list.width
                height: lp.rowH
                radius: Theme.rSm
                color: index === lp.sel ? Theme.containerHigh : "transparent"
                border.width: index === lp.sel ? 1 : 0
                border.color: Theme.accent

                Item {
                    id: ico
                    x: 8; anchors.verticalCenter: parent.verticalCenter
                    width: 28; height: 28
                    property string src: modelData.icon ? Quickshell.iconPath(modelData.icon, true) : ""
                    Image {
                        id: img
                        anchors.fill: parent
                        source: ico.src
                        sourceSize: Qt.size(56, 56)
                        asynchronous: true
                        visible: ico.src !== "" && status === Image.Ready
                    }
                    // Text fallback: initial of the name.
                    Rectangle {
                        anchors.fill: parent
                        visible: !img.visible
                        radius: Theme.rSm
                        color: Theme.surface
                        Text {
                            anchors.centerIn: parent
                            color: Theme.dim
                            font.pixelSize: Theme.fs
                            font.family: Theme.fam(text, Theme.families)
                            text: (modelData.name || "?").charAt(0).toUpperCase()
                        }
                    }
                }
                Column {
                    anchors { left: ico.right; leftMargin: Theme.gap; right: parent.right; rightMargin: 8
                              verticalCenter: parent.verticalCenter }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                        text: modelData.name
                    }
                    Text {
                        width: parent.width
                        visible: !!modelData.generic
                        elide: Text.ElideRight
                        color: Theme.dim
                        font.pixelSize: Theme.fs - 2
                        font.family: Theme.fam(text, Theme.families)
                        text: modelData.generic || ""
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { lp.sel = row.index; lp.launch() }
                }
            }
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        }

        Text {
            anchors { centerIn: list }
            visible: lp.results.length === 0
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: lp.err !== "" ? lp.err : I18n.tr("launcher.empty")
        }
    }
}
