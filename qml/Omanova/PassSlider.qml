import "." as App
import QtQuick
import QtQuick.Controls
Slider {
    id: control
    implicitHeight: 40
    background: Rectangle {
        x: control.leftPadding
        y: control.topPadding+control.availableHeight/2-height/2
        implicitHeight: 6
        width:control.availableWidth;height:implicitHeight;radius:3
        color:App.Palette.line
        Rectangle {width:control.visualPosition*parent.width;height:parent.height;radius:3;color:App.Palette.accent}
    }
    handle: Rectangle {
        x:control.leftPadding+control.visualPosition*(control.availableWidth-width)
        y:control.topPadding+control.availableHeight/2-height/2
        implicitWidth:22;implicitHeight:22;radius:11
        color:control.pressed?App.Palette.accent:App.Palette.ink
        border.color:control.activeFocus?App.Palette.accent:App.Palette.border
        border.width:2
    }
}
