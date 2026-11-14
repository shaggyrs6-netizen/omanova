import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    FloatingWindow {
        title:"OMANOVA · Offline observing cards preview"
        color:page.backgroundColour;implicitWidth:1080;implicitHeight:850;minimumSize:Qt.size(480,520)
        onVisibleChanged:if(!visible)Qt.quit()
        OfflinePage {id:page;anchors.fill:parent}
        IpcHandler {target:"omanova-offline-preview-window";function close():void {Qt.quit()}}
    }
}
