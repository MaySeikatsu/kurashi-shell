import QtQuick
import Quickshell
import qs.core

// The terminal's last frame in a place's well (W85; docs/ux/terminal.md "Drawing"): the host keeps a still of the active
// tab's text beside the well's size (mods/terminal/host/TermView.qml), and the place draws it while the text itself is not
// there — as the sheet slides in or out, until the host's window has mapped over the well — so the text comes and goes
// with its sheet instead of popping in after it rests. The same pixels as the text: when the host's window maps over it
// there is nothing to see, and the still is put away once the host says its text is here (`host.shows`). No still of this
// size (the first show, another size): nothing, as before. Loaded only while it is wanted (Ma).
Image {
    id: st
    property var doc: ({})
    // The place this well is, and whether the still is wanted now (the place moves, or its text is not here yet).
    property string place: ""
    property bool hold: false
    // Kept loaded (not drawn) while the place shows the text, so it is drawn the moment the place leaves.
    property bool keep: false
    readonly property string tabId: doc.active || ""
    readonly property string runDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string key: tabId === "" || width < 2 || height < 2 ? ""
        : tabId + "-" + Math.round(width) + "x" + Math.round(height)
    // (only a still the host says it wrote: no read of a file that is not there)
    readonly property bool there: key !== "" && ((doc.host && doc.host.stills) || []).indexOf(key) >= 0
    readonly property string path: there ? "file://" + runDir + "/kurashi-terminal-" + key + ".png" : ""
    readonly property string hostAt: (doc.host && doc.host.shows) || ""
    readonly property int gen: (doc.host && doc.host.still_gen) || 0
    readonly property bool wanted: hold || keep
    cache: false
    // (wanted on screen now: decoded at once, a few ms, so the first frame of a slide has the text; kept: in the
    // background)
    asynchronous: false
    smooth: false
    fillMode: Image.Stretch
    visible: hold && status === Image.Ready
    function reload() {
        source = ""
        asynchronous = !hold
        if (wanted && path !== "") source = path
    }
    // (settled first: the place hands over from keeping to holding in one change, and the still loaded stays)
    onWantedChanged: Qt.callLater(function () { if (!st.wanted) st.source = ""; else if (st.source.toString() === "") st.reload() })
    onPathChanged: if (wanted) reload()
    // A newer still (written while the text showed, or as it left).
    onGenChanged: if (wanted) reload()
}
