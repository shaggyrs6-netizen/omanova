import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: page
    required property var sky
    signal inspect(var selected)
    property bool stationDetail: false
    property alias mode: detailed.mode
    function summary() { return stationDetail ? detailed.summary() : JSON.stringify({count: rows.length}) }
    spacing: 14
    readonly property var rows: sky.plannedEvents.filter(row =>
        (kinds.currentIndex === 0 || row.kind === kinds.currentText)
        && (horizon.currentIndex === 2 || Date.parse(row.start) <= sky.now + (horizon.currentIndex === 0 ? 1 : 7)*86400000)
        && (!localOnly.checked || row.visibility === "possible"))
    component Copy: Text { Layout.fillWidth: true; Layout.leftMargin: 22; Layout.rightMargin: 22; wrapMode: Text.Wrap; textFormat: Text.PlainText; color: "#eef5ff"; font.pixelSize: 15 }
    Copy { Layout.topMargin: 22; text: qsTr("Your observing timeline"); font.pixelSize: 32; font.bold: true }
    Copy { text: qsTr("Local viewing windows across the Observatory. Unconfirmed launches and stale geometry remain inspectable. Times use your system time zone."); color: "#a7b7ce" }
    Flow {
        Layout.fillWidth: true; Layout.leftMargin: 22; Layout.rightMargin: 22; spacing: 8
        ComboBox {
            implicitWidth: 170
            font.pixelSize: 14; implicitHeight: 37
            palette.base: "#0a1424"; palette.button: "#15253c"; palette.window: "#101c32"
            palette.text: "#eef5ff"; palette.buttonText: "#eef5ff"; palette.windowText: "#eef5ff"
            palette.highlight: "#365c77"; palette.highlightedText: "#ffffff"; palette.mid: "#36516d"
            background: Rectangle { radius: 6; color: "#15253c"; border.color: parent.activeFocus ? "#70edeb" : "#36516d" }
 id: horizon; model: [qsTr("Next 24 hours"), qsTr("Next 7 days"), qsTr("All available")]; Accessible.name: qsTr("Timeline range") }
        ComboBox {
            implicitWidth: 170
            font.pixelSize: 14; implicitHeight: 37
            palette.base: "#0a1424"; palette.button: "#15253c"; palette.window: "#101c32"
            palette.text: "#eef5ff"; palette.buttonText: "#eef5ff"; palette.windowText: "#eef5ff"
            palette.highlight: "#365c77"; palette.highlightedText: "#ffffff"; palette.mid: "#36516d"
            background: Rectangle { radius: 6; color: "#15253c"; border.color: parent.activeFocus ? "#70edeb" : "#36516d" }
 id: kinds; model: [qsTr("All types"), "station", "satellite", "moon", "meteor", "planet", "conjunction", "comet", "eclipse", "launch", "plume", "train", "aurora"]; Accessible.name: qsTr("Event type") }
        CheckBox {
                palette.windowText: "#eef5ff"; palette.text: "#eef5ff"; palette.buttonText: "#eef5ff"; palette.button: "#15253c"; palette.base: "#0a1424"; palette.highlight: "#70edeb"; id: localOnly; text: qsTr("Local possibilities only") }
        Button {
            font.pixelSize: 14; implicitHeight: 37; leftPadding: 12; rightPadding: 12
            palette.buttonText: "#eef5ff"; palette.text: "#eef5ff"; palette.button: "#15253c"
            background: Rectangle { radius: 6; color: parent.down ? "#243a54" : parent.hovered ? "#1a3049" : "#15253c"; border.color: parent.visualFocus ? "#70edeb" : "#36516d" }
 text: page.stationDetail ? qsTr("Unified timeline") : qsTr("Station and launch detail"); onClicked: page.stationDetail = !page.stationDetail }
    }
    Copy { visible: page.sky.plannerStale; text: qsTr("Planning data is missing or stale. Inspect cached geometry below; recommendations and alerts are withheld."); color: "#ffcc7b" }
    Copy { visible: (page.sky.planning?.issues || []).length > 0; text: (page.sky.planning?.issues || []).join(" · "); color: "#ffcc7b" }
    Copy { visible: !page.stationDetail && !page.rows.length; text: qsTr("No events in this selection. Try a longer range or another type.") }
    Repeater {
        model: page.stationDetail ? [] : page.rows.slice(0,100)
        OpportunityCard { Layout.leftMargin: 22; Layout.rightMargin: 22; required property var modelData; event: modelData; sky: page.sky; onInspect: selected => page.inspect(selected) }
    }
    Copy { visible: !page.stationDetail && page.rows.length > 100; text: qsTr("Showing the first 100 events. Filter by type to narrow the list.") }
    EventsPage {
        id: detailed
        visible: page.stationDetail; Layout.fillWidth: true; sky: page.sky
        onInspect: eventId => page.inspect({ kind: "station", station_id: eventId, page: 1 })
    }
}
