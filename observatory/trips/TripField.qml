import QtQuick
import QtQuick.Controls
TextField {
    id: control
    font.pixelSize: 14; implicitHeight: 38; color: "#eef5ff"; placeholderTextColor: "#a7b7ce"
    selectionColor: "#365c77"; selectedTextColor: "#ffffff"
    background: Rectangle { radius: 5; color: "#0a1424"; border.color: control.activeFocus ? "#70edeb" : "#36516d" }
}
