import "." as App
import QtQuick
import QtQuick.Controls
Button {
    id: control
    implicitHeight: 42
    leftPadding: 14
    rightPadding: 14
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    contentItem: Text {
        text: control.text
        textFormat: Text.PlainText
        color: control.enabled ? App.Palette.ink : App.Palette.muted
        font.pixelSize: 14
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
        radius: 6
        color: control.down || control.hovered ? App.Palette.hover : App.Palette.button
        border.color: control.visualFocus ? App.Palette.accent : App.Palette.border
    }
}
