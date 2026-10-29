import QtQuick

// FaceHost (W53.0b, K80): loads the lock face the daemon names (`runtime.lock.face`; the greeter: its cache) —
// `<Name>Face.qml` in this directory, kebab-case → PascalCase — and hands it the FaceBase contract. It never compares the
// name (rule 4). The daemon names only shipped faces; a face that fails to load anyway falls back to the plain one.
Loader {
    id: fh
    property string face: "plain"
    property var lock: ({})
    property var clock: ({})
    property var media: ({})
    property int remainingMs: 0
    property var user: ({})
    property bool primary: true
    property Component asideSlot: null
    // The ground's colour when the host wants another (the greeter's veil over a picture); unset = the face's own.
    property var ground: undefined
    signal submitted(string secret)
    signal cancelled()
    signal capsKey()

    function refocus() { if (item) item.refocus() }

    readonly property string file: {
        var n = face || "plain"
        return n.split("-").map(function (w) { return w.charAt(0).toUpperCase() + w.slice(1) }).join("") + "Face.qml"
    }
    property bool failed: false
    onFileChanged: failed = false
    source: Qt.resolvedUrl(failed ? "PlainFace.qml" : file)
    onStatusChanged: if (status === Loader.Error && !failed) {
        console.warn("lock face " + file + " did not load; the plain face stands in")
        failed = true
    }
    onLoaded: {
        item.lock = Qt.binding(function () { return fh.lock })
        item.clock = Qt.binding(function () { return fh.clock })
        item.media = Qt.binding(function () { return fh.media })
        item.remainingMs = Qt.binding(function () { return fh.remainingMs })
        item.user = Qt.binding(function () { return fh.user })
        item.primary = Qt.binding(function () { return fh.primary })
        item.asideSlot = Qt.binding(function () { return fh.asideSlot })
        if (fh.ground !== undefined) item.color = Qt.binding(function () { return fh.ground })
        item.submitted.connect(fh.submitted)
        item.cancelled.connect(fh.cancelled)
        item.capsKey.connect(fh.capsKey)
        item.refocus()
    }
}
