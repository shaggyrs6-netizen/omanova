import "./qml/Omanova" as App
import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    IpcHandler { target:"omanova-terrain-preview"; function close():void {Qt.quit()} }
    FloatingWindow {
        title: "OMANOVA · Terrain horizon preview"
        color: App.Palette.background
        implicitWidth: 1160; implicitHeight: 820
        minimumSize: Qt.size(480,460)
        onVisibleChanged: if(!visible)Qt.quit()
        TripPage { anchors.fill: parent }
    }
}
