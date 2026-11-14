import "./qml/Omanova" as App
import QtQuick
import QtQuick.Controls
ComboBox {
    id: control
    font.pixelSize: 14; implicitHeight: 38; implicitWidth: 200
    palette.base: App.Palette.field; palette.button: App.Palette.button; palette.window: App.Palette.surface
    palette.text: App.Palette.ink; palette.buttonText: App.Palette.ink; palette.windowText: App.Palette.ink
    palette.highlight: App.Palette.button; palette.highlightedText: App.Palette.ink
    background: Rectangle { radius: 6; color: App.Palette.button; border.color: control.activeFocus ? App.Palette.accent : App.Palette.border }
}
