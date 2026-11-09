import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
    FloatingWindow {
        title: "Omasky Observatory · Moon preview"
        color: "#070d1b"
        implicitWidth: 1000
        implicitHeight: 740
        minimumSize: Qt.size(360, 420)
        onVisibleChanged: if (!visible) Qt.quit()

        ScrollView {
            id: scroll
            anchors.fill: parent
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            MoonPage { id: page; width: scroll.availableWidth }
        }
        IpcHandler {
            target: "omasky-moon-preview"
            function summary(): string { return JSON.stringify(page.summary()) }
            function close(): void { Qt.quit() }
        }
    }
}
