import QtQuick
import Quickshell

ShellRoot {
    Loader {
        source: Qt.resolvedUrl(Quickshell.env("OMANOVA_PREVIEW_ENTRY"))
    }
}
