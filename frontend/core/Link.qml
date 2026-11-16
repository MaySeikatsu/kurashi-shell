import QtQuick
import Quickshell.Io

// The socket to the daemon, shared by the shell's Store and Settings' (I334, rule 10). A Socket whose attempt failed does
// not reliably try again when toggled (measured: silent after the first ServerNotFound), so every attempt gets a fresh
// Socket instance, and the retry does not wait for an error signal (an attempt can fail silently): it makes a new Socket
// until the owner says the daemon welcomed it. Runs only while not welcomed (Ma): 250 ms doubling to 4 s.
Item {
    id: link
    property string path: ""
    // The owner's: the daemon answered the hello (the retry stops), or refused this client for good (it never retries).
    property bool welcomed: false
    property bool refused: false
    readonly property bool open: cur !== null && cur.connected
    // The socket opened (send the hello), it closed (the state is stale), a line arrived.
    signal up()
    signal down()
    signal line(string data)

    function write(text: string): bool {
        if (!link.open) return false
        cur.write(text + "\n")
        cur.flush()
        return true
    }
    // The daemon welcomed the client: the next loss starts again at the shortest wait.
    function settled(): void { retry.stop(); retry.interval = 250 }
    function giveUp(): void { retry.stop() }

    property var cur: null   // the live Socket instance
    Component {
        id: sockComp
        Socket {
            id: s
            path: link.path
            Component.onCompleted: { link.cur = s; connected = true }
            Component.onDestruction: if (link.cur === s) link.cur = null
            parser: SplitParser {
                splitMarker: "\n"
                onRead: data => link.line(data)
            }
            onConnectedChanged: {
                if (link.cur !== s) return   // a replaced instance going must not touch the state
                if (connected) {
                    link.up()
                } else {
                    link.down()
                    if (!retry.running && !link.refused) retry.start()
                }
            }
        }
    }
    Loader { id: ld; sourceComponent: sockComp }
    Timer {
        id: retry
        interval: 250
        repeat: false
        onTriggered: {
            interval = Math.min(interval * 2, 4000)
            if (link.welcomed || link.refused) return
            ld.active = false
            ld.active = true
            start()
        }
    }
    Component.onCompleted: retry.start()
}
