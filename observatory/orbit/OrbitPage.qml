import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: ui
    spacing: 13
    property var orbitData: null
    property int stationIndex: 0
    property int passIndex: 0
    property int sampleIndex: 0
    readonly property var station: orbitData ? orbitData.stations[stationIndex] : null
    readonly property var selected: station ? (station.passes[passIndex] || null) : null
    readonly property var sample: selected ? (selected.pass[sampleIndex] || null) : null
    readonly property color accent: stationIndex === 0 ? "#70edeb" : "#b2a7ff"
    readonly property color ink: "#f2f7ff"
    readonly property color muted: "#a7b7ce"
    readonly property color line: "#2a3e58"
    readonly property int margin: width < 650 ? 14 : 25
    onStationChanged: {
        const preferred = station ? station.passes.findIndex(pass => pass.id === station.preferred) : -1
        passIndex = Math.max(0, preferred)
    }
    onSelectedChanged: {
        sampleIndex = selected ? Math.max(0, selected.pass.findIndex(point => point.time === selected.peak)) : 0
    }

    function time(value, format) {
        return value ? Qt.formatDateTime(new Date(value), format) : "—"
    }
    function direction(az) {
        const bearings = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        return bearings[Math.floor((az + 11.25) / 22.5) % 16]
    }
    function status() {
        if (!selected || !sample) return "No pass data"
        if (selected.confidence === "Stale orbit") return "Stale elements · Prediction uncertain"
        if (selected.windows.some(w => sample.time >= w.start && sample.time <= w.end))
            return "Inside potential viewing window · Geometry only"
        return selected.windows.length ? "Outside potential viewing window" : selected.reason
    }

    component Copy: Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        color: ui.ink
        font.family: "sans-serif"
        font.pixelSize: 14
        wrapMode: Text.Wrap
    }
    component Tag: Copy {
        color: ui.muted
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.letterSpacing: 1.1
    }
    component Fact: ColumnLayout {
        id: fact
        property string label
        property string value
        spacing: 3
        Tag { text: fact.label }
        Copy { text: fact.value; font.pixelSize: 19; font.weight: Font.DemiBold }
    }
    component StationButton: Button {
        id: button
        required property int index
        required property string modelData
        text: modelData
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        implicitHeight: 39
        leftPadding: 15; rightPadding: 15
        Accessible.description: ui.stationIndex === index ? "Selected station" : ""
        onClicked: ui.stationIndex = index
        contentItem: Copy { text: button.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
        background: Rectangle {
            radius: 6
            color: ui.stationIndex === button.index || button.hovered ? "#172b43" : "#101c32"
            border.color: button.visualFocus || ui.stationIndex === button.index ? ui.accent : ui.line
        }
    }

    FileView {
        id: snapshot
        printErrors: false
        path: Quickshell.env("OMASKY_ORBIT")
        onLoaded: {
            try { ui.orbitData = JSON.parse(text()) }
            catch (error) { ui.orbitData = null }
        }
    }

    readonly property string tool: Quickshell.env("OMASKY_ORBIT_TOOL")
    property string loadMessage: ""
    Component.onCompleted: {
        if (tool && snapshot.path) calculate.running = true
    }
    Process {
        id: calculate
        command: [ui.tool + "/.venv/bin/python", ui.tool + "/observatory/orbit/tracks.py",
            snapshot.path, Quickshell.env("OMASKY_FIXTURE") === "1" ? "fixture" : "live"]
        environment: ({ "OPENBLAS_NUM_THREADS": "1" })
        stderr: StdioCollector { id: diagnostics }
        onExited: function(code) {
            if (code === 0) snapshot.reload()
            else ui.loadMessage = diagnostics.text.trim() || "Orbit calculation unavailable"
        }
    }
    Copy {
        visible: calculate.running || !!ui.loadMessage
        Layout.leftMargin: ui.margin; Layout.rightMargin: ui.margin
        text: calculate.running ? "Calculating ground tracks from cached elements…" : ui.loadMessage
        color: ui.muted
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.margins: ui.margin
        Layout.bottomMargin: 0
        spacing: 5
        Tag { text: ui.orbitData?.fixture ? "OMASKY  /  OFFLINE FIXTURE" : "OMASKY  /  CACHED ORBITAL ELEMENTS"; color: ui.accent }
        Copy { text: "Orbit"; font.pixelSize: 42; font.weight: Font.DemiBold }
        Copy { text: "Ground tracks and the view from your observing point"; color: ui.muted }
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: ui.margin; Layout.rightMargin: ui.margin
        spacing: 8
        Repeater { model: ["ISS", "Tiangong"]; delegate: StationButton {} }
        Item { Layout.fillWidth: true }
    }
    ComboBox {
        Layout.fillWidth: true
        Layout.leftMargin: ui.margin; Layout.rightMargin: ui.margin
        model: ui.station ? ui.station.passes.map(pass =>
            ui.time(pass.rise, "ddd d MMM · HH:mm") + " local · " +
            (pass.confidence === "Stale orbit" ? "stale orbit" : pass.windows.length ? "viewing window" : "geometric pass")) : []
        currentIndex: count ? ui.passIndex : -1
        Accessible.name: "Upcoming station pass"
        onActivated: index => ui.passIndex = index
        palette.button: "#101c32"; palette.buttonText: ui.ink
        palette.base: "#101c32"; palette.text: ui.ink
    }
    GroundMap {
        Layout.fillWidth: true
        Layout.leftMargin: ui.margin; Layout.rightMargin: ui.margin
        observer: ui.orbitData?.observer || null
        selected: ui.selected
        sample: ui.sample
        accent: ui.accent
    }
    Copy {
        Layout.leftMargin: ui.margin; Layout.rightMargin: ui.margin
        text: "◆ Your observing point    ● Station footprint    ━ Selected pass    ┄ Surrounding orbit"
        font.pixelSize: 12; color: ui.muted
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: ui.margin; Layout.rightMargin: ui.margin
        spacing: 4
        Copy {
            text: ui.sample ? "Predicted position · " + ui.time(ui.sample.time, "ddd d MMM · HH:mm:ss") + " local" : "No predicted pass available"
            color: ui.accent
            font.weight: Font.DemiBold
        }
        Slider {
            Layout.fillWidth: true
            from: 0
            to: ui.selected ? Math.max(1, ui.selected.pass.length - 1) : 1
            value: ui.sampleIndex
            stepSize: 1
            enabled: !!ui.selected
            onMoved: ui.sampleIndex = Math.round(value)
            Accessible.name: "Scrub from geometric rise to set"
            palette.highlight: ui.accent
        }
        Copy { text: ui.status(); color: ui.muted }
    }
    GridLayout {
        columns: width < 660 ? 2 : 4
        rowSpacing: 10; columnSpacing: 15
        Layout.fillWidth: true
        Layout.leftMargin: ui.margin; Layout.rightMargin: ui.margin
        Fact { Layout.fillWidth: true; label: "TRUE BEARING"; value: ui.sample ? ui.sample.az + "° " + ui.direction(ui.sample.az) : "—" }
        Fact { Layout.fillWidth: true; label: "ELEVATION"; value: ui.sample ? ui.sample.el + "°" : "—" }
        Fact { Layout.fillWidth: true; label: "GROUND DISTANCE"; value: ui.sample ? ui.sample.ground + " km" : "—" }
        Fact { Layout.fillWidth: true; label: "LINE-OF-SIGHT RANGE"; value: ui.sample ? ui.sample.slant + " km" : "—" }
    }
    Copy {
        Layout.leftMargin: ui.margin; Layout.rightMargin: ui.margin; Layout.bottomMargin: ui.margin
        text: "Ground distance is to the point directly below the station. Weather is assessed separately.\n" +
            (ui.station ? "Elements epoch " + ui.time(ui.station.epoch, "ddd d MMM · HH:mm") + " local · " : "") +
            (ui.orbitData ? "Computed " + ui.time(ui.orbitData.generated, "HH:mm:ss") + " local · " : "") + "Made with Natural Earth."
        font.pixelSize: 12; color: ui.muted
    }
}
