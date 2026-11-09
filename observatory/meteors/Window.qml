import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
    FloatingWindow {
        id: window
        title: qsTr("OMANOVA Observatory · Meteor shower preview")
        color: "#070d1b"
        implicitWidth: 850
        implicitHeight: 760
        minimumSize: Qt.size(390, 420)
        onVisibleChanged: if (!visible) Qt.quit()
        Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
        IpcHandler {
            target: "omasky-meteors-preview"
            function count(): int { return page.catalog?.showers.length ?? 0 }
        }
        ScrollView {
            id: scroll
            anchors.fill: parent
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            clip: true
            MeteorPage { id: page; width: scroll.availableWidth }
        }
    }
}
