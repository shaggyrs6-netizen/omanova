import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
    FloatingWindow {
        title: qsTr("OMANOVA Observatory · Aurora preview")
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
            AuroraPage {
                id: page
                width: scroll.availableWidth
                onExampleChanged: scroll.contentItem.contentY = 0
            }
        }
        Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
        IpcHandler {
            target: "omasky-aurora-preview"
            function example(show: bool): void { page.example = show }
            function summary(): string {
                return JSON.stringify({ fixture: page.catalog?.fixture, verdict: page.verdict,
                    look: page.catalog?.current.look, nights: page.catalog?.nights.length })
            }
        }
    }
}
