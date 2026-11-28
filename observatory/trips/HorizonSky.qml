import "../../qml/Omanova" as App
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
    id: panel
    required property string runtime
    required property string statePath
    required property var place
    required property var terrain
    property bool active: true
    property bool overlay: true
    property string selected: "Moon"
    property int offsetMinutes: 0
    property double requestedTime: 0
    property int serial: 0
    property int sentSerial: -1
    property string pending: ""
    property var dataSet: null
    property bool failed: false
    readonly property var target: dataSet?.selected || null

    function schedule() {
        serial++
        failed = false
        if (active && overlay && place) debounce.restart()
    }
    function select(name) {
        if (name !== selected) selected = name
    }
    function request() {
        if (job.running || !active || !overlay || !place) return
        sentSerial = serial
        pending = JSON.stringify({place: place, selected: selected,
            time: new Date(offsetMinutes === 0 ? Date.now() : requestedTime).toISOString()}) + "\n"
        job.stdinEnabled = true
        job.running = true
    }
    function setOffset(minutes) {
        requestedTime = Date.now() + minutes*60000
        offsetMinutes = minutes
        schedule()
    }

    onPlaceChanged: { dataSet = null; schedule() }
    onTerrainChanged: { dataSet = null; schedule() }
    onActiveChanged: schedule()
    onOverlayChanged: schedule()
    onSelectedChanged: schedule()

    Timer { id: debounce; interval: 180; onTriggered: panel.request() }
    Timer {
        interval: 60000
        repeat: true
        running: panel.active && panel.overlay && panel.offsetMinutes === 0
        onTriggered: panel.schedule()
    }
    Process {
        id: job
        command: [panel.runtime + "/.venv/bin/python",
                  panel.runtime + "/observatory/trips/horizon_sky.py", "--state", panel.statePath]
        environment: ({OPENBLAS_NUM_THREADS: "1"})
        onStarted: { write(panel.pending); panel.pending = ""; stdinEnabled = false }
        stdout: StdioCollector { id: output }
        onExited: code => {
            if (panel.sentSerial !== panel.serial) {
                panel.schedule()
                return
            }
            if (code === 0) {
                try { panel.dataSet = JSON.parse(output.text); return }
                catch (error) { /* Show the same fallback as a failed calculation. */ }
            }
            panel.dataSet = null
            panel.failed = true
        }
    }

    component Caption: Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: App.Palette.ink
        font.pixelSize: 14
    }

    Flow {
        Layout.fillWidth: true
        spacing: 10
        App.ActionButton {
            text: panel.overlay ? qsTr("Hide sky overlay") : qsTr("Show sky overlay")
            onClicked: panel.overlay = !panel.overlay
        }
        App.ActionButton {
            visible: panel.overlay
            text: qsTr("Now")
            onClicked: { timeSlider.value = 0; panel.setOffset(0) }
        }
        App.ActionButton {
            visible: panel.overlay
            text: chart.showBelow ? qsTr("Hide below horizon") : qsTr("Show below horizon")
            onClicked: chart.showBelow = !chart.showBelow
        }
    }
    RowLayout {
        visible: panel.overlay
        Layout.fillWidth: true
        Caption { Layout.fillWidth: false; text: qsTr("−6 h") }
        Slider {
            id: timeSlider
            Layout.fillWidth: true
            from: -360; to: 1440; stepSize: 5
            value: 0
            Accessible.name: qsTr("Sky time in minutes relative to now")
            palette.mid: App.Palette.border
            palette.dark: App.Palette.border
            palette.highlight: App.Palette.accent
            onMoved: panel.setOffset(value)
        }
        Caption { Layout.fillWidth: false; text: qsTr("+24 h") }
    }
    Caption {
        visible: panel.overlay
        text: panel.failed ? qsTr("Sky positions unavailable. Use Now to retry.") :
            panel.sentSerial !== panel.serial || job.running || !panel.dataSet ?
                (panel.dataSet ? qsTr("Updating sky · shown at %1").arg(panel.dataSet.localTime) : qsTr("Calculating sky positions…")) :
            (panel.offsetMinutes === 0 ? qsTr("Now · ") : qsTr("Preview time · ")) + panel.dataSet.localTime
        color: panel.failed ? App.Palette.warning : App.Palette.muted
    }
    HorizonChart {
        id: chart
        property bool showBelow: true
        Layout.fillWidth: true
        Layout.preferredHeight: panel.overlay ? 260 : 200
        terrain: panel.terrain
        sectors: panel.place?.horizon || []
        sky: panel.overlay ? panel.dataSet : null
        below: showBelow
        onSelectObject: name => panel.select(name)
    }
    RowLayout {
        visible: panel.overlay && !!panel.dataSet
        Layout.fillWidth: true
        Caption { Layout.fillWidth: false; text: qsTr("Inspect object") }
        ComboBox {
            id: objects
            Layout.fillWidth: true
            Accessible.name: qsTr("Inspect sky object")
            model: panel.dataSet?.targets.map(item => item.name) || []
            currentIndex: Math.max(0, model.indexOf(panel.selected))
            palette.base: App.Palette.field
            palette.button: App.Palette.button
            palette.window: App.Palette.surface
            palette.text: App.Palette.ink
            palette.buttonText: App.Palette.ink
            palette.windowText: App.Palette.ink
            onActivated: panel.select(currentText)
        }
    }
    ColumnLayout {
        visible: panel.overlay && !!panel.target && panel.sentSerial === panel.serial && !job.running
        Layout.fillWidth: true
        Caption {
            readonly property var item: panel.target
            text: !item ? "" : item.name + " · " +
                (item.status === "clear" ? qsTr("Clear of the skyline") :
                 item.status === "blocked" ? qsTr("Behind the skyline") : qsTr("Below the level horizon"))
            font.bold: true
            color: item?.status === "clear" ? App.Palette.ink : App.Palette.warning
        }
        Caption {
            readonly property var item: panel.target
            text: !item ? "" : qsTr("%1 (%2° true) · altitude %3° · skyline %4°")
                .arg(item.direction).arg(Math.round(item.az)%360).arg(item.el.toFixed(1)).arg(item.skyline.toFixed(1))
        }
        Caption {
            visible: panel.target?.status !== "clear"
            text: panel.dataSet?.nextClear ? qsTr("Estimated to clear around %1").arg(panel.dataSet.nextClear) :
                qsTr("No clearance found in the next 48 hours.")
        }
    }
    Caption {
        visible: panel.overlay
        text: !panel.place ? "" : panel.terrain.length ?
            qsTr("Solid edge: manual obstructions · dashed edge: terrain estimate · lower shaded area: below the level horizon.") :
            qsTr("Solid edge: manual obstructions · lower shaded area: below the level horizon. Terrain estimate unavailable.")
        color: App.Palette.muted
    }
    Caption {
        visible: panel.overlay && !!panel.dataSet
        text: qsTr("Filled markers are clear of the skyline. Open markers are blocked or below the level horizon. The chart shows down to −20°.")
        color: App.Palette.muted
    }
    Caption {
        visible: panel.overlay && !!panel.dataSet
        text: (panel.dataSet?.sunAltitude ?? -90) > -6 ?
            qsTr("Daylight or bright twilight. Sky positions show where objects are. Never look at the Sun through unfiltered optics.") :
            qsTr("Clearance is geometric. Clouds, glare and equipment affect what you can see.")
        color: App.Palette.muted
    }
}
