import QtQuick
import qs.core
import qs.components

// The add form (docs/ux/webdock.md "States", `webdock.add`): a site's address and an optional name. Enter adds, Escape
// cancels (back to the strip). The daemon checks the address and refuses it with an i18n key, shown under the fields.
Rectangle {
    id: form
    property string error: ""
    signal added()
    signal cancelled()

    radius: Theme.rLg
    color: Theme.container
    activeFocusOnTab: true
    Keys.onEscapePressed: form.cancelled()

    function submit() {
        var url = urlField.text.trim()
        var title = nameField.text.trim()
        var args = { url: url }
        if (title !== "") args.title = title
        form.error = ""
        Store.act("webdock.add", args, function (done, err) {
            if (err) form.error = err.msg || "webdock.add.invalid"
            else form.added()
        })
    }

    Column {
        anchors.fill: parent
        anchors.margins: Theme.pad
        spacing: Theme.gap

        Text {
            width: parent.width
            text: I18n.tr("webdock.dock.add.title")
            color: Theme.fg
            font.pixelSize: Theme.fsLabel
            font.family: Theme.fam(text, Theme.families)
        }
        Text {
            text: I18n.tr("webdock.add.url")
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
        }
        Rectangle {
            width: parent.width
            height: Theme.controlH
            radius: Theme.rSm
            color: Theme.surface
            border.width: urlField.activeFocus ? 1 : 0
            border.color: Theme.focusRing
            TextInput {
                id: urlField
                anchors.fill: parent
                anchors.leftMargin: Theme.gap
                anchors.rightMargin: Theme.gap
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.fg
                selectByMouse: true
                clip: true
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                Accessible.role: Accessible.EditableText
                Accessible.name: I18n.tr("webdock.add.url")
                Keys.onReturnPressed: form.submit()
                Keys.onEnterPressed: form.submit()
                Keys.onEscapePressed: form.cancelled()
            }
        }
        Text {
            text: I18n.tr("webdock.dock.add.name")
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
        }
        Rectangle {
            width: parent.width
            height: Theme.controlH
            radius: Theme.rSm
            color: Theme.surface
            border.width: nameField.activeFocus ? 1 : 0
            border.color: Theme.focusRing
            TextInput {
                id: nameField
                anchors.fill: parent
                anchors.leftMargin: Theme.gap
                anchors.rightMargin: Theme.gap
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.fg
                selectByMouse: true
                clip: true
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                Accessible.role: Accessible.EditableText
                Accessible.name: I18n.tr("webdock.dock.add.name")
                Keys.onReturnPressed: form.submit()
                Keys.onEnterPressed: form.submit()
                Keys.onEscapePressed: form.cancelled()
            }
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            visible: form.error !== ""
            text: I18n.tr(form.error)
            color: Theme.error
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
        }
        Row {
            spacing: Theme.gap
            Button {
                primary: true
                label: I18n.tr("webdock.dock.add.submit")
                onClicked: form.submit()
            }
            Button {
                label: I18n.tr("webdock.dock.add.cancel")
                onClicked: form.cancelled()
            }
        }
    }

    // The address field takes the keyboard as the form opens (now, and again once the surface is laid out).
    Component.onCompleted: {
        urlField.forceActiveFocus()
        Qt.callLater(function () { urlField.forceActiveFocus() })
    }
}
