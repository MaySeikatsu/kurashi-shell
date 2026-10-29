import QtQuick
import "../../core"

// DecorHost (W53.0a, K80; docs/ux/styles.md "Slots, as data"): loads the look's component for one slot — the token
// `decor.<slot>`, a name loaded as `decor/<slot>/<Name>.qml` (kebab-case → PascalCase), as FrameHost does for frames. The
// name is data and never compared (rule 4). Nothing is made while the look names none (`has` false): the caller then
// draws its own default, today's shell, so a look without the slot stays pixel-identical. The typed hosts beside this
// file (TitleHost, StartHost, TrayWell, MenuStyle, ScrollStyle, TooltipStyle) bind their contract's properties onto the
// loaded part; each slot's contract is `decor/<slot>/<Slot>Base.qml`.
Loader {
    id: dh
    property string slot: ""
    readonly property string name: Theme.slot(slot)
    readonly property string file: Theme.pascal(name)
    // The look names a part for this slot (it may still be loading: `ready`).
    readonly property bool has: file !== ""
    readonly property bool ready: status === Loader.Ready && item !== null
    active: has
    source: has ? Qt.resolvedUrl(slot + "/" + file + ".qml") : ""
}
