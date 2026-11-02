import QtQuick

// fade (W53.0a): fades only. Also what FormHost falls back to for a form it has no component for.
TransformForm {
    opacity: 1 - away
}
