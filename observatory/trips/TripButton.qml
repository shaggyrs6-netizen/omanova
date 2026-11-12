import QtQuick
import QtQuick.Controls
Button {
    id: control
    font.pixelSize: 14; implicitHeight: 38; leftPadding: 12; rightPadding: 12
    contentItem: Text { text: control.text; textFormat: Text.PlainText; color: control.enabled ? "#eef5ff" : "#8190a6"; font: control.font; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
    background: Rectangle { radius: 6; color: control.down ? "#243a54" : control.hovered ? "#1a3049" : "#15253c"; border.color: control.visualFocus ? "#70edeb" : "#36516d" }
}
