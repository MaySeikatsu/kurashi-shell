import QtQuick

// FaceBase (W53.0b, K80, docs/ux/styles.md "Lock faces"): the contract every lock face keeps. A face is presentational —
// state in, signals out — and the daemon names the one in effect (`runtime.lock.face`, resolved from `lock.face` and the
// style's `decor.lock`); FaceHost loads `<Name>Face.qml` by that name and never compares it (rule 4).
// Every face renders: the clock and date, the password field (echo off; on for a PAM question with `prompt_echo`), PAM's
// follow-up prompts and info/error messages, busy, the retry countdown, Caps Lock, the fingerprint reader, what plays
// (optional), and "daemon disconnected". Keyboard only: the field has focus on the first frame, a key typed on a
// two-stage face's first stage reaches the field. Strings from `lockui` keys. Ma: one paint per size and colour, motion
// one-shot, nothing while unlocked (the surface does not exist). The greeter's strip (user, session, power) stands over
// the bottom edge of any face: keep the bottom 72 px free of controls.
Rectangle {
    // runtime.lock (the daemon's): locked, busy, failures, retry_in_ms, message_key, pam_message, prompt, prompt_echo,
    // prompt_key, face, caps_lock (absent = unknown), fingerprint {available, state}.
    property var lock: ({})
    property var clock: ({})            // svc.clock
    property var media: ({})            // svc.media
    property int remainingMs: 0         // local countdown of lock.retry_in_ms (no daemon polling)
    property var user: ({})             // {name, avatar?}; the greeter's chosen user, else empty
    // This output shows the field (the focused one); the others show the face's ground and clock. A face may keep the
    // field everywhere (the plain one does).
    property bool primary: true
    readonly property bool capsLock: lock.caps_lock === true
    readonly property var fingerprint: lock.fingerprint || ({ available: false, state: "idle" })
    // The `lock.aside` mod slot's host, for a face that shows one (B40).
    property Component asideSlot: null

    signal submitted(string secret)
    signal cancelled()
    // The Caps Lock key reached the field: the host asks the daemon to read the LED again (`lock.caps`).
    signal capsKey()

    // Give the field the keyboard (after a prompt, a busy spell, a click).
    function refocus() {}
}
