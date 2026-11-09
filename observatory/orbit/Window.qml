import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
    FloatingWindow {
        id: window
        title: "OMANOVA Observatory · Orbit preview"
        color: "#070d1b"
        implicitWidth: 1100
        implicitHeight: 740
        minimumSize: Qt.size(360, 420)
        onVisibleChanged: if (!visible) Qt.quit()

        ScrollView {
            id: scroll
            anchors.fill: parent
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            OrbitPage {
                id: ui
                width: scroll.availableWidth
            }
        }

        IpcHandler {
            target: "omasky-orbit-preview"
            function station(index: int): void { if (index === 0 || index === 1) ui.stationIndex = index }
            function scrub(index: int): void { if (ui.selected) ui.sampleIndex = Math.max(0, Math.min(index, ui.selected.pass.length - 1)) }
            function summary(): string {
                return JSON.stringify({fixture: ui.orbitData?.fixture, name: ui.station?.name, passes: ui.station?.passes.length,
                    points: ui.selected?.track.length, sample: ui.sample?.time, status: ui.status()})
            }
            function capture(): void {
                if (ui.orbitData?.fixture) {
                    const path = Quickshell.env("OMASKY_ORBIT")
                    ui.grabToImage(result => result.saveToFile(path.replace("tracks.json", "orbit.png")))
                }
            }
            function close(): void { Qt.quit() }
        }
    }
}
