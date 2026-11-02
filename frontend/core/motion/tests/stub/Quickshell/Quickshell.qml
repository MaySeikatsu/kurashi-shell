pragma Singleton
import QtQuick

// The one Quickshell call Driver makes, for the offscreen tests (qmltestrunner -import tests/stub): no scrub.
QtObject {
    function env(name) { return "" }
}
