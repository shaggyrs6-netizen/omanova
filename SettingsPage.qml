import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: page
    required property var sky
    property bool compact: false
    readonly property bool trial: Quickshell.env("OMASKY_SETTINGS_PREVIEW") === "1" && sky.fixture
    readonly property var preferences: sky.data?.settings ?? ({ profiles: [], online: false, weather: false })
    readonly property bool busy: sky.settingsWorker.running
    readonly property int gutter: compact ? 0 : 22
    property var lookupRows: []
    property string lookupMessage: ""
    property string lookupInput: ""
    property bool lookupCooling: false
    Timer { interval: 5000; running: page.lookupCooling; onTriggered: page.lookupCooling = false }
    Process {
        id: lookup
        stdinEnabled: true
        command: [page.sky.runtime + "/.venv/bin/python", page.sky.runtime + "/place_lookup.py"]
        environment: ({ "OPENBLAS_NUM_THREADS": "1" })
        onStarted: { write(page.lookupInput); page.lookupInput = ""; stdinEnabled = false }
        stdout: StdioCollector { id: lookupOutput }
        onExited: function(code) {
            if (code === 0) {
                try { page.lookupRows = JSON.parse(lookupOutput.text); page.lookupMessage = page.lookupRows.length ? "Select a result to fill the fields, then save or use temporarily." : "No places found." }
                catch (e) { page.lookupMessage = "Lookup unavailable." }
            } else page.lookupMessage = "Lookup unavailable. Use manual coordinates or try again later."
        }
    }
    signal openCompact()
    spacing: 12

    component Copy: Text {
        Layout.fillWidth: true
        color: "#eef5ff"
        font.pixelSize: 14
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }
    component Heading: Copy {
        font.pixelSize: 21
        font.bold: true
    }
    component Action: Button {
        id: action
        enabled: !page.busy
        implicitHeight: 37
        leftPadding: 12
        rightPadding: 12
        contentItem: Text {
            text: action.text
            textFormat: Text.PlainText
            color: action.enabled ? "#eef5ff" : "#8190a6"
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 6
            color: action.down ? "#243a54" : action.hovered ? "#1a3049" : "#15253c"
            border.color: action.visualFocus ? "#70edeb" : "#36516d"
        }
    }
    component Field: TextField {
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        color: "#eef5ff"
        placeholderTextColor: "#a7b7ce"
        selectionColor: "#365c77"
        selectedTextColor: "#ffffff"
        implicitHeight: 37
        Accessible.name: placeholderText
        background: Rectangle {
            color: "#0a1424"
            radius: 5
            border.color: parent.activeFocus ? "#70edeb" : "#36516d"
        }
    }
    component Card: Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: page.gutter
        Layout.rightMargin: page.gutter
        color: "#101c32"
        border.color: "#2a3e58"
        radius: 10
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: page.gutter
        Layout.rightMargin: page.gutter
        Layout.topMargin: page.compact ? 4 : 20
        visible: !page.compact
        spacing: 7
        Copy { text: qsTr("OMANOVA OBSERVATORY  /  CONFIGURATION"); color: "#70edeb"; font.letterSpacing: 1.3 }
        Heading { text: qsTr("Settings"); font.pixelSize: 32 }
        Copy {
            visible: page.trial
            text: qsTr("Offline preview. These controls use sample data and save changes only in this trial.")
            color: "#a7b7ce"
        }
        Action {
            visible: page.trial
            text: qsTr("Show compact panel preview")
            onClicked: page.openCompact()
        }
    }

    Card {
        implicitHeight: placeForm.implicitHeight + 32
        ColumnLayout {
            id: placeForm
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10
            Heading { text: qsTr("Observing location") }
            Copy {
                text: page.sky.data?.place
                    ? (page.preferences.temporary ? qsTr("Temporary · %1") : qsTr("Active · %1"))
                        .arg(page.sky.data.place.name)
                    : qsTr("No active location")
                color: "#70edeb"
            }
            RowLayout {
                Layout.fillWidth: true
                ComboBox {
                    id: saved
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    model: page.preferences.profiles
                    textRole: "name"
                    Accessible.name: qsTr("Saved locations")
                    palette.base: "#101c32"
                    palette.button: "#15253c"
                    palette.text: "#eef5ff"
                    palette.buttonText: "#eef5ff"
                    palette.window: "#101c32"
                    palette.windowText: "#eef5ff"
                    palette.highlight: "#365c77"
                }
                Action {
                    text: qsTr("Use saved")
                    enabled: !page.busy && saved.currentIndex >= 0
                    onClicked: page.sky.run(["use", page.preferences.profiles[saved.currentIndex].id])
                }
            }
            Copy { text: qsTr("Optional city or postcode lookup sends only the text you enter to Open-Meteo/GeoNames when you press Search. It does not read your current coordinates. Place data: GeoNames."); color: "#a7b7ce" }
            RowLayout {
                Field { id: lookupQuery; placeholderText: qsTr("City or postcode, optionally country"); maximumLength: 120 }
                Action {
                    text: qsTr("Search online"); enabled: !lookup.running && !page.lookupCooling && !page.sky.fixture && lookupQuery.text.trim().length >= 2
                    onClicked: { page.lookupInput = JSON.stringify(lookupQuery.text.trim()) + "\n"; page.lookupRows = []; page.lookupMessage = "Searching…"; page.lookupCooling = true; lookup.stdinEnabled = true; lookup.running = true }
                }
            }
            Copy { text: page.lookupMessage; visible: text.length > 0 }
            Repeater {
                model: page.lookupRows
                Action {
                    required property var modelData
                    text: modelData.label
                    onClicked: { placeName.text = modelData.name; latitude.text = String(modelData.lat); longitude.text = String(modelData.lon); elevation.text = String(modelData.elevation); page.lookupRows = [] }
                }
            }
            Field { id: placeName; maximumLength: 48; placeholderText: qsTr("Place name") }
            GridLayout {
                Layout.fillWidth: true
                columns: width < 330 ? 1 : 3
                Field { id: latitude; maximumLength: 18; placeholderText: qsTr("Latitude") }
                Field { id: longitude; maximumLength: 18; placeholderText: qsTr("Longitude") }
                Field { id: elevation; maximumLength: 18; placeholderText: qsTr("Elevation m (optional)") }
            }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                Action {
                    text: qsTr("Save & use")
                    enabled: !page.busy && page.sky.supports("save-stdin")
                    onClicked: page.sky.run(["save-stdin"], [placeName.text, latitude.text, longitude.text, elevation.text])
                }
                Action {
                    text: qsTr("Use temporarily")
                    enabled: !page.busy && page.sky.supports("temporary-stdin")
                    onClicked: page.sky.run(["temporary-stdin"], [placeName.text, latitude.text, longitude.text, elevation.text])
                }
            }
            Copy {
                visible: !page.sky.supports("save-stdin") || !page.sky.supports("temporary-stdin")
                text: qsTr("Update the runtime checkout and rerun ./setup-runtime to enter locations privately.")
                color: "#ffcc7b"
            }
        }
    }

    Card {
        implicitHeight: units.implicitHeight + 32
        ColumnLayout {
            id: units
            anchors.fill: parent
            anchors.margins: 16
            Heading { text: qsTr("Distance units") }
            Copy { text: page.sky.useMiles ? qsTr("Showing miles") : qsTr("Showing kilometres"); color: "#70edeb" }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                Action {
                    text: qsTr("Kilometres")
                    enabled: !page.busy && page.sky.useMiles && page.sky.supports("distance-unit")
                    onClicked: page.sky.run(["distance-unit", "km"])
                }
                Action {
                    text: qsTr("Miles")
                    enabled: !page.busy && !page.sky.useMiles && page.sky.supports("distance-unit")
                    onClicked: page.sky.run(["distance-unit", "mi"])
                }
            }
            Copy {
                visible: !page.sky.supports("distance-unit")
                text: qsTr("Update the runtime checkout and rerun ./setup-runtime, then reopen OMANOVA.")
                color: "#ffcc7b"
            }
        }
    }

    Card {
        implicitHeight: downloads.implicitHeight + 32
        ColumnLayout {
            id: downloads
            anchors.fill: parent
            anchors.margins: 16
            spacing: 9
            Heading { text: qsTr("Downloads") }
            Copy {
                text: page.preferences.online ? qsTr("Orbital data · Enabled") : qsTr("Orbital data · Paused")
                font.bold: true
            }
            Copy { text: qsTr("CelesTrak receives no observing coordinates."); color: "#a7b7ce" }
            Action {
                text: page.preferences.online ? qsTr("Pause orbital downloads") : qsTr("Enable orbital downloads")
                enabled: !page.busy && (!page.sky.fixture || page.trial)
                onClicked: page.sky.run(["online", page.preferences.online ? "off" : "on"])
            }
            Copy {
                text: !page.preferences.weather ? qsTr("Weather · Off")
                    : page.preferences.online ? qsTr("Weather · Enabled") : qsTr("Weather · Opted in, downloads paused")
                font.bold: true
            }
            Copy {
                text: qsTr("Open-Meteo receives coordinates rounded to two decimal places when downloads are enabled.")
                color: "#a7b7ce"
            }
            Action {
                text: page.preferences.weather ? qsTr("Turn weather off") : qsTr("Opt in to weather")
                enabled: !page.busy && (!page.sky.fixture || page.trial)
                onClicked: page.sky.run(["weather", page.preferences.weather ? "off" : "on"])
            }
            Copy {
                text: qsTr("Launch schedules and NOAA aurora guidance are separate opt-ins. Neither sends observing coordinates. Reopen the Observatory for launch changes, or reopen the Aurora tab for aurora changes.")
                color: "#a7b7ce"
            }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                Action {
                    text: page.preferences.launches === true ? qsTr("Pause launch downloads") : qsTr("Enable launch downloads")
                    enabled: !page.busy && (!page.sky.fixture || page.trial) && page.sky.supports("launches")
                    onClicked: page.sky.run(["launches", page.preferences.launches === true ? "off" : "on"])
                }
                Action {
                    text: page.preferences.aurora === true ? qsTr("Pause aurora downloads") : qsTr("Enable aurora downloads")
                    enabled: !page.busy && (!page.sky.fixture || page.trial) && page.sky.supports("aurora")
                    onClicked: page.sky.run(["aurora", page.preferences.aurora === true ? "off" : "on"])
                }
            }
            Action { text: qsTr("Refresh now"); onClicked: page.sky.run(["refresh"]) }
        }
    }
    Card {
        implicitHeight: observing.implicitHeight + 32
        ObservingPreferences { id: observing; anchors.fill: parent; anchors.margins: 16; sky: page.sky }
    }
    Copy {
        Layout.leftMargin: page.gutter
        Layout.rightMargin: page.gutter
        Layout.bottomMargin: 12
        visible: text.length > 0
        text: page.sky.message
        color: "#ffcc7b"
        Accessible.role: Accessible.StaticText
    }
}
