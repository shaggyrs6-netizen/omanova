import "./qml/Omanova" as App
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: card
    required property var event
    required property var sky
    property bool hero: false
    property bool whyOpen: false
    function timeRange() {
        const start=new Date(card.event.start), end=new Date(card.event.end)
        const sameMinute=Qt.formatDateTime(start,"yyyy-MM-dd HH:mm")===Qt.formatDateTime(end,"yyyy-MM-dd HH:mm")
        const fmt=sameMinute?"HH:mm:ss":"HH:mm"
        const sameDate=start.toDateString()===end.toDateString()
        return Qt.formatDateTime(start,"ddd d MMM · "+fmt)+" – "+Qt.formatDateTime(end,sameDate?fmt:"ddd d MMM · "+fmt)
    }
    signal inspect(var selected)
    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + 32
    color: App.Palette.surface; border.color: App.Palette.line; radius: 12
    component Copy: Text {
        Layout.fillWidth: true; color: App.Palette.ink; font.pixelSize: 14
        wrapMode: Text.Wrap; textFormat: Text.PlainText
    }
    ColumnLayout {
        id: content
        anchors.fill: parent; anchors.margins: 16; spacing: 9
        Copy { text: (card.hero ? qsTr("NEXT OPPORTUNITY · ") : "") + (card.event.kind || "").toUpperCase(); color: App.Palette.accent; font.pixelSize: 12 }
        Copy { text: card.event.name; font.pixelSize: card.hero ? 32 : 22; font.bold: true }
        Copy {
            text: card.sky.countdown(card.event.start) + " · " + card.timeRange()
            color: App.Palette.accent; font.pixelSize: card.hero ? 23 : 16
        }
        Copy { text: card.event.assessment; color: card.event.conditions.label === "Poor" || card.event.visibility !== "possible" ? App.Palette.warning : App.Palette.muted }
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                Copy { text: card.event.look.direction ? qsTr("Suggested look %1 · %2 · %3° true · %4° up").arg(Qt.formatDateTime(new Date(card.event.look.time || card.event.start), "ddd HH:mm")).arg(card.event.look.direction).arg(Math.round(card.event.look.az)).arg(Math.round(card.event.look.el)) : qsTr("Viewing direction unconfirmed") }
                Copy { text: card.event.reason || ""; color: App.Palette.muted }
                Copy { text: card.event.conditions.reason || "Forecast coverage unknown"; color: App.Palette.muted }
            }
            Compass {
                visible: card.hero && Number.isFinite(card.event.look?.az) && Number.isFinite(card.event.look?.el)
                Layout.preferredWidth: card.width < 500 ? 110 : 180
                Layout.preferredHeight: Layout.preferredWidth
                points: visible ? [{ az: card.event.look.az, el: card.event.look.el, visible: true }] : []
            }
        }
        Copy { visible: !!card.event.safety; text: card.event.safety || ""; color: App.Palette.warning; font.bold: true }
        Copy {
            visible: card.whyOpen
            text: qsTr("Ranking: timing %1 · height %2 · weather %3 · rarity %4 · brief window %5. %6")
                .arg((card.event.score_parts?.time || 0) + (card.event.score_parts?.happeningNow || 0)).arg(card.event.score_parts?.elevation || 0)
                .arg(card.event.score_parts?.weather || 0).arg(card.event.score_parts?.rarity || 0).arg(card.event.score_parts?.briefWindow || 0)
                .arg(qsTr("Only your selected interests and suitable geometry qualify; this is not a sighting probability."))
            color: App.Palette.muted; font.pixelSize: 12
        }
        Flow {
            Layout.fillWidth: true;spacing:8
            App.ActionButton {text:qsTr("Explore details");onClicked:card.inspect(card.event)}
            App.ActionButton {text:card.whyOpen?qsTr("Hide reasoning"):qsTr("Why this pick?");onClicked:card.whyOpen=!card.whyOpen}
            App.ActionButton {text:qsTr("Source");visible:!!card.event.source;onClicked:if(/^https:\/\//.test(card.event.source))Qt.openUrlExternally(card.event.source)}
        }
    }
}
