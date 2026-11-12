import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: card
    required property var event
    required property var sky
    property bool hero: false
    signal inspect(var selected)
    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + 32
    color: "#101c32"; border.color: "#2a3e58"; radius: 12
    component Copy: Text {
        Layout.fillWidth: true; color: "#eef5ff"; font.pixelSize: 14
        wrapMode: Text.Wrap; textFormat: Text.PlainText
    }
    ColumnLayout {
        id: content
        anchors.fill: parent; anchors.margins: 16; spacing: 9
        Copy { text: (card.hero ? qsTr("NEXT OPPORTUNITY · ") : "") + card.event.kind.toUpperCase(); color: "#70edeb"; font.pixelSize: 12 }
        Copy { text: card.event.name; font.pixelSize: card.hero ? 32 : 22; font.bold: true }
        Copy {
            text: card.sky.countdown(card.event.start) + " · " + Qt.formatDateTime(new Date(card.event.start), "ddd d MMM · HH:mm") + " – " + Qt.formatDateTime(new Date(card.event.end), "HH:mm")
            color: "#70edeb"; font.pixelSize: card.hero ? 23 : 16
        }
        Copy { text: card.event.assessment; color: card.event.conditions.label === "Poor" || card.event.visibility !== "possible" ? "#ffcc7b" : "#a7b7ce" }
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                Copy { text: card.event.look.direction ? qsTr("Suggested look %1 · %2 · %3° true · %4° up").arg(Qt.formatDateTime(new Date(card.event.look.time || card.event.start), "ddd HH:mm")).arg(card.event.look.direction).arg(Math.round(card.event.look.az)).arg(Math.round(card.event.look.el)) : qsTr("Viewing direction unconfirmed") }
                Copy { text: card.event.reason; color: "#a7b7ce" }
                Copy { text: card.event.conditions.reason; color: "#a7b7ce" }
            }
            Compass {
                visible: card.hero && card.event.look.az !== null && card.event.look.el !== null
                Layout.preferredWidth: card.width < 500 ? 110 : 180
                Layout.preferredHeight: Layout.preferredWidth
                points: visible ? [{ az: card.event.look.az, el: card.event.look.el, visible: true }] : []
            }
        }
        Copy { visible: !!card.event.safety; text: card.event.safety; color: "#ffcc7b"; font.bold: true }
        Copy {
            visible: card.hero
            text: qsTr("Ranking: timing %1 · height %2 · weather %3 · rarity %4 · brief window %5. %6")
                .arg(card.event.score_parts.time + card.event.score_parts.happeningNow).arg(card.event.score_parts.elevation)
                .arg(card.event.score_parts.weather).arg(card.event.score_parts.rarity).arg(card.event.score_parts.briefWindow || 0)
                .arg(qsTr("Only your selected interests and suitable geometry qualify; this is not a sighting probability."))
            color: "#a7b7ce"; font.pixelSize: 12
        }
        RowLayout {
            Button {
            font.pixelSize: 14; implicitHeight: 37; leftPadding: 12; rightPadding: 12
            palette.buttonText: "#eef5ff"; palette.text: "#eef5ff"; palette.button: "#15253c"
            background: Rectangle { radius: 6; color: parent.down ? "#243a54" : parent.hovered ? "#1a3049" : "#15253c"; border.color: parent.visualFocus ? "#70edeb" : "#36516d" }
 text: qsTr("Explore details"); onClicked: card.inspect(card.event) }
            Button {
            font.pixelSize: 14; implicitHeight: 37; leftPadding: 12; rightPadding: 12
            palette.buttonText: "#eef5ff"; palette.text: "#eef5ff"; palette.button: "#15253c"
            background: Rectangle { radius: 6; color: parent.down ? "#243a54" : parent.hovered ? "#1a3049" : "#15253c"; border.color: parent.visualFocus ? "#70edeb" : "#36516d" }
 text: qsTr("Source"); visible: !!card.event.source; onClicked: if (/^https:\/\//.test(card.event.source)) Qt.openUrlExternally(card.event.source) }
        }
    }
}
