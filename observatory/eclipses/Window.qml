import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
    FloatingWindow {
        id: window
        title: qsTr("OMANOVA Observatory · Eclipses preview")
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
            EclipsePage { id: page; width: scroll.availableWidth }
        }
        Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
        IpcHandler {
            target: "omasky-eclipses-preview"
            function summary(): string {
                return JSON.stringify({ solar: page.catalog?.solar.length, lunar: page.catalog?.lunar.length,
                    fixture: page.catalog?.fixture })
            }
        }
    }
}
