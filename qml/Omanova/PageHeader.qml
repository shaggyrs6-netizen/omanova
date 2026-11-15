import "." as App
import QtQuick
import QtQuick.Layouts
ColumnLayout {
    id: header
    property string title: ""
    property string eyebrow: ""
    property string description: ""
    Layout.fillWidth: true
    spacing: 7
    Text {
        visible: !!header.eyebrow
        Layout.fillWidth: true
        text: header.eyebrow
        textFormat: Text.PlainText
        color: App.Palette.accent
        font.pixelSize: 12
        font.weight: Font.DemiBold
        font.letterSpacing: 1.1
        wrapMode: Text.Wrap
    }
    Text {
        Layout.fillWidth: true
        text: header.title
        textFormat: Text.PlainText
        color: App.Palette.ink
        font.pixelSize: header.width < 500 ? 26 : 32
        font.weight: Font.DemiBold
        wrapMode: Text.Wrap
        Accessible.role: Accessible.Heading
    }
    Text {
        visible: !!header.description
        Layout.fillWidth: true
        text: header.description
        textFormat: Text.PlainText
        color: App.Palette.muted
        font.pixelSize: 14
        wrapMode: Text.Wrap
    }
}
