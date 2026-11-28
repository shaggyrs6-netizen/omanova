import "../qml/Omanova" as App
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

App.InstrumentCard {
    id: card
    required property var hours
    required property bool weatherEnabled
    required property bool fixture
    required property var distanceLabel
    readonly property var selected: hours[picker.currentIndex] ?? null
    spacing: 10

    component Copy: Text {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        font.pixelSize: 14
        color: App.Palette.ink
    }
    Copy {
        text: qsTr("Seeing & transparency")
        font.pixelSize: 20
        font.bold: true
    }
    Copy {
        visible: card.fixture
        text: qsTr("Sample forecast")
        color: App.Palette.warning
    }
    ComboBox {
        id: picker
        visible: card.hours.length > 0
        Layout.fillWidth: true
        Layout.maximumWidth: 280
        model: card.hours.map(row => row.label)
        Accessible.name: qsTr("Optical conditions forecast hour")
        palette.base: App.Palette.field
        palette.button: App.Palette.button
        palette.window: App.Palette.surface
        palette.text: App.Palette.ink
        palette.buttonText: App.Palette.ink
        palette.windowText: App.Palette.ink
    }
    Copy {
        visible: !card.selected
        text: card.weatherEnabled ? qsTr("No current forecast for this location.")
                                  : qsTr("Enable weather downloads to see an estimate.")
        color: App.Palette.muted
    }
    GridLayout {
        Layout.fillWidth: true
        visible: !!card.selected
        columns: width >= 630 ? 2 : 1
        columnSpacing: 22
        rowSpacing: 12
        ColumnLayout {
            Layout.fillWidth: true
            Copy { text: qsTr("Seeing · wind proxy"); font.bold: true }
            Copy {
                text: card.selected?.seeing ?? qsTr("Unknown")
                color: card.selected?.seeing ? App.Palette.accent : App.Palette.muted
            }
            Copy {
                visible: !!card.selected?.seeing
                text: visible ? qsTr("Wind · surface %1 · 850 hPa %2 · 200 hPa %3 km/h")
                    .arg(Math.round(card.selected.surfaceWind)).arg(Math.round(card.selected.lowerWind))
                    .arg(Math.round(card.selected.upperWind)) : ""
                color: App.Palette.muted
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Copy { text: qsTr("Transparency · weather proxy"); font.bold: true }
            Copy {
                text: card.selected?.transparency ?? qsTr("Unknown")
                color: card.selected?.transparency ? App.Palette.accent : App.Palette.muted
            }
            Copy {
                visible: !!card.selected?.transparency
                text: visible ? qsTr("%1% cloud · %2% humidity · %3 surface visibility")
                    .arg(Math.round(card.selected.cloud)).arg(Math.round(card.selected.humidity))
                    .arg(card.distanceLabel(card.selected.visibility)) : ""
                color: App.Palette.muted
            }
        }
    }
    Copy {
        text: qsTr("Coarse planning estimates. The forecast does not measure atmospheric steadiness or extinction. Local turbulence, haze, smoke and moonlight can change the view.")
        color: App.Palette.muted
    }
}
