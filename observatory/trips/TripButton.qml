import "./qml/Omanova" as App
import QtQuick
import QtQuick.Controls
Button {
    id: control
    font.pixelSize: 14; implicitHeight: 38; leftPadding: 12; rightPadding: 12
    contentItem: Text { text: control.text; textFormat: Text.PlainText; color: control.enabled ? App.Palette.ink : App.Palette.muted; font: control.font; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
    background: Rectangle { radius: 6; color: control.down ? App.Palette.button : control.hovered ? App.Palette.hover : App.Palette.button; border.color: control.visualFocus ? App.Palette.accent : App.Palette.border }
}
