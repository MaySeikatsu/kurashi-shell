import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import "../core"
import "../components"
import "../components/decor"

// The polkit authentication agent and its dialog (K47 (5), docs/ux/polkit.md). The agent is Quickshell's `PolkitAgent`
// (as illogical-impulse's `services/PolkitService.qml` and DMS's `Services/PolkitService.qml`): libpolkit-agent and the
// setuid helper run in Quickshell's C++, so this file only draws the flow polkit hands it — an exception to rule 1 like
// the toolkit's own Wayland work, because the agent must live in the process that draws the dialog. The daemon learns only
// that a dialog is up (`ui.polkit {active}`), so the island and the Stage can stay out of its way.
// The window exists only while a flow is up (Ma): an overlay on the focused output, keyboard exclusive, a scrim behind a
// centred card drawn with Block, Icon and tokens (every decor styles it). The password goes from the field to
// `flow.submit()` in one call stack, the field cleared first (as LockContent does, K2); it is never kept or logged.
// `KURASHI_POLKIT_AGENT`: "0" never registers an agent, "1" always does; unset, it does except in the test sandbox
// (tools/bench/sandbox.sh exports KURASHI_SANDBOX_NETNS_ID), so an invisible sandbox shell never answers the user's own
// requests. `fakeFlow` (frontend/test-polkit.sh's harness) stands in for the agent's flow.
Scope {
    id: pd

    readonly property string envAgent: Quickshell.env("KURASHI_POLKIT_AGENT") || ""
    readonly property bool agentWanted: envAgent === "1"
        || (envAgent !== "0" && (Quickshell.env("KURASHI_SANDBOX_NETNS_ID") || "") === "")
    property var fakeFlow: null
    readonly property var agent: agentLoader.item
    readonly property var flow: fakeFlow ? fakeFlow : (agent && agent.isActive && agent.flow ? agent.flow : null)
    readonly property bool active: flow !== null
    // The output of this flow, latched when it starts (the dialog never jumps outputs); the window follows `shown`,
    // which is set after the output is picked.
    property var flowScreen: null
    property bool shown: false

    LazyLoader {
        id: agentLoader
        active: pd.agentWanted
        PolkitAgent {}
    }
    // The registration result, once (the card asks for it in the log either way).
    Connections {
        target: pd.agent
        function onIsRegisteredChanged() { pd.logRegistration() }
    }
    property bool logged: false
    function logRegistration() {
        if (logged || !agent) return
        logged = true
        console.info(agent.isRegistered ? "polkit: agent registered"
            : "polkit: agent not registered (another agent holds the session, or polkitd is not reachable)")
    }
    Timer {
        // Registration is asynchronous; one look after it had time to answer, never again.
        interval: 3000
        running: pd.agentWanted && !pd.logged
        onTriggered: pd.logRegistration()
    }
    Component.onCompleted: if (!agentWanted) console.info("polkit: agent off (KURASHI_POLKIT_AGENT, or the test sandbox)")

    // The daemon's flag (PROTOCOL runtime.ui `polkit`): sent on each change, and again after a reconnect while up.
    property bool told: false
    function tell() {
        if (!Store.live) return
        if (active === told) return
        told = active
        Store.act("ui.polkit", { active: active })
    }
    onActiveChanged: {
        if (active) flowScreen = focusedScreen()
        shown = active
        tell()
    }
    Connections {
        target: Store
        function onLiveChanged() { pd.told = false; if (Store.live && pd.active) pd.tell() }
    }
    Component.onDestruction: if (told) Store.act("ui.polkit", { active: false })

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

    LazyLoader {
        active: pd.shown
        PanelWindow {
            id: win
            screen: pd.flowScreen
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "kurashi-polkit"
            color: "transparent"

            readonly property var flow: pd.flow
            property bool busy: false
            property bool failed: false
            property real p: 0
            Component.onCompleted: { enter.start(); field.forceActiveFocus(); pickCurrentUser() }
            NumberAnimation { id: enter; target: win; property: "p"; from: 0; to: 1; duration: Theme.stdMs; easing.type: Easing.OutCubic }

            // polkit's prompt, cleaned as ii does: no trailing colon; "Password" (or "Response" for a visible answer)
            // when it sends none.
            readonly property string prompt: {
                var s = String((flow && flow.inputPrompt) || "").trim().replace(/[\s:]+$/, "")
                return s !== "" ? s : I18n.tr(flow && flow.responseVisible ? "polkit.response" : "polkit.password")
            }
            readonly property string message: String((flow && flow.message) || "").trim().replace(/\.$/, "")
            readonly property var identities: (flow && flow.identities) || []
            function idName(i) {
                if (!i) return ""
                var n = String(i.displayName || i.string || "")
                return i.isGroup ? I18n.tr("polkit.group").replace("{name}", n) : n
            }
            // Several identities may answer: the current user first (DMS `selectCurrentUserIdentity`). Choosing one
            // restarts polkit's request; that restart is not a failure.
            property bool switching: false
            // Identities compare by what they name (a list read back through a property may hand out new wrappers).
            function same(a, b) { return !!a && !!b && a.string === b.string && !!a.isGroup === !!b.isGroup }
            function pickCurrentUser() {
                if (!flow || identities.length < 2) return
                var me = Quickshell.env("USER") || ""
                for (var i = 0; i < identities.length; i++) {
                    var it = identities[i]
                    if (!it.isGroup && it.string === me && !same(it, flow.selectedIdentity)) { choose(it); return }
                }
            }
            function choose(it) {
                if (!flow || same(it, flow.selectedIdentity)) return
                switching = true
                flow.selectedIdentity = it
                switching = false
                failed = false
                busy = false
                field.forceActiveFocus()
            }
            function submit() {
                if (!flow || busy || field.text === "") return
                var s = field.text
                field.text = ""             // cleared before anything else can observe it
                failed = false
                busy = true
                flow.submit(s)
                s = ""
            }
            function cancel() {
                if (flow && !flow.isCompleted) flow.cancelAuthenticationRequest()
            }
            Connections {
                target: win.flow
                function onAuthenticationFailed() {
                    if (win.switching) return
                    win.busy = false
                    win.failed = true
                    shake.restart()
                    field.forceActiveFocus()
                }
                function onIsResponseRequiredChanged() {
                    if (win.flow.isResponseRequired) { win.busy = false; field.forceActiveFocus() }
                }
            }

            // Scrim: the chrome has no scrim token yet (CONTRACT-CHANGE row); black at 40 %, faded in.
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.4 * win.p)
            }
            MouseArea { anchors.fill: parent; onPressed: field.forceActiveFocus() }

            // The look's form (W53, row 591; decor/Entrance) on the dialog's own progress; `grow` (the default) keeps its
            // rise and fade.
            Entrance {
                id: card
                progress: win.p
                edge: "top"
                width: 420
                height: body.implicitHeight + 2 * Theme.pad + 2 * blk.inset + Theme.shadowDy + 2 * Theme.xs
                anchors.centerIn: parent
                anchors.verticalCenterOffset: form === "grow" ? 12 * (1 - win.p) : 0
                opacity: form === "grow" ? Math.min(1, win.p * 1.4) : (slides ? 1 : 1 - away)
                Keys.onEscapePressed: win.cancel()
                Accessible.role: Accessible.Dialog
                Accessible.name: I18n.tr("polkit.a11y.dialog").replace("{message}", win.message)
                Accessible.description: win.flow ? I18n.tr("polkit.a11y.action").replace("{action}", win.flow.actionId || "") : ""

                // W57 (K78): a modal stands highest (level 4).
                Elevation {
                    anchors.fill: parent
                    anchors.bottomMargin: Theme.shadowDy
                    radius: Theme.rLg + 4
                    level: 4
                }
                Block {
                    id: blk
                    anchors.fill: parent
                    radius: Theme.rLg + 4
                    fill: Theme.panel
                    flatBorder: Theme.outline
                }
                Column {
                    id: body
                    x: Theme.pad + blk.inset
                    y: Theme.pad + blk.inset + Theme.xs
                    width: card.width - 2 * x
                    spacing: Theme.gap

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 48; height: 48
                        radius: Theme.groups ? 24 : Theme.rSm
                        color: Theme.container
                        border.width: Theme.outlineW
                        border.color: Theme.outlineColor
                        Icon {
                            anchors.centerIn: parent
                            name: "lock"
                            glyph: "🔒"
                            filled: true
                            size: 26
                            color: Theme.accent
                        }
                    }
                    Text {
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        antialiasing: !Theme.pixelType
                        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        color: Theme.fg
                        font.pixelSize: Theme.fsTitle + 2
                        font.weight: Theme.wBold
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.tr("polkit.title")
                    }
                    Text {
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        antialiasing: !Theme.pixelType
                        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        color: Theme.fg
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                        text: win.message
                    }
                    // One identity: "as <user>". Several: one button each, the selected one primary.
                    Text {
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        antialiasing: !Theme.pixelType
                        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                        visible: win.identities.length < 2 && win.flow && win.flow.selectedIdentity
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        color: Theme.dim
                        font.pixelSize: Theme.fs - 1
                        font.family: Theme.fam(text, Theme.families)
                        text: visible ? I18n.tr("polkit.as").replace("{user}", win.idName(win.flow.selectedIdentity)) : ""
                    }
                    Column {
                        visible: win.identities.length > 1
                        width: parent.width
                        spacing: Theme.xs
                        Text {
                            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                            antialiasing: !Theme.pixelType
                            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                            color: Theme.dim
                            font.pixelSize: Theme.fsCaption
                            font.family: Theme.fam(text, Theme.families)
                            text: I18n.tr("polkit.identity")
                        }
                        Flow {
                            width: parent.width
                            spacing: Theme.xs
                            Repeater {
                                model: win.identities
                                delegate: Button {
                                    required property var modelData
                                    label: win.idName(modelData)
                                    primary: win.flow && win.same(modelData, win.flow.selectedIdentity)
                                    onClicked: win.choose(modelData)
                                }
                            }
                        }
                    }

                    // The field: the lock screen's (LockContent.qml), with its shake.
                    Item {
                        width: parent.width
                        height: 48 + Theme.shadowDy
                        RoundBox {
                            id: box
                            width: parent.width
                            height: 48
                            radius: Theme.groups ? Math.min(height / 2, Theme.rFull) : Theme.rLg
                            color: Theme.container
                            border.width: Theme.outlineW > 0 ? Theme.outlineW + (Theme.ringW > 0 ? 1 : 0) : 1
                            border.color: win.failed ? Theme.error : (Theme.ringW > 0 ? Theme.line
                                : (field.activeFocus ? Theme.fg : (Theme.outlineW > 0 ? Theme.outlineColor : Theme.outline)))
                            opacity: win.busy ? 0.6 : 1
                            // A text field is a well (W53, row 591): sunken under a bevel chrome, as Block { sunken } draws.
                            Loader {
                                anchors.fill: parent
                                active: Theme.bevelW > 0
                                sourceComponent: BevelEdge { sunk: true }
                            }
                            // The field's hard shadow along the shadow vector (K67; LockContent's field, the same shadow).
                            Rectangle {
                                z: -1
                                visible: Theme.sinkX !== 0 || Theme.sinkY !== 0
                                x: Theme.sinkX
                                y: Theme.sinkY
                                width: box.width
                                height: box.height
                                radius: box.radius
                                color: win.failed ? Theme.error : Theme.line
                            }
                            SequentialAnimation {
                                id: shake
                                NumberAnimation { target: box; property: "x"; to: 10; duration: Math.round(Theme.quickMs * 0.42) }
                                NumberAnimation { target: box; property: "x"; to: -10; duration: Math.round(Theme.quickMs * 0.67) }
                                NumberAnimation { target: box; property: "x"; to: 6; duration: Math.round(Theme.quickMs * 0.58) }
                                NumberAnimation { target: box; property: "x"; to: 0; duration: Math.round(Theme.quickMs * 0.42) }
                            }
                            Icon {
                                id: keyIcon
                                anchors { left: parent.left; leftMargin: Theme.pad; verticalCenter: parent.verticalCenter }
                                name: "key"
                                glyph: "⚿"
                                color: Theme.dim
                                size: Theme.fs + 4
                            }
                            Text {
                                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                                antialiasing: !Theme.pixelType
                                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                                anchors { left: keyIcon.right; leftMargin: Theme.gap; verticalCenter: parent.verticalCenter }
                                visible: field.text === ""
                                text: win.prompt
                                color: Theme.dim
                                font.pixelSize: Theme.fs
                                font.family: Theme.fam(text, Theme.families)
                            }
                            TextInput {
                                id: field
                                anchors { left: keyIcon.right; leftMargin: Theme.gap; right: parent.right; rightMargin: Theme.pad
                                          top: parent.top; bottom: parent.bottom }
                                verticalAlignment: TextInput.AlignVCenter
                                echoMode: win.flow && win.flow.responseVisible ? TextInput.Normal : TextInput.Password
                                passwordCharacter: "•"
                                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                                readOnly: win.busy
                                color: Theme.fg
                                font.pixelSize: Theme.fs
                                font.family: Theme.families[0]
                                selectionColor: Theme.accent
                                cursorVisible: activeFocus && !readOnly
                                focus: true
                                activeFocusOnTab: true
                                Accessible.name: win.prompt
                                Accessible.passwordEdit: echoMode === TextInput.Password
                                onAccepted: win.submit()
                                Keys.onEscapePressed: { text = ""; win.cancel() }
                            }
                        }
                    }
                    // polkit's own line (PAM info or error), else ours after a failure, else "Checking…" while busy.
                    Text {
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        antialiasing: !Theme.pixelType
                        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                        readonly property string supp: String((win.flow && win.flow.supplementaryMessage) || "").trim()
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        visible: text !== ""
                        text: win.busy ? I18n.tr("polkit.checking") : supp !== "" ? supp : win.failed ? I18n.tr("polkit.failed") : ""
                        color: !win.busy && (win.failed || (win.flow && win.flow.supplementaryIsError)) ? Theme.error : Theme.dim
                        font.pixelSize: Theme.fs - 1
                        font.family: Theme.fam(text, Theme.families)
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: Theme.gap
                        Button {
                            label: I18n.tr("polkit.cancel")
                            onClicked: win.cancel()
                        }
                        Button {
                            label: I18n.tr("polkit.authenticate")
                            primary: true
                            enabled: !win.busy && field.text !== ""
                            onClicked: win.submit()
                        }
                    }
                }
            }
        }
    }
}
