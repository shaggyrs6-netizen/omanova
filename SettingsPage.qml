import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

ColumnLayout {
    id: page
    required property var sky
    property bool compact: false
    readonly property bool trial: Quickshell.env("OMASKY_SETTINGS_PREVIEW") === "1" && sky.fixture
    readonly property var preferences: sky.data?.settings ?? ({ profiles: [], online: false, weather: false })
    readonly property bool busy: sky.settingsWorker.running
    readonly property int gutter: compact ? 0 : 22
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
        Copy { text: qsTr("OMASKY OBSERVATORY  /  CONFIGURATION"); color: "#70edeb"; font.letterSpacing: 1.3 }
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
                    onClicked: page.sky.run(["save", placeName.text, latitude.text, longitude.text, elevation.text])
                }
                Action {
                    text: qsTr("Use temporarily")
                    onClicked: page.sky.run(["temporary", placeName.text, latitude.text, longitude.text, elevation.text])
                }
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
                text: page.preferences.online ? qsTr("Pause downloads") : qsTr("Enable orbital downloads")
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
            Action { text: qsTr("Refresh now"); onClicked: page.sky.run(["refresh"]) }
        }
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
