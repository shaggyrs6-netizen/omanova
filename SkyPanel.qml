import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    required property var sky
    property string selection: ""
    readonly property var selected: sky.events.find(event => event.id === selection) || sky.featured || sky.events[0] || null
    readonly property var window: sky.bestWindow(selected)
    Rectangle { anchors.fill: parent; color: "#070d1b" }
    readonly property color ink: "#eef5ff"
    readonly property color accent: "#70edeb"
    readonly property color surface: "#101c32"

    component ThemedButton: Button {
        palette.button: root.surface
        palette.buttonText: root.ink
        palette.highlight: root.accent
    }
    component SkyTab: TabButton {
        id: tab
        implicitHeight: 36
        contentItem: Text {
            text: tab.text
            color: tab.checked ? root.ink : "#a7b7ce"
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            color: tab.checked ? "#15253c" : root.surface
            border.color: tab.checked || tab.visualFocus ? root.accent : "#2a3e58"
        }
    }

    function local(when) {
        return when ? Qt.formatDateTime(new Date(when), "ddd d MMM · HH:mm") : "—"
    }

    function position(point) {
        return point ? point.direction + " " + point.az + "° · " + point.el + "° up" : "—"
    }

    component Copy: Text {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        color: root.ink
        font.family: "sans-serif"
        font.pixelSize: 14
    }
    component Heading: Copy {
        font.bold: true
        font.pixelSize: 18
    }
    component View: ScrollView {
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    }

    property alias tabIndex: tabs.currentIndex

    ColumnLayout {
        anchors.fill: parent
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            Heading { text: qsTr("OMANOVA Observatory"); color: root.accent }
            Copy {
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                maximumLineCount: 1
                text: root.sky.fixture ? "Offline fixture · system time"
                     : (root.sky.data && root.sky.data.place ? root.sky.data.place.name + " · system time" : "Setup")
            }
        }

        TabBar {
            id: tabs
            Layout.fillWidth: true
            background: Rectangle { color: "#070d1b" }
            SkyTab { text: "Now & Next" }
            SkyTab { text: "Sky Compass" }
            SkyTab { text: "Upcoming" }
            SkyTab { text: "Conditions" }
            SkyTab { text: "Settings" }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabs.currentIndex
            View {
                ColumnLayout {
                    width: parent.width
                    spacing: 9
                    Heading { text: root.selected ? root.selected.name + " · Station pass" : "Your observing location" }
                    Copy {
                        text: root.window ? "Potential viewing window · " + root.sky.countdown(root.window.start.time)
                             : (root.selected ? "Geometric pass · no usable viewing window"
                             : (root.sky.data ? root.sky.data.status : "Set a manual location in Settings"))
                        color: root.accent
                        font.bold: true
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.selected !== null
                        ColumnLayout {
                            Layout.fillWidth: true
                            Copy {
                                text: root.window ? "Look " + root.position(root.window.start) + "\nPeak " + root.position(root.window.peak)
                                      : (root.selected ? root.selected.reason : "")
                            }
                            Copy {
                                visible: root.window !== null
                                text: root.window ? "Viewing start   " + root.local(root.window.start.time)
                                    + "\nViewing peak   " + root.local(root.window.peak.time)
                                    + "\nViewing end    " + root.local(root.window.end.time) : ""
                            }
                        }
                        Compass {
                            visible: root.width >= 440
                            Layout.preferredWidth: 152
                            Layout.preferredHeight: 140
                            points: visible && root.selected ? root.selected.path : []
                        }
                    }
                    Copy {
                        visible: root.selected !== null
                        text: root.selected ? "Geometric rise   " + root.local(root.selected.start)
                             + "\nCulmination      " + root.local(root.selected.peak) + " · " + root.selected.culmination.el + "°"
                             + "\nGeometric set   " + root.local(root.selected.end) + " · " + root.selected.duration_s + "s total" : ""
                    }
                    Copy {
                        visible: root.selected !== null
                        text: root.selected ? "At culmination · "
                            + (root.selected.culmination.sunlit ? "station sunlit" : "station in shadow")
                            + " · " + (root.selected.culmination.sky_dark ? "sky dark enough" : "sky too bright") : ""
                    }
                    Copy {
                        visible: root.selected !== null
                        text: root.selected ? root.selected.confidence + " · elements " + root.selected.epoch_hours + "h from pass"
                            + (root.window ? " · " + root.window.conditions.label + " weather" : "") : ""
                    }
                    Copy {
                        text: root.sky.data ? root.sky.data.status + " · updated " + root.local(root.sky.data.generated) : ""
                    }
                    ThemedButton {
                        text: "CelesTrak orbital source"
                        visible: root.selected !== null
                        onClicked: Qt.openUrlExternally("https://celestrak.org/norad/elements/table.php?GROUP=stations")
                    }
                }
            }
            View {
                ColumnLayout {
                    width: parent.width
                    Heading { text: root.selected ? root.selected.name + " · True north up" : "Sky compass" }
                    Compass {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 220
                        points: root.selected ? root.selected.path : []
                    }
                    Copy { text: "Thick line shows potential viewing geometry. Thin line shows the rest of the pass." }
                    Copy {
                        text: root.window ? "First look " + root.position(root.window.start)
                             + "  →  " + root.position(root.window.end) : "No usable viewing window for this selection."
                    }
                }
            }
            ListView {
                id: passes
                clip: true
                spacing: 3
                model: root.sky.events
                ScrollBar.vertical: ScrollBar {}
                delegate: ItemDelegate {
                    required property var modelData
                    width: ListView.view.width - 12
                    highlighted: root.selected && root.selected.id === modelData.id
                    background: Rectangle { color: parent.highlighted || parent.hovered ? "#15253c" : "transparent" }
                    onClicked: {
                        root.selection = modelData.id
                        tabs.currentIndex = 0
                    }
                    contentItem: Text {
                        textFormat: Text.PlainText
                        color: root.ink
                        font.family: "sans-serif"
                        font.pixelSize: 14
                        elide: Text.ElideRight
                        text: modelData.name + "   " + root.local(modelData.start) + "   " + modelData.culmination.el + "°   "
                             + (modelData.confidence === "Stale orbit" ? "Stale orbit" : modelData.windows.length
                                ? modelData.windows[0].conditions.label : "Geometric only")
                    }
                }
            }
            View {
                ColumnLayout {
                    width: parent.width
                    Heading { text: root.window ? root.window.conditions.label : "Conditions" }
                    Copy { text: root.window ? root.window.conditions.reason : "Select a pass with a potential viewing window." }
                    Copy { text: root.sky.data && root.sky.data.weather_fetched
                        ? "Forecast retrieved " + root.local(root.sky.data.weather_fetched) : "Forecast unavailable" }
                    Copy {
                        visible: text.length > 0
                        text: root.sky.data && root.sky.data.weather_error ? "Weather refresh · " + root.sky.data.weather_error : ""
                    }
                    Repeater {
                        model: root.window ? root.window.conditions.hours : []
                        delegate: Copy {
                            required property var modelData
                            text: root.local(modelData.time) + " · cloud " + (modelData.cloud_cover ?? "—")
                                + "% · visibility " + (modelData.visibility === null ? "—" : (modelData.visibility / 1000).toFixed(1))
                                + " km · precipitation " + (modelData.precipitation ?? "—") + " mm"
                                + "\nCloud low/mid/high " + (modelData.cloud_cover_low ?? "—") + "/"
                                + (modelData.cloud_cover_mid ?? "—") + "/" + (modelData.cloud_cover_high ?? "—") + "%"
                                + " · wind " + (modelData.wind_speed_10m ?? "—") + " km/h"
                        }
                    }
                    Copy { text: "Forecasts describe the area around the observing location. Trees, buildings and local cloud can affect the view." }
                    ThemedButton {
                        text: "Open-Meteo forecast source"
                        onClicked: Qt.openUrlExternally("https://open-meteo.com/")
                    }
                }
            }
            View {
                id: settingsScroll
                SettingsPage {
                    width: settingsScroll.availableWidth
                    sky: root.sky
                    compact: true
                }
            }
        }
    }
}
