import QtQuick
import QtQuick.Controls
SpinBox {
    id: control
    editable: true; font.pixelSize: 14; implicitHeight: 38; implicitWidth: 110
    palette.base: "#0a1424"; palette.button: "#15253c"; palette.window: "#101c32"
    palette.text: "#eef5ff"; palette.buttonText: "#eef5ff"; palette.windowText: "#eef5ff"
    palette.highlight: "#365c77"; palette.highlightedText: "#ffffff"
    background: Rectangle { radius: 6; color: "#15253c"; border.color: control.activeFocus ? "#70edeb" : "#36516d" }
}
