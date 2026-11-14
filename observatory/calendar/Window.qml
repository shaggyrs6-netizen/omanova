import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    FloatingWindow {
        title:"OMANOVA · Calendar export preview"
        color:page.backgroundColour;implicitWidth:1080;implicitHeight:850;minimumSize:Qt.size(480,520)
        onVisibleChanged:if(!visible)Qt.quit()
        CalendarPage {id:page;anchors.fill:parent}
        IpcHandler {target:"omanova-calendar-preview-window";function close():void {Qt.quit()}}
    }
}
