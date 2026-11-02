import QtQuick
import "recipe.js" as R

// A recipe (W59.7, K83; brief docs/ux/motion-engine.md §5 "Recipes"): a form a user wrote in a motion pack as tracks
// over progress, run at content level like the other TransformForms. The host gives the recipe's token (`host.recipe`:
// `motion.recipe.<id>`, validated by the daemon) and its one progress; every track is evaluated from that progress
// (recipe.js) — no timers. Outputs:
//   - a base form (`base = "slide"` …) runs underneath: its translate, scale, rotation pass through, its opacity
//     multiplies, its blur adds;
//   - the tracks' scale, skew, turns and translation as one `matrix` (projected as QQuickRotation projects, so a
//     rotate_y looks as flip's does), identity at rest;
//   - a blur track or a clip track: the host's layer (`layered`) only away from rest (p < 1, as bleed's), with `blurMax`
//     and a `mask` item (made then, destroyed at rest).
// At p = 1 every output is identity and nothing is made: the motion-off frame (the daemon's rest rule).
TransformForm {
    id: rc
    // The recipe's token; the host's (FormHost.recipe; Settings' preview host).
    readonly property var token: host && host.recipe !== undefined ? host.recipe : null
    readonly property var prep: R.prepare(token)
    readonly property real pc: Math.max(0, Math.min(1, progress))
    // Away from rest (as bleed: the closed end, p = 0, draws its frame too — a surface shows its p = 0 frame for the first
    // frame of an open).
    readonly property bool moving: pc < 1
    readonly property var v: R.evaluate(prep, pc)
    readonly property var origin: host && host.origin !== undefined ? host.origin : Qt.rect(0, 0, 0, 0)

    // --- the base form, made once per base ---
    readonly property var bases: ({ slide: "Slide", rubber: "Slide", zoom: "Zoom", fade: "Fade", flip: "Flip",
                                    bleed: "Bleed", stepped: "Stepped" })
    property QtObject base: null
    readonly property string baseComp: prep.ok && bases[prep.base] !== undefined ? bases[prep.base] : ""
    onBaseCompChanged: makeBase()
    Component.onCompleted: makeBase()
    Component.onDestruction: { dropMask(); if (base) base.destroy() }
    function makeBase() {
        if (base) { base.destroy(); base = null }
        if (baseComp === "") return
        var c = Qt.createComponent(Qt.resolvedUrl(baseComp + ".qml"))
        if (c.status === Component.Ready) base = c.createObject(rc, { host: rc.host })
        else console.log("motion: recipe base " + prep.base + " failed to load: " + c.errorString())
    }

    // --- outputs ---
    opacity: (base ? base.opacity : 1) * v.opacity
    tx: base ? base.tx : 0
    ty: base ? base.ty : 0
    sx: base ? base.sx : 1
    sy: base ? base.sy : 1
    angle: base ? base.angle : 0
    rx: base ? base.rx : w / 2
    ry: base ? base.ry : h / 2
    ax: base ? base.ax : 0
    ay: base ? base.ay : 1
    // The tracks' transform after the base's (FormHost's Matrix4x4, last in its list).
    readonly property var identity: Qt.matrix4x4()
    readonly property var matrix: {
        if (!moving || !prep.ok) return identity
        var m = R.matrix(prep, v, w, h, edge, origin)
        return Qt.matrix4x4(m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9], m[10], m[11],
                            m[12], m[13], m[14], m[15])
    }
    // Blur in px of the recipe's own largest (bleed's 24 when it is the base and blurs more).
    readonly property bool baseBlurs: base !== null && base.layered
    readonly property real blurMax: Math.max(prep.blurMax, baseBlurs ? 24 : 0)
    blur: blurMax > 0 ? Math.min(1, (v.blur + (baseBlurs ? base.blur * 24 : 0)) / blurMax) : 0
    layered: (moving && prep.layer) || baseBlurs

    // --- the clip mask: an item the host's layer effect masks with, only while it moves ---
    property Item mask: null
    readonly property bool needMask: moving && prep.clip && host !== null
    onNeedMaskChanged: needMask ? makeMask() : dropMask()
    readonly property var box: needMask ? R.clip(prep, v, w, h, edge, origin) : ({ x: 0, y: 0, w: 0, h: 0, cx: 0, cy: 0, r: -1 })
    function makeMask() {
        if (mask) return
        mask = maskComp.createObject(host, { form: rc })
    }
    function dropMask() {
        if (!mask) return
        var m = mask
        mask = null
        m.destroy()
    }
    property Component maskComp: Component {
        Item {
            id: mk
            property QtObject form: null
            width: form ? form.w : 0
            height: form ? form.h : 0
            visible: false
            layer.enabled: true
            Item {
                id: boxItem
                x: mk.form ? mk.form.box.x : 0
                y: mk.form ? mk.form.box.y : 0
                width: mk.form ? mk.form.box.w : 0
                height: mk.form ? mk.form.box.h : 0
                clip: true
                Rectangle {
                    readonly property var b: mk.form ? mk.form.box : null
                    readonly property bool iris: b !== null && b.r >= 0
                    x: iris ? b.cx - b.r - boxItem.x : 0
                    y: iris ? b.cy - b.r - boxItem.y : 0
                    width: iris ? 2 * b.r : boxItem.width
                    height: iris ? 2 * b.r : boxItem.height
                    radius: iris ? b.r : 0
                    antialiasing: true
                    color: "white"
                }
            }
        }
    }
}
