import QtQuick
import Quickshell
import Quickshell.Wayland
import "core"
import "components"
import "components/decor"
import "components/lock"

// StyleSheet (W53.2): the style sheet: every decor part of the look in effect, side by side on one layer-shell surface, and a lock
// face in any state — for the family cards' review against the brief while the callers do not host a part yet, and for
// the lock states a sandbox cannot reach (Caps Lock, an error, a countdown). Run on the sandbox's own Quickshell next to
// the shell (it talks to the sandbox's kurashid for the theme; it sends nothing):
//   niri-sandbox.sh spawn env KURASHI_SHEET=<mode> qs -p frontend/StyleSheet.qml
// (It lives beside shell.qml because Quickshell resolves the shell's imports only from the config's own directory.)
// Modes: `parts` (default): captions active and inactive, start dresses at rest/open, the bar ground with a start and a
// tray well, menu rows, a balloon/tooltip with its tail, buttons; `lock`, `lock-error`, `lock-caps`, `lock-busy`,
// `lock-wait`, `lock-prompt`, `lock-secondary`: the look's lock face (`decor.lock`) full screen with that state faked
// (a typed key never leaves this window). Test tool only: never part of the shell.
ShellRoot {
    id: root
    readonly property string mode: String(Quickshell.env("KURASHI_SHEET") || "parts")
    readonly property bool lockMode: mode.indexOf("lock") === 0
    Watch { doc: "theme" }
    Watch { doc: "i18n" }
    Watch { doc: "svc.clock" }

    PanelWindow {
        anchors { top: true; left: true; right: true; bottom: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.lockMode ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        color: root.lockMode ? "transparent" : Theme.color("color.desk", "#3a6ea5")

        // ---- lock faces ----------------------------------------------------------------------------------------------
        FaceHost {
            anchors.fill: parent
            visible: root.lockMode
            active: root.lockMode
            focus: true
            face: Theme.slot("lock") || "plain"
            lock: ({
                locked: true,
                busy: root.mode === "lock-busy",
                failures: root.mode === "lock-error" ? 1 : 0,
                retry_in_ms: root.mode === "lock-wait" ? 27000 : 0,
                message_key: root.mode === "lock-error" ? "lock.error.wrong_password" : "",
                prompt: root.mode === "lock-prompt" ? "Verification code:" : "",
                prompt_echo: root.mode === "lock-prompt",
                caps_lock: root.mode === "lock-caps",
                fingerprint: { available: false, state: "idle" }
            })
            clock: ({ hh: "10", mm: "31", date_key: "", weekday: "Friday", day: 30, month: 10, year: 2026 })
            remainingMs: root.mode === "lock-wait" ? 27000 : 0
            user: ({ name: String(Quickshell.env("USER") || "maike") })
            primary: root.mode !== "lock-secondary"
        }

        // ---- parts ----------------------------------------------------------------------------------------------------
        Column {
            visible: !root.lockMode
            x: 24; y: 24
            spacing: 18

            Row {
                spacing: 24
                Repeater {
                    model: [true, false]
                    TitleHost {
                        required property bool modelData
                        width: 420
                        title: modelData ? "Active caption" : "Inactive caption"
                        focused: modelData
                        canClose: true
                        buttons: ["maximize", "minimize"]
                    }
                }
            }
            Row {
                spacing: 24
                Repeater {
                    model: [false, true]
                    Item {
                        required property bool modelData
                        width: start.item ? start.item.width : 0
                        height: Theme.barH
                        StartHost { id: start; open: parent.modelData }
                    }
                }
            }
            // The bar: its ground, the start dress, a tray well with a clock-sized label, one strip.
            Item {
                width: 900
                height: Theme.barH
                BarGround { anchors.fill: parent; edge: "bottom" }
                StartHost { id: bs; anchors.verticalCenter: parent.verticalCenter }
                Item {
                    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                    width: 140
                    TrayWell { anchors.fill: parent }
                    Text {
                        anchors.centerIn: parent
                        text: "10:31"
                        color: Theme.fgOnAccent
                        font.family: Theme.families[0]
                        font.pixelSize: Theme.fs
                    }
                }
            }
            // W53.4: a window ground with the look's pattern, and the dock body (`[slots] dock`) under five stand-in icons
            // (its reflection mirrors them), the running mark under two.
            Row {
                spacing: 40
                Rectangle {
                    width: 260
                    height: 84
                    radius: Theme.rLg
                    color: Theme.container
                    border.width: 1
                    border.color: Theme.outline
                    Pattern { anchors.fill: parent; radius: parent.radius }
                    Text { anchors.centerIn: parent; text: "Window ground"; color: Theme.fg; font.family: Theme.families[0]; font.pixelSize: Theme.fs }
                }
                Item {
                    width: icons.width + 24
                    height: 48 + 6 + 24
                    DockGround {
                        id: dg
                        anchors.fill: parent
                        edge: "bottom"
                        mirror: icons
                        icon: 48
                    }
                    Row {
                        id: icons
                        x: 12; y: 12
                        spacing: 6
                        Repeater {
                            model: [Theme.accent, Theme.error, Theme.warning, Theme.tertiary, Theme.secondary]
                            Rectangle {
                                required property color modelData
                                width: 48; height: 48; radius: 11
                                gradient: Gradient {
                                    GradientStop { position: 0; color: Qt.lighter(modelData, 1.4) }
                                    GradientStop { position: 1; color: modelData }
                                }
                            }
                        }
                    }
                    Text {
                        x: 12 + 24 - width / 2; y: 12 + 48 + 1
                        text: dg.indicator === "triangle" ? "▲" : dg.indicator === "dot" ? "●" : "• •"
                        color: Theme.fg
                        font.pixelSize: dg.indicator === "triangle" ? 6 : 5
                    }
                }
            }
            Row {
                spacing: 40
                // Menu rows: normal, highlighted, a separator, normal.
                Rectangle {
                    width: 220
                    height: menuCol.height + 6
                    color: Theme.color("color.surface_container_lowest", "#ffffff")
                    border.width: 1
                    border.color: Theme.color("color.outline_variant", "#aca899")
                    MenuStyle { id: ms }
                    Column {
                        id: menuCol
                        x: 3; y: 3
                        width: parent.width - 6
                        Repeater {
                            model: [["Programs", false, false], ["Favorites", true, false], ["", false, true], ["Shut Down…", false, false]]
                            Item {
                                required property var modelData
                                width: menuCol.width
                                height: modelData[2] ? 9 : Math.max(20, Theme.decor("menu.row", 0))
                                DecorHost {
                                    slot: "menu"
                                    anchors.fill: parent
                                    onLoaded: {
                                        item.highlighted = parent.modelData[1]
                                        item.separator = parent.modelData[2]
                                    }
                                }
                                Text {
                                    visible: !parent.modelData[2]
                                    x: 26
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.modelData[0]
                                    color: parent.modelData[1] ? Theme.decor("menu.on", "") || Theme.fgOnSelected : Theme.fg
                                    font.family: Theme.families[0]
                                    font.pixelSize: Theme.fs
                                }
                            }
                        }
                    }
                }
                // A balloon tip with its tail toward an anchor below.
                Item {
                    width: 320
                    height: 96
                    TooltipStyle { id: ts }
                    Loader {
                        anchors.fill: parent
                        anchors.bottomMargin: 20
                        active: ts.has
                        source: ts.part
                        onLoaded: { item.tailSide = "bottom"; item.tailAt = 250; item.title = "Caps Lock is On" }
                    }
                    Column {
                        x: 12; y: 8
                        spacing: 4
                        Text {
                            text: "Caps Lock is On"
                            font.bold: true
                            font.family: Theme.families[0]
                            font.pixelSize: Theme.fs
                            color: ts.ink(Theme.fg)
                        }
                        Text {
                            width: 290
                            wrapMode: Text.WordWrap
                            text: "Having Caps Lock on may cause you to enter your password incorrectly."
                            font.family: Theme.families[0]
                            font.pixelSize: Theme.fs
                            color: ts.ink(Theme.fg)
                        }
                    }
                }
                // Buttons: normal, hovered (not faked: at rest), the default, pressed.
                Row {
                    spacing: 8
                    Repeater {
                        model: [[false, false, "OK"], [false, true, "Default"], [true, false, "Pressed"]]
                        Item {
                            required property var modelData
                            width: 75
                            height: 23
                            DecorHost {
                                slot: "button"
                                anchors.fill: parent
                                onLoaded: { item.pressed = parent.modelData[0]; item.primary = parent.modelData[1] }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData[2]
                                color: Theme.fg
                                font.family: Theme.families[0]
                                font.pixelSize: Theme.fs
                            }
                        }
                    }
                }
            }
        }
    }
}
