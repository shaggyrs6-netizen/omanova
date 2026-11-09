import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
    FloatingWindow {
        id: window
        title: qsTr("OMANOVA Observatory · Twilight launch plumes preview")
        color: "#070d1b"
        implicitWidth: 870
        implicitHeight: 740
        minimumSize: Qt.size(380, 420)
        onVisibleChanged: if (!visible) Qt.quit()

        ScrollView {
            id: scroll
            anchors.fill: parent
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            clip: true
            PlumePage {
                id: page
                width: scroll.availableWidth
                onExampleChanged: scroll.contentItem.contentY = 0
            }
        }
        Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
        IpcHandler {
            target: "omasky-plumes-preview"
            function example(show: bool): void { page.example = show }
            function summary(): string {
                return JSON.stringify({ fixture: page.catalog?.fixture, fresh: page.catalog?.fresh,
                    count: page.catalog?.launches.length, candidates: page.candidates })
            }
        }
    }
}
