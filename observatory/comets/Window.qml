import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
    FloatingWindow {
        id: window
        title: qsTr("Omasky Observatory · Comets preview")
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
            CometPage { id: page; width: scroll.availableWidth }
        }
        Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
        IpcHandler {
            target: "omasky-comets-preview"
            function summary(): string {
                return JSON.stringify({ count: page.catalog?.targets.length,
                    available: page.catalog?.available, fixture: page.catalog?.fixture,
                    windows: page.catalog?.targets.map(target => target.windows.length) })
            }
        }
    }
}
