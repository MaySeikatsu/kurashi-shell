import QtQuick
import QtWebEngine

// One profile per effective profile name (MODS.md "Web dock"): the pins that share a name share its cookies, storage
// and user agent. A profile is made from a WebEngineProfilePrototype (the storage, `dirs.profiles/<name>`) and its
// `instance()`. The view of a profile is the view of its first pin (the daemon's rule), and the user agent and the
// client hints follow it: desktop is the engine's own, mobile the same string with an Android platform and `Mobile`
// before `Safari/`. The privacy switches that are profile-wide are set here (docs/ux/webdock.md "Privacy", K38).
Item {
    id: profiles
    // Holds the prototypes; draws nothing (no frames, Ma).
    visible: false

    // The daemon's pins (`mod.webdock.pins`), `dirs.profiles` (the storage root), and the reporter.
    property var pins: []
    property string storageRoot: ""
    property var report: null

    // The engine's own values, read once from a prototype without storage (it keeps nothing of its own).
    WebEngineProfilePrototype {
        id: engineDefaults
    }
    property string desktopUA: ""
    property string desktopPlatform: ""
    readonly property string mobileUA: desktopUA
        .replace(/\([^)]*\)/, "(Linux; Android 14; Pixel 8)")
        .replace("Safari/", "Mobile Safari/")
    Component.onCompleted: {
        var d = engineDefaults.instance()
        desktopUA = d.httpUserAgent
        desktopPlatform = d.clientHints.platform
        console.log("webdock: the engine's user agent is " + desktopUA)
    }

    // The profiles made so far, by name.
    property var byName: ({})

    onPinsChanged: {
        for (var name in byName) applyClientHints(byName[name], name)
    }

    // "mobile" or "desktop": the view of the first web pin that uses the profile.
    function viewOf(name) {
        for (var i = 0; i < pins.length; i++) {
            var p = pins[i]
            if (p.kind === "web" && (p.profile || p.id) === name)
                return p.view === "mobile" ? "mobile" : "desktop"
        }
        return "desktop"
    }

    function nameOf(pin) {
        return pin.profile || pin.id
    }

    // The profile a pin's view uses; made on first use. None until `dirs.profiles` is known (the storage is under it).
    function forPin(pin) {
        if (storageRoot === "") return null
        var name = nameOf(pin)
        if (!byName[name]) {
            var proto = protoComp.createObject(profiles, {
                pname: name,
                storageName: name,
                persistentStoragePath: storageRoot + "/" + name
            })
            var prof = proto.instance()
            configure(prof, name)
            var next = Object.assign({}, byName)
            next[name] = prof
            byName = next
        }
        return byName[name]
    }

    function configure(prof, name) {
        // Permissions are never stored: each request is asked again (and refused in v1).
        prof.persistentPermissionsPolicy = WebEngineProfile.PersistentPermissionsPolicy.AskEveryTime
        // Spell check from local dictionaries only, and no push service (it would use the vendor's push).
        prof.spellCheckEnabled = false
        prof.isPushServiceEnabled = false
        prof.httpUserAgent = Qt.binding(function () {
            return viewOf(name) === "mobile" ? mobileUA : desktopUA
        })
        applyClientHints(prof, name)
        prof.downloadRequested.connect(function (download) { downloadRequested(name, download) })
    }

    // The client hints are not bindable in QtWebEngine 6.11, so they follow the view by hand (on every pins change).
    function applyClientHints(prof, name) {
        var mobile = viewOf(name) === "mobile"
        prof.clientHints.mobile = mobile
        prof.clientHints.platform = mobile ? "Android" : desktopPlatform
    }

    function downloadRequested(name, download) {
        // Downloads are refused and reported (docs/ux/webdock.md "Sites"); the download's view names the pin.
        var view = download.view
        download.cancel()
        if (report) report("webdock.host.blocked", {
            pin: view && view.pinId ? view.pinId : name,
            permission: "download"
        })
    }

    Component {
        id: protoComp
        WebEngineProfilePrototype {
            property string pname: ""
        }
    }
}
