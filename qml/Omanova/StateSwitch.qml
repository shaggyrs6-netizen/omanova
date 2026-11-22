import "." as App
import QtQuick
import QtQuick.Controls

Switch {
    id: toggle
    required property bool current
    signal requestChange()
    text:current ? qsTr("On") : qsTr("Off")
    checked:current
    spacing:7
    implicitHeight:36
    indicator:Rectangle {
        x:toggle.leftPadding;y:(toggle.height-height)/2
        implicitWidth:40;implicitHeight:23;radius:12
        color:toggle.current?App.Palette.shade:App.Palette.field
        border.color:toggle.activeFocus||toggle.current?App.Palette.accent:App.Palette.border
        Rectangle {
            x:toggle.current?20:4;y:4;width:15;height:15;radius:8
            color:toggle.current?App.Palette.accent:App.Palette.muted
        }
    }
    contentItem:Text {
        leftPadding:toggle.indicator.width+toggle.spacing
        text:toggle.text;color:toggle.current?App.Palette.accent:App.Palette.muted
        verticalAlignment:Text.AlignVCenter
    }
    onClicked:{requestChange();checked=Qt.binding(()=>current)}
}
