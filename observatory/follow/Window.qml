import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    FloatingWindow {
        title:"OMANOVA · Launch-following preview"
        color:page.backgroundColour;implicitWidth:1080;implicitHeight:800;minimumSize:Qt.size(460,480)
        onVisibleChanged:if(!visible)Qt.quit()
        FollowPage { id:page;anchors.fill:parent }
        IpcHandler {target:"omanova-follow-window";function close():void {Qt.quit()}}
    }
}
