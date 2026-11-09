import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: page
    property int section: 0
    property var dataSet: null
    property string loadError: ""
    readonly property string tool: Quickshell.env("OMASKY_PLANETS_TOOL")
    Component.onCompleted: if (tool && snapshot.path) calculate.running = true
    spacing: 0

    function stamp(value, format) {
        return Qt.formatDateTime(new Date(value), format || "ddd d MMM · HH:mm")
    }
    function span(first, last) {
        const sameDay = new Date(first).toDateString() === new Date(last).toDateString()
        return stamp(first) + " – " + stamp(last, sameDay ? "HH:mm" : "ddd d MMM · HH:mm")
    }
    function position(item) {
        return qsTr("%1 · %2° up").arg(item.direction).arg(item.altitude)
    }
    function degrees(value) {
        return value.toLocaleString(Qt.locale(), 'f', 1) + "°"
    }

    component Copy: Text {
        Layout.fillWidth: true
        color: "#eef5ff"
        font.pixelSize: 15
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }
    component Heading: Copy {
        font.pixelSize: 23
        font.bold: true
    }
    component Card: Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 22
        Layout.rightMargin: 22
        color: "#111e31"
        border.color: "#2a3e58"
        radius: 12
    }

    component ViewTab: TabButton {
        id: tab
        implicitHeight: 42
        contentItem: Text {
            text: tab.text
            color: tab.checked ? "#eef5ff" : "#a7b7ce"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: 15
            font.bold: tab.checked
        }
        background: Rectangle {
            color: tab.checked ? "#15253c" : tab.hovered ? "#111e31" : "#070d1b"
            border.color: tab.visualFocus ? "#70edeb" : "#2a3e58"
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 2
                color: tab.checked ? "#70edeb" : "transparent"
            }
        }
    }

    FileView {
        id: snapshot
        printErrors: false
        path: Quickshell.env("OMASKY_PLANETS")
        onLoaded: {
            try { page.dataSet = JSON.parse(text()) }
            catch (error) { page.loadError = qsTr("Could not read the planet calculations.") }
        }
        onLoadFailed: if (!page.tool) page.loadError = qsTr("Could not load the planet calculations.")
    }

    Process {
        id: calculate
        command: [page.tool + "/.venv/bin/python", page.tool + "/observatory/planets/planets.py",
            snapshot.path, Quickshell.env("OMASKY_FIXTURE") === "1" ? "fixture" : "live"]
        environment: ({ "OPENBLAS_NUM_THREADS": "1" })
        stderr: StdioCollector { id: diagnostics }
        onExited: function(code) {
            if (code === 0) snapshot.reload()
            else page.loadError = diagnostics.text.trim() || qsTr("Planet calculation unavailable.")
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.margins: 22
        spacing: 7
        Copy {
            text: page.tool ? qsTr("OMANOVA OBSERVATORY  /  NIGHT SKY") : qsTr("OMANOVA OBSERVATORY  /  PREVIEW")
            color: "#70edeb"
            font.pixelSize: 12
            font.letterSpacing: 1.8
        }
        Heading { text: qsTr("Planets & conjunctions"); font.pixelSize: 32 }
        Copy {
            color: "#a7b7ce"
            text: page.dataSet?.fixture ? qsTr("Nashville test location · fixture")
                : qsTr("Saved observing location · times on your desktop clock")
        }
    }

    TabBar {
        Layout.fillWidth: true
        Layout.leftMargin: 22
        Layout.rightMargin: 22
        currentIndex: page.section
        onCurrentIndexChanged: {
            page.section = currentIndex
            scroll.contentItem.contentY = 0
        }
        background: Rectangle { color: "#070d1b" }
        ViewTab { text: qsTr("Next 24 hours") }
        ViewTab { text: qsTr("Pairings · 30 days") }
    }

    ScrollView {
        id: scroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        clip: true

        ColumnLayout {
            width: scroll.availableWidth
            spacing: 12
            Copy {
                Layout.margins: 22
                color: "#a7b7ce"
                text: page.loadError || (!page.dataSet ? qsTr("Loading viewing windows…") :
                    page.section === 0
                    ? qsTr("The five naked-eye planets. Windows require the planet to be at least 10° up and the Sun at least 6° below the horizon. Clouds and obstructions can affect the view.")
                    : qsTr("Close approaches within 5° for two planets or 8° for a Moon–planet pair. The closest approach is measured from Earth’s centre. Local windows use your observing point and the same darkness and height limits."))
            }

            Repeater {
                model: page.section === 0 ? page.dataSet?.highlights ?? [] : []
                delegate: Card {
                    id: planet
                    required property var modelData
                    implicitHeight: planetDetails.implicitHeight + 32
                    ColumnLayout {
                        id: planetDetails
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 6
                        Heading { text: planet.modelData.name }
                        Copy {
                            visible: !planet.modelData.windows.length
                            text: qsTr("No suitable window in the next 24 hours.")
                            color: "#a7b7ce"
                        }
                        Repeater {
                            model: planet.modelData.windows
                            delegate: ColumnLayout {
                                id: period
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 4
                                Copy {
                                    color: "#70edeb"
                                    text: page.span(period.modelData.start, period.modelData.end)
                                }
                                Copy {
                                    text: qsTr("Highest around %1 · %2")
                                        .arg(page.stamp(period.modelData.time, "HH:mm"))
                                        .arg(page.position(period.modelData))
                                }
                            }
                        }
                    }
                }
            }

            Repeater {
                model: page.section === 1 ? page.dataSet?.pairings ?? [] : []
                delegate: Card {
                    id: pairing
                    required property var modelData
                    readonly property var viewing: modelData.window
                    implicitHeight: pairDetails.implicitHeight + 32
                    ColumnLayout {
                        id: pairDetails
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 6
                        Heading { text: pairing.modelData.name }
                        Copy {
                            color: "#a7b7ce"
                            text: qsTr("Closest approach · %1 · %2 apart")
                                .arg(page.stamp(pairing.modelData.peak))
                                .arg(page.degrees(pairing.modelData.separation))
                        }
                        Copy {
                            color: pairing.viewing ? "#70edeb" : "#ffcc7b"
                            text: pairing.viewing
                                ? qsTr("Local window · %1").arg(page.span(pairing.viewing.start, pairing.viewing.end))
                                : qsTr("No suitable local viewing window near this pairing.")
                        }
                        Copy {
                            visible: !!pairing.viewing
                            text: pairing.viewing ? qsTr("Look around %1 · %2 apart")
                                .arg(page.stamp(pairing.viewing.time)).arg(page.degrees(pairing.viewing.separation)) : ""
                            font.bold: true
                        }
                        Repeater {
                            model: pairing.viewing?.positions ?? []
                            delegate: Copy {
                                required property var modelData
                                text: qsTr("%1 · %2").arg(modelData.name).arg(page.position(modelData))
                            }
                        }
                    }
                }
            }

            Copy {
                visible: page.section === 1 && page.dataSet && !page.dataSet.pairings.length
                Layout.margins: 22
                text: qsTr("No close pairings meet these limits in the next 30 days.")
            }
            Item { implicitHeight: 12 }
        }
    }
}
