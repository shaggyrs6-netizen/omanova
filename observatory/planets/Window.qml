import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
    FloatingWindow {
        id: window
        title: qsTr("Omasky Observatory · Planets preview")
        color: "#070d1b"
        implicitWidth: 850
        implicitHeight: 740
        minimumSize: Qt.size(380, 420)
        onVisibleChanged: if (!visible) Qt.quit()

        PlanetPage { id: page; anchors.fill: parent }
        Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
        IpcHandler {
            target: "omasky-planets-preview"
            function summary(): string {
                return JSON.stringify({ planets: page.dataSet?.highlights.length,
                    pairings: page.dataSet?.pairings.length, fixture: page.dataSet?.fixture })
            }
            function showPairings(): void { page.section = 1 }
        }
    }
}
