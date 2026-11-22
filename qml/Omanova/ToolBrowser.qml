import "." as App
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

GridLayout {
    id: browser
    required property var entries
    required property string heading
    required property Component detail
    property var label: row => row.name
    property var subtitle: row => ""
    property string selection: ""
    function key(row) { return JSON.stringify([row.id ?? "", label(row), subtitle(row)]) }
    readonly property int selectedIndex: Math.max(0, entries.findIndex(row => key(row) === selection))
    readonly property var selectedRow: entries[selectedIndex] ?? null
    visible: entries.length > 0
    Layout.fillWidth: true
    Layout.leftMargin: 18
    Layout.rightMargin: 18
    columns: width >= 720 ? 2 : 1
    rowSpacing: 10
    columnSpacing: 12
    App.InstrumentCard {
        Layout.preferredWidth: 270
        RowLayout {
            Layout.fillWidth: true
            Text { Layout.fillWidth:true; text:browser.heading; color:App.Palette.ink; font.bold:true; font.pixelSize:18; wrapMode:Text.Wrap }
            Text { text:String(browser.entries.length); color:App.Palette.muted }
        }
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, browser.columns === 2 ? 350 : 155)
            clip:true; spacing:4; model:browser.entries
            ScrollBar.vertical: ScrollBar {}
            delegate: Button {
                id: choice
                required property int index
                required property var modelData
                width:list.width
                implicitHeight:Math.max(42, contentItem.implicitHeight + 16)
                leftPadding:10; rightPadding:10
                readonly property bool current:index===browser.selectedIndex
                Accessible.name:[browser.label(modelData),browser.subtitle(modelData)].filter(Boolean).join(" · ")
                Accessible.selected:current
                onClicked:browser.selection=browser.key(modelData)
                background:Rectangle {
                    radius:5; color:choice.current?App.Palette.hover:App.Palette.field
                    border.color:choice.activeFocus||choice.current?App.Palette.accent:App.Palette.line
                }
                contentItem:ColumnLayout {
                    spacing:2
                    Text { Layout.fillWidth:true; text:browser.label(choice.modelData); color:App.Palette.ink; font.bold:true; wrapMode:Text.Wrap; textFormat:Text.PlainText }
                    Text { Layout.fillWidth:true; text:browser.subtitle(choice.modelData); visible:!!text; color:App.Palette.muted; wrapMode:Text.Wrap; textFormat:Text.PlainText }
                }
            }
        }
    }
    ColumnLayout {
        Layout.fillWidth:true; Layout.minimumWidth:0; Layout.preferredWidth:650; Layout.alignment:Qt.AlignTop
        Repeater { model:browser.selectedRow?[browser.selectedRow]:[]; delegate:browser.detail }
    }
}
