import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: page
    spacing: 14
    property var catalog: null

    function when(stamp, format) {
        return Qt.formatDateTime(new Date(stamp), format || "ddd d MMM · HH:mm")
    }
    function span(first, last) {
        const sameDay = new Date(first).toDateString() === new Date(last).toDateString()
        return when(first) + " – " + when(last, sameDay ? "HH:mm" : "ddd d MMM · HH:mm")
    }

    component Copy: Text {
        Layout.fillWidth: true
        color: "#eef5ff"
        font.pixelSize: 15
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }

    FileView {
        id: snapshot
        path: Quickshell.env("OMASKY_METEORS")
        printErrors: false
        onLoaded: {
            try { page.catalog = JSON.parse(text()) }
            catch (error) { page.loadMessage = qsTr("Could not read the meteor calendar.") }
        }
    }
    property string loadMessage: ""
    readonly property string tool: Quickshell.env("OMASKY_METEORS_TOOL")
    Component.onCompleted: if (tool && snapshot.path) calculate.running = true

    Process {
        id: calculate
        command: [page.tool + "/.venv/bin/python", page.tool + "/observatory/meteors/meteors.py",
            snapshot.path, Quickshell.env("OMASKY_FIXTURE") === "1" ? "fixture" : "live"]
        environment: ({ "OPENBLAS_NUM_THREADS": "1" })
        stderr: StdioCollector { id: diagnostics }
        onExited: function(code) {
            if (code === 0) snapshot.reload()
            else page.loadMessage = diagnostics.text.trim() || qsTr("Meteor calculation unavailable.")
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.margins: 22
        spacing: 8
        Copy {
            text: qsTr("OMANOVA OBSERVATORY  /  NIGHT SKY")
            color: "#70edeb"
            font.pixelSize: 12
            font.letterSpacing: 1.8
        }
        Copy { text: qsTr("Meteor showers"); font.pixelSize: 34; font.bold: true }
        Copy {
            text: page.catalog?.fixture ? qsTr("Nashville test location · fixture")
                : qsTr("Saved observing location · times on your desktop clock")
            color: "#a7b7ce"
        }
        Copy {
            text: qsTr("Viewing windows cover nights near each peak, with the Sun at least 18° below the horizon and the radiant at least 20° up. Clouds, light pollution and obstructions affect what you’ll see.")
            color: "#a7b7ce"
        }
    }

    Repeater {
        model: page.catalog?.showers ?? []
        delegate: Rectangle {
            id: card
            required property var modelData
            Layout.fillWidth: true
            Layout.leftMargin: 22
            Layout.rightMargin: 22
            implicitHeight: details.implicitHeight + 36
            color: "#111e31"
            border.color: "#2a3e58"
            radius: 12

            ColumnLayout {
                id: details
                anchors.fill: parent
                anchors.margins: 18
                spacing: 9

                Copy { text: card.modelData.name; font.pixelSize: 23; font.bold: true }
                Copy { text: qsTr("Activity · %1 to %2%3").arg(card.modelData.activeStart || "—").arg(card.modelData.activeEnd || "—").arg(card.modelData.activeNow ? qsTr(" · Active now") : ""); color: "#70edeb" }
                Copy {
                    text: card.modelData.dateOnly
                        ? qsTr("Published peak date · %1 UTC").arg(card.modelData.peak)
                        : qsTr("Expected peak · %1 local").arg(page.when(card.modelData.peak, "ddd d MMM yyyy · HH:mm"))
                    color: "#a7b7ce"
                }
                Copy {
                    visible: !card.modelData.windows.length
                    text: card.modelData.peakPassed ? qsTr("Activity continues, but this peak has passed. Precise viewing windows are shown near the published peak.") : qsTr("No local dark viewing window found near this peak.")
                }
                Repeater {
                    model: card.modelData.windows
                    delegate: ColumnLayout {
                        id: row
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 5
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#2a3e58" }
                        Copy {
                            text: page.span(row.modelData.start, row.modelData.end)
                            color: "#70edeb"
                            font.bold: true
                        }
                        Copy {
                            text: qsTr("Radiant highest at %1 · %2° %3 · Moon %4% lit, %5")
                                .arg(page.when(row.modelData.highest, "HH:mm"))
                                .arg(row.modelData.altitude).arg(row.modelData.direction)
                                .arg(row.modelData.illumination)
                                .arg(row.modelData.moonDown ? qsTr("below horizon") : qsTr("above horizon"))
                        }
                        Copy {
                            text: row.modelData.moonless.length
                                ? qsTr("Moon below horizon · %1").arg(row.modelData.moonless.map(
                                    item => page.span(item.start, item.end)).join(" / "))
                                : qsTr("No moon-free stretch of 15 minutes")
                            color: "#a7b7ce"
                        }
                    }
                }
                Button {
                    text: qsTr("IMO calendar ↗")
                    onClicked: Qt.openUrlExternally(card.modelData.source)
                }
            }
        }
    }

    Copy {
        Layout.margins: 22
        color: "#a7b7ce"
        text: page.loadMessage || (!page.catalog ? qsTr("Loading calendar…") : page.catalog.showers.length
            ? qsTr("The radiant is where the meteors appear to come from. Watch a wide patch of sky away from it.")
            : qsTr("No upcoming peaks in the bundled calendar."))
    }
}
