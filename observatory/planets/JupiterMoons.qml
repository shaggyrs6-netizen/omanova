import "../../qml/Omanova" as App
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: panel
    required property string runtime
    property var dataSet: null
    property string fault: ""
    property bool localOnly: true
    property double clock: Date.now()
    readonly property bool stale: !fixture && dataSet &&
        (clock < Date.parse(dataSet.generated) || clock - Date.parse(dataSet.generated) >= 1800000)
    readonly property bool fixture: Quickshell.env("OMASKY_FIXTURE") === "1"
    readonly property string resultPath: Quickshell.env("OMASKY_PLANETS") + ".jupiter"
    spacing: 12
    function stamp(value) { return Qt.formatDateTime(new Date(value), "ddd d MMM · HH:mm") }
    function refresh() { if (!calculator.running) { fault = ""; dataSet = null; calculator.running = true } }
    Component.onCompleted: refresh()
    Timer { interval: 60000; running: !panel.fixture; repeat: true; onTriggered: panel.clock = Date.now() }
    component Copy: Text {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        color: App.Palette.ink
        font.pixelSize: 15
    }
    FileView {
        id: result
        path: panel.resultPath
        printErrors: false
        onLoaded: {
            if (calculator.running) return
            try { panel.dataSet = JSON.parse(text()) }
            catch (error) { panel.fault = qsTr("Could not read Jupiter moon events.") }
        }
    }
    Process {
        id: calculator
        command: [panel.runtime + "/.venv/bin/python", panel.runtime + "/observatory/planets/jupiter_moons.py",
                  panel.resultPath, panel.fixture ? "fixture" : "live"]
        environment: ({"OPENBLAS_NUM_THREADS": "1"})
        onExited: function(code) {
            if (code === 0) result.reload()
            else panel.fault = qsTr("Jupiter moon events unavailable. Check your location and cached ephemeris.")
        }
    }
    App.InstrumentCard {
        Layout.leftMargin: 22
        Layout.rightMargin: 22
        App.PageHeader { title: qsTr("Jupiter’s moons"); eyebrow: qsTr("NEXT THREE DAYS") }
        Copy {
            text: qsTr("Estimated moon and shadow transits. Local windows require Jupiter at least 20° up, twilight or darkness, and a clear saved horizon. Shadow times approximate the centre crossing the disk. Weather and telescope performance can affect the view.")
            color: App.Palette.muted
        }
        Copy {
            visible: panel.stale
            text: qsTr("These viewing windows are older than 30 minutes. Recalculate to check what is still upcoming.")
            color: App.Palette.warning
        }
        Flow {
            Layout.fillWidth: true
            spacing: 10
            App.ActionButton {
                text: panel.localOnly ? qsTr("Show all predicted events") : qsTr("Show local windows only")
                onClicked: panel.localOnly = !panel.localOnly
            }
            App.ActionButton { text: qsTr("Recalculate"); enabled: !calculator.running; onClicked: panel.refresh() }
        }
        Copy { visible: calculator.running || !!panel.fault; text: panel.fault || qsTr("Calculating locally…"); color: App.Palette.muted }
        Copy {
            visible: !!panel.dataSet && !panel.dataSet.events.some(row => !panel.localOnly || row.windows.length)
            text: qsTr("No events match this view.")
            color: App.Palette.muted
        }
    }
    Repeater {
        model: panel.dataSet?.events.filter(row => !panel.localOnly || row.windows.length) || []
        App.InstrumentCard {
            required property var modelData
            Layout.leftMargin: 22
            Layout.rightMargin: 22
            Copy { text: modelData.moon + " · " + modelData.kind; font.pixelSize: 21; font.bold: true }
            Copy {
                text: (modelData.ongoing ? qsTr("In progress") : panel.stamp(modelData.start))
                      + " – " + (modelData.continues ? qsTr("Continues beyond this forecast") : panel.stamp(modelData.end))
                color: App.Palette.muted
            }
            Copy { visible: !modelData.windows.length; text: qsTr("No local viewing window under the current geometry.") }
            Repeater {
                model: modelData.windows
                Copy {
                    required property var modelData
                    text: qsTr("Local window %1 – %2 · look %3, %4° up")
                        .arg(panel.stamp(modelData.start)).arg(panel.stamp(modelData.end))
                        .arg(modelData.direction).arg(modelData.altitude)
                    color: App.Palette.accent
                }
            }
        }
    }
}
