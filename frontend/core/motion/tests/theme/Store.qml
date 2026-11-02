pragma Singleton
import QtQuick

// A stand-in for the shell's Store: Theme reads `docs.theme.tokens` (theme_case.qml sets them).
QtObject {
    property var docs: ({ theme: { tokens: {} } })
    property var theme: null
}
