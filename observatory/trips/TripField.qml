import "./qml/Omanova" as App
import QtQuick
import QtQuick.Controls
TextField {
    id: control
    font.pixelSize: 14; implicitHeight: 38; color: App.Palette.ink; placeholderTextColor: App.Palette.muted
    selectionColor: App.Palette.button; selectedTextColor: App.Palette.ink
    background: Rectangle { radius: 5; color: App.Palette.field; border.color: control.activeFocus ? App.Palette.accent : App.Palette.border }
}
