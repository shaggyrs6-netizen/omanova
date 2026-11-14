import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    FloatingWindow {
        title:"OMANOVA · My Equipment and Sky preview"
        color:page.backgroundColour;implicitWidth:1080;implicitHeight:860;minimumSize:Qt.size(480,520)
        onVisibleChanged:if(!visible)Qt.quit()
        EquipmentPage {id:page;anchors.fill:parent}
        IpcHandler {target:"omanova-equipment-preview-window";function close():void {Qt.quit()}}
    }
}
