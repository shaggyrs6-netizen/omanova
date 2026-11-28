import "../../qml/Omanova" as App
import QtQuick
import QtQuick.Layouts

App.InstrumentCard {
    id: card
    required property var context
    required property double clock
    required property bool fixture
    required property bool enabledDownloads
    readonly property var plasma: current(context?.plasma)
    readonly property var field: current(context?.field)
    spacing: 10

    function current(row) {
        if (!row) return null
        const age = clock - Date.parse(row.observed)
        return fixture || (age >= 0 && age < 900000) ? row : null
    }
    function metric(value, unit, decimals) {
        return Number.isFinite(value) ? value.toFixed(decimals) + " " + unit : qsTr("Unavailable")
    }
    function measured(row) {
        return row ? qsTr("%1 · %2 UTC").arg(row.source).arg(row.observed.slice(11, 16)) :
            qsTr("Missing or older than 15 minutes")
    }

    component Copy: Text {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        color: App.Palette.ink
        font.pixelSize: 14
    }
    Copy { text: qsTr("Solar wind near Earth"); font.pixelSize: 20; font.bold: true }
    Copy {
        visible: !!card.context && (card.fixture || !card.enabledDownloads || card.context.fetchIssue === true)
        text: card.fixture ? qsTr("Sample readings") : !card.enabledDownloads ?
            qsTr("Aurora downloads paused. Only recent cached readings can appear.") :
            qsTr("NOAA refresh incomplete. Recent readings may still be available.")
        color: App.Palette.warning
    }
    GridLayout {
        Layout.fillWidth: true
        columns: width >= 620 ? 2 : 1
        columnSpacing: 24
        rowSpacing: 12
        ColumnLayout {
            Layout.fillWidth: true
            Copy { text: qsTr("Plasma"); font.bold: true }
            Copy { text: qsTr("Speed · %1").arg(card.metric(card.plasma?.speed, "km/s", 0)) }
            Copy { text: qsTr("Proton density · %1").arg(card.metric(card.plasma?.density, "cm⁻³", 1)) }
            Copy { text: card.measured(card.plasma); color: App.Palette.muted }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Copy { text: qsTr("Magnetic field"); font.bold: true }
            Copy {
                readonly property var bz: card.field?.bz
                text: qsTr("Bz (GSM) · %1").arg(card.metric(bz, "nT", 1)) +
                    (bz < 0 ? qsTr(" · southward") : bz > 0 ? qsTr(" · northward") : "")
            }
            Copy { text: qsTr("Total field · %1").arg(card.metric(card.field?.bt, "nT", 1)) }
            Copy { text: card.measured(card.field); color: App.Palette.muted }
        }
    }
    Copy {
        text: qsTr("Southward Bz can favour geomagnetic activity. These are upstream measurements. Use the aurora outlook, local darkness and weather to judge a viewing chance.")
        color: App.Palette.muted
    }
    App.ActionButton {
        text: qsTr("NOAA solar wind ↗")
        onClicked: Qt.openUrlExternally("https://www.spaceweather.gov/products/solar-wind")
    }
}
