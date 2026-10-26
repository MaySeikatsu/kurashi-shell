import QtQuick
import QtQuick.Layouts
import "../../core"
import "../../core/mods.js" as Mods
import ".."
import "../expanded"

// The right sidebar's column (docs/ux/sidebar.md): `sidebar.right.sections`, its sections, top to bottom — `header`, `toggles`,
// `sliders`, `notifications`, `calendar` (ClockView: the month grid and the agenda slot), `media` (MediaView, while
// something plays) and mod panels `mod:<id>:<panel>` (a section takes no space while its mod is off). The notifications
// take the free height (ii's centre group); when the output is too short for their least height the whole column scrolls,
// so it never overflows (a 720 px output too). A tile's page covers the sections and slides in; `back()` (Esc) closes it
// and gives the focus back to the tile. Tab order is the visual order. Each section watches its own documents, and the
// column exists only while the sidebar is open (Ma).
Item {
    id: rc
    property var sections: []
    property string outName: ""

    // ---- a tile's page over the sections ----
    property Component pageC: null
    property Item pageFrom: null
    property real slide: 0
    function openPage(c, from) {
        pageFrom = from
        pageC = c
        slideAnim.stop(); slideAnim.to = 1; slideAnim.start()
    }
    // Esc: a page goes back first; with none, the sidebar closes (Sidebar.qml).
    function back() {
        if (pageC === null) return false
        slideAnim.stop(); slideAnim.to = 0; slideAnim.start()
        var f = pageFrom
        pageFrom = null
        if (f !== null) f.forceActiveFocus()
        return true
    }
    NumberAnimation {
        id: slideAnim
        target: rc; property: "slide"
        duration: Theme.emphMs + (Theme.springOn ? 60 : 0)
        easing.type: Theme.springOn ? Easing.OutBack : Easing.BezierSpline
        easing.overshoot: Theme.overshoot
        easing.bezierCurve: Theme.enterCurve
        onFinished: if (rc.slide <= 0) rc.pageC = null
    }
    clip: true

    Flickable {
        id: flick
        x: -rc.slide * rc.width
        width: rc.width
        height: rc.height
        visible: rc.slide < 1
        contentWidth: width
        contentHeight: lay.height
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height + 1
        ColumnLayout {
            id: lay
            width: flick.width
            height: Math.max(flick.height, implicitHeight)
            spacing: Theme.pad
            Repeater {
                model: rc.sections
                delegate: Loader {
                    id: sec
                    required property var modelData
                    readonly property string sid: String(modelData)
                    readonly property var modRef: Mods.panelOf(sid)
                    readonly property bool fills: sid === "notifications"
                    Layout.fillWidth: true
                    Layout.fillHeight: fills
                    Layout.preferredHeight: fills ? (item ? item.minHeight : 0) : (item ? item.implicitHeight : 0)
                    Layout.minimumHeight: fills && item ? item.minHeight : 0
                    // A section that shows nothing (nothing plays, its mod is off) takes no space and no spacing.
                    visible: status === Loader.Ready && item !== null && item.shown !== false
                    sourceComponent: sid === "header" ? headerC
                        : sid === "toggles" ? togglesC
                        : sid === "sliders" ? slidersC
                        : sid === "notifications" ? notesC
                        : sid === "calendar" ? calendarC
                        : sid === "media" ? mediaC
                        : modRef !== null ? modC : null
                    onLoaded: if (item && modRef !== null) { item.mod = modRef.mod; item.panel = modRef.panel }
                }
            }
        }
    }
    Component { id: headerC; HeaderSection {} }
    Component {
        id: togglesC
        TogglesSection { onPageRequested: (c, from) => rc.openPage(c, from) }
    }
    Component { id: slidersC; SlidersSection {} }
    Component { id: notesC; NotificationsSection {} }
    Component {
        id: calendarC
        Card { ClockView { width: parent.width } }
    }
    Component {
        id: mediaC
        Card {
            id: mc
            Watch { doc: "svc.media" }
            readonly property var md: Store.docs["svc.media"] || ({})
            shown: md.available !== false && String(md.title || "") !== ""
            Loader { width: parent.width; active: mc.shown; sourceComponent: MediaView {} }
        }
    }
    Component { id: modC; ModSection {} }

    // The page: the quick card's page component, made while it is shown; a long list scrolls.
    Flickable {
        id: pageFlick
        x: (1 - rc.slide) * rc.width
        width: rc.width
        height: rc.height
        visible: rc.pageC !== null
        contentWidth: width
        contentHeight: pageLoader.height
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height + 1
        Loader {
            id: pageLoader
            width: pageFlick.width
            active: rc.pageC !== null
            sourceComponent: rc.pageC
            onLoaded: {
                item.width = Qt.binding(function () { return pageLoader.width })
                item.backRequested.connect(function () { rc.back() })
                Qt.callLater(function () { if (pageLoader.item) pageLoader.item.focusFirst() })
            }
        }
    }
}
