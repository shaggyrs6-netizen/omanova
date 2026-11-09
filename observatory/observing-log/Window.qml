import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

ShellRoot {
    FloatingWindow {
        title: qsTr("OMANOVA Observatory · Observing log preview")
        color: "#070d1b"
        implicitWidth: 860
        implicitHeight: 740
        minimumSize: Qt.size(380, 420)
        onVisibleChanged: if (!visible) Qt.quit()

        ScrollView {
            id: scroll
            anchors.fill: parent
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            clip: true
            ObservingLogPage { id: page; width: scroll.availableWidth }
        }
        IpcHandler {
            target: "omasky-observing-log-preview"
            function summary(): string {
                return JSON.stringify({ entries: page.entries.length, message: page.message })
            }
        }
    }
}
