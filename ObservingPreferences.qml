import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: page
    required property var sky
    readonly property var saved: sky.data?.settings?.observing || ({})
    property var draft: ({})
    property bool dirty: false
    readonly property var kinds: ["station", "satellite", "moon", "meteor", "planet", "conjunction", "comet", "eclipse", "launch", "plume", "train", "aurora"]
    Component.onCompleted: reset()
    onSavedChanged: if (!dirty) reset()
    function reset() { draft = JSON.parse(JSON.stringify(saved)); dirty = false }
    function set(key, value) { let copy = Object.assign({}, draft); copy[key] = value; draft = copy; dirty = true }
    function toggle(key, kind, checked) {
        let values = (draft[key] || []).filter(x => x !== kind)
        if (checked) values.push(kind)
        set(key, values)
    }
    component Copy: Text {
        Layout.fillWidth: true
        color: "#eef5ff"; font.pixelSize: 14; wrapMode: Text.Wrap; textFormat: Text.PlainText
    }
    Copy { text: qsTr("Observing preferences"); font.pixelSize: 21; font.bold: true }
    Copy { text: qsTr("Choose what appears in Next opportunity. All event types remain available in the timeline."); color: "#a7b7ce" }
    Flow {
        Layout.fillWidth: true; spacing: 8
        Repeater { model: page.kinds
            CheckBox {
                palette.windowText: "#eef5ff"; palette.text: "#eef5ff"; palette.buttonText: "#eef5ff"; palette.button: "#15253c"; palette.base: "#0a1424"; palette.highlight: "#70edeb";
                required property string modelData
                text: modelData; checked: (page.draft.interests || []).includes(modelData)
                onClicked: page.toggle("interests", modelData, checked)
            }
        }
    }
    Button {
        text: page.sky.data?.settings?.alerts === true ? qsTr("Turn observing alerts off") : qsTr("Enable observing alerts")
        enabled: !page.sky.settingsWorker.running
        onClicked: page.sky.run(["alerts", page.sky.data?.settings?.alerts === true ? "off" : "on"])
        font.pixelSize: 14; implicitHeight: 37; leftPadding: 12; rightPadding: 12
        palette.buttonText: "#eef5ff"; palette.text: "#eef5ff"; palette.button: "#15253c"
        background: Rectangle { radius: 6; color: parent.down ? "#243a54" : parent.hovered ? "#1a3049" : "#15253c"; border.color: parent.visualFocus ? "#70edeb" : "#36516d" }
    }
    Copy { text: qsTr("Alert event types"); font.bold: true }
    Flow {
        Layout.fillWidth: true; spacing: 8
        Repeater { model: page.kinds
            CheckBox {
                palette.windowText: "#eef5ff"; palette.text: "#eef5ff"; palette.buttonText: "#eef5ff"; palette.button: "#15253c"; palette.base: "#0a1424"; palette.highlight: "#70edeb";
                required property string modelData
                text: modelData; checked: (page.draft.alert_types || []).includes(modelData)
                onClicked: page.toggle("alert_types", modelData, checked)
            }
        }
    }
    Copy { text: qsTr("Alerts never claim a confirmed sighting. Unconfirmed local visibility is excluded; poor or missing weather is included only if you explicitly choose Any weather."); color: "#a7b7ce" }
    GridLayout {
        Layout.fillWidth: true; columns: width < 500 ? 1 : 3
        Label { text: qsTr("Lead minutes"); color: "#eef5ff" }
        SpinBox {
            editable: true
            implicitWidth: 110
            font.pixelSize: 14; implicitHeight: 37
            palette.base: "#0a1424"; palette.button: "#15253c"; palette.window: "#101c32"
            palette.text: "#eef5ff"; palette.buttonText: "#eef5ff"; palette.windowText: "#eef5ff"
            palette.highlight: "#365c77"; palette.highlightedText: "#ffffff"; palette.mid: "#36516d"
            background: Rectangle { radius: 6; color: "#15253c"; border.color: parent.activeFocus ? "#70edeb" : "#36516d" }
 from: 1; to: 120; value: page.draft.alert_lead_minutes ?? 15; onValueModified: page.set("alert_lead_minutes", value) }
        ComboBox {
            implicitWidth: 170
            font.pixelSize: 14; implicitHeight: 37
            palette.base: "#0a1424"; palette.button: "#15253c"; palette.window: "#101c32"
            palette.text: "#eef5ff"; palette.buttonText: "#eef5ff"; palette.windowText: "#eef5ff"
            palette.highlight: "#365c77"; palette.highlightedText: "#ffffff"; palette.mid: "#36516d"
            background: Rectangle { radius: 6; color: "#15253c"; border.color: parent.activeFocus ? "#70edeb" : "#36516d" }

            model: ["Favourable", "Mixed", "Any"]
            currentIndex: Math.max(0, model.indexOf(page.draft.alert_conditions || "Favourable"))
            onActivated: page.set("alert_conditions", currentText)
            Accessible.name: qsTr("Minimum alert weather quality")
        }
    }
    GridLayout {
        Layout.fillWidth: true; columns: width < 500 ? 1 : 3
        CheckBox {
                palette.windowText: "#eef5ff"; palette.text: "#eef5ff"; palette.buttonText: "#eef5ff"; palette.button: "#15253c"; palette.base: "#0a1424"; palette.highlight: "#70edeb"; text: qsTr("Quiet hours (system time)"); checked: page.draft.quiet_enabled === true; onClicked: page.set("quiet_enabled", checked) }
        TextField {
            font.pixelSize: 14; implicitHeight: 37; color: "#eef5ff"; placeholderTextColor: "#a7b7ce"
            selectionColor: "#365c77"; selectedTextColor: "#ffffff"
            background: Rectangle { radius: 5; color: "#0a1424"; border.color: parent.activeFocus ? "#70edeb" : "#36516d" }
 text: page.draft.quiet_start || "22:00"; placeholderText: "22:00"; maximumLength: 5; Layout.preferredWidth: 85; onTextEdited: page.set("quiet_start", text) }
        TextField {
            font.pixelSize: 14; implicitHeight: 37; color: "#eef5ff"; placeholderTextColor: "#a7b7ce"
            selectionColor: "#365c77"; selectedTextColor: "#ffffff"
            background: Rectangle { radius: 5; color: "#0a1424"; border.color: parent.activeFocus ? "#70edeb" : "#36516d" }
 text: page.draft.quiet_end || "07:00"; placeholderText: "07:00"; maximumLength: 5; Layout.preferredWidth: 85; onTextEdited: page.set("quiet_end", text) }
    }
    Copy { text: qsTr("Equal quiet-hour times silence alerts all day. Changes affect future alerts; missed alerts are not replayed."); color: "#a7b7ce" }
    GridLayout {
        Layout.fillWidth: true; columns: width < 500 ? 1 : 2
        Label { text: qsTr("Minimum viewing elevation"); color: "#eef5ff" }
        SpinBox {
            editable: true
            implicitWidth: 110
            font.pixelSize: 14; implicitHeight: 37
            palette.base: "#0a1424"; palette.button: "#15253c"; palette.window: "#101c32"
            palette.text: "#eef5ff"; palette.buttonText: "#eef5ff"; palette.windowText: "#eef5ff"
            palette.highlight: "#365c77"; palette.highlightedText: "#ffffff"; palette.mid: "#36516d"
            background: Rectangle { radius: 6; color: "#15253c"; border.color: parent.activeFocus ? "#70edeb" : "#36516d" }
 from: 0; to: 90; value: page.draft.minimum_elevation ?? 10; onValueModified: page.set("minimum_elevation", value) }
    }
    Copy { text: qsTr("Satellite watchlist · up to 20 NORAD objects"); font.bold: true }
    Repeater {
        model: page.draft.watchlist || []
        RowLayout {
            required property var modelData
            Copy { text: modelData.name + " · " + modelData.number }
            Button {
            font.pixelSize: 14; implicitHeight: 37; leftPadding: 12; rightPadding: 12
            palette.buttonText: "#eef5ff"; palette.text: "#eef5ff"; palette.button: "#15253c"
            background: Rectangle { radius: 6; color: parent.down ? "#243a54" : parent.hovered ? "#1a3049" : "#15253c"; border.color: parent.visualFocus ? "#70edeb" : "#36516d" }
 text: qsTr("Remove"); onClicked: page.set("watchlist", page.draft.watchlist.filter(x => x.number !== modelData.number)) }
        }
    }
    GridLayout {
        Layout.fillWidth: true; columns: width < 500 ? 1 : 3
        TextField {
            font.pixelSize: 14; implicitHeight: 37; color: "#eef5ff"; placeholderTextColor: "#a7b7ce"
            selectionColor: "#365c77"; selectedTextColor: "#ffffff"
            background: Rectangle { radius: 5; color: "#0a1424"; border.color: parent.activeFocus ? "#70edeb" : "#36516d" }
 id: number; placeholderText: qsTr("NORAD ID"); maximumLength: 6; Layout.preferredWidth: 110; validator: IntValidator { bottom: 1; top: 999999 } }
        TextField {
            font.pixelSize: 14; implicitHeight: 37; color: "#eef5ff"; placeholderTextColor: "#a7b7ce"
            selectionColor: "#365c77"; selectedTextColor: "#ffffff"
            background: Rectangle { radius: 5; color: "#0a1424"; border.color: parent.activeFocus ? "#70edeb" : "#36516d" }
 id: name; placeholderText: qsTr("Display name"); maximumLength: 64; Layout.fillWidth: true }
        Button {
            font.pixelSize: 14; implicitHeight: 37; leftPadding: 12; rightPadding: 12
            palette.buttonText: "#eef5ff"; palette.text: "#eef5ff"; palette.button: "#15253c"
            background: Rectangle { radius: 6; color: parent.down ? "#243a54" : parent.hovered ? "#1a3049" : "#15253c"; border.color: parent.visualFocus ? "#70edeb" : "#36516d" }

            text: qsTr("Add"); enabled: number.acceptableInput && name.text.trim().length > 0 && (page.draft.watchlist || []).length < 20
            onClicked: { page.set("watchlist", (page.draft.watchlist || []).concat([{ number: Number(number.text), name: name.text.trim() }])); number.clear(); name.clear() }
        }
    }
    Copy { text: qsTr("Custom low-Earth-orbit IDs require CelesTrak data and orbital-download consent. Higher or highly eccentric orbits are not supported. A calculated pass does not establish object brightness; unknown brightness is labelled."); color: "#a7b7ce" }
    Flow {
        Layout.fillWidth: true; spacing: 8
        Button {
            font.pixelSize: 14; implicitHeight: 37; leftPadding: 12; rightPadding: 12
            palette.buttonText: "#eef5ff"; palette.text: "#eef5ff"; palette.button: "#15253c"
            background: Rectangle { radius: 6; color: parent.down ? "#243a54" : parent.hovered ? "#1a3049" : "#15253c"; border.color: parent.visualFocus ? "#70edeb" : "#36516d" }
 text: qsTr("Save observing preferences"); enabled: page.dirty && !page.sky.settingsWorker.running && page.sky.supports("preferences-stdin"); onClicked: { page.sky.run(["preferences-stdin"], page.draft); page.dirty = false } }
        Button {
            font.pixelSize: 14; implicitHeight: 37; leftPadding: 12; rightPadding: 12
            palette.buttonText: "#eef5ff"; palette.text: "#eef5ff"; palette.button: "#15253c"
            background: Rectangle { radius: 6; color: parent.down ? "#243a54" : parent.hovered ? "#1a3049" : "#15253c"; border.color: parent.visualFocus ? "#70edeb" : "#36516d" }
 text: qsTr("Undo edits"); enabled: page.dirty; onClicked: page.reset() }
    }
}
