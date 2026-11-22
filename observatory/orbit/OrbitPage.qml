import "../../qml/Omanova" as App
import "../.." as Core
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: ui
    property var formatDistance: (km, digits) => km.toLocaleString(Qt.locale(), 'f', digits) + " km"
    spacing: 13
    property bool useTonightTracks: false
    property var orbitData: null
    property var initialTarget: null
    signal targetConsumed()
    function applyTarget() {
        if (!initialTarget || !orbitData || calculate.running) return
        const target = initialTarget
        const index = orbitData.stations.findIndex(s => s.name === target.station)
        if (index >= 0) {
            const pass = orbitData.stations[index].passes.findIndex(p => Math.abs(Date.parse(p.rise)-Date.parse(target.rise)) <= 5000)
            if (pass >= 0) {
                stationIndex = index
                passIndex = pass
                const time = Date.parse(target.time)
                sampleIndex = selected.pass.reduce((best,p,i,a) =>
                    Math.abs(Date.parse(p.time)-time) < Math.abs(Date.parse(a[best].time)-time) ? i : best, 0)
            }
        }
        targetConsumed()
    }

    property bool flatMap: false
    property int stationIndex: 0
    property int passIndex: 0
    property int sampleIndex: 0
    readonly property var station: orbitData ? orbitData.stations[stationIndex] : null
    readonly property var selected: station ? (station.passes[passIndex] || null) : null
    readonly property var sample: selected ? (selected.pass[sampleIndex] || null) : null
    readonly property var localTrack: (selected?.pass || []).map(point => ({
        az: point.az, el: point.el,
        visible: selected.confidence !== "Stale orbit" &&
                 selected.windows.some(window => point.time >= window.start && point.time <= window.end)
    }))
    readonly property color accent: stationIndex === 0 ? App.Palette.accent : App.Palette.warning
    readonly property color ink: App.Palette.ink
    readonly property color muted: App.Palette.muted
    readonly property color line: App.Palette.line
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
            color: ui.stationIndex === button.index || button.hovered ? App.Palette.hover : App.Palette.surface
            border.color: button.visualFocus || ui.stationIndex === button.index ? ui.accent : ui.line
        }
    }

    FileView {
        id: snapshot
        printErrors: false
        path: ui.useTonightTracks ? "" : Quickshell.env("OMASKY_ORBIT")
        onLoaded: {
            if (ui.useTonightTracks) return
            try { ui.orbitData = JSON.parse(text()) }
            catch (error) { ui.orbitData = null }
        }
    }

    readonly property string tool: Quickshell.env("OMASKY_ORBIT_TOOL")
    property string loadMessage: ""
    Component.onCompleted: {
        if (initialTarget?.tracks) {
            useTonightTracks = true
            orbitData = initialTarget.tracks
            applyTarget()
        } else if (tool && snapshot.path) calculate.running = true
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
        App.PageHeader { eyebrow:"MISSION CONTROL"; title:"Orbit"; description:qsTr("Compare the ground track with the sky at your observing point.") }
    }
    Flow {
        Layout.fillWidth:true
        Layout.leftMargin:ui.margin;Layout.rightMargin:ui.margin
        spacing:8
        Repeater {model:["ISS","Tiangong"];delegate:StationButton {}}
        ComboBox {
            width:Math.min(390,parent.width)
            height:39
            model:ui.station ? ui.station.passes.map(pass =>
                ui.time(pass.rise,"ddd d MMM · HH:mm") + " local · " +
                (pass.confidence === "Stale orbit" ? "stale orbit" : pass.windows.length ? "viewing window" : "geometric pass")) : []
            id: passChoice
            function syncSelection() {
                currentIndex = ui.selected ? ui.passIndex : -1
            }
            // Qt resets the selection while installing a new station's model.
            onModelChanged: Qt.callLater(syncSelection)
            Connections {
                target: ui
                function onPassIndexChanged() { passChoice.syncSelection() }
            }
            displayText: ui.selected ? model[ui.passIndex] || "" : qsTr("No upcoming pass")
            Accessible.name:qsTr("Upcoming station pass")
            onActivated:index=>ui.passIndex=index
            palette.button:App.Palette.button;palette.buttonText:ui.ink
            palette.base:App.Palette.surface;palette.text:ui.ink
            palette.window:App.Palette.surface;palette.windowText:ui.ink
        }
    }
    GridLayout {
        Layout.fillWidth:true;Layout.leftMargin:ui.margin;Layout.rightMargin:ui.margin
        columns:width>=720?2:1;columnSpacing:14;rowSpacing:14
        App.ViewPanel {
            appearance:"mission"
            Layout.fillWidth:true;Layout.fillHeight:true;Layout.preferredWidth:1
            implicitHeight:localBody.implicitHeight+28
            ColumnLayout {
                id:localBody
                anchors.top:parent.top;anchors.left:parent.left;anchors.right:parent.right;anchors.margins:14
                spacing:8
                Copy {text:qsTr("Local sky");font.pixelSize:19;font.bold:true}
                Core.Compass {
                    id: skyCompass
                    Layout.fillWidth:true;Layout.preferredHeight:270
                    accent:ui.accent
                    points:ui.localTrack
                    marker:ui.sample
                    instrument:true
                }
                Copy {
                    text:ui.sample ? qsTr("Look %1 · %2° up").arg(ui.direction(ui.sample.az)).arg(ui.sample.el) : qsTr("Select a pass to plot its path.")
                    color:ui.accent;font.bold:true
                }
                Copy {
                    visible: skyCompass.hasStarBackdrop
                    text: qsTr("Illustrative star field")
                    color: ui.muted
                    font.pixelSize: 12
                }
            }
        }
        App.ViewPanel {
            appearance:"mission"
            Layout.fillWidth:true;Layout.fillHeight:true;Layout.preferredWidth:1
            implicitHeight:earthBody.implicitHeight+28
            ColumnLayout {
                id:earthBody
                anchors.top:parent.top;anchors.left:parent.left;anchors.right:parent.right;anchors.margins:14
                spacing:8
                RowLayout {
                    Layout.fillWidth:true
                    Copy {text:qsTr("Ground track");font.pixelSize:19;font.bold:true}
                    App.ActionButton {
                        text:ui.flatMap?qsTr("Globe"):qsTr("Flat map")
                        onClicked:ui.flatMap=!ui.flatMap
                    }
                }
                Item {
                    Layout.fillWidth:true;Layout.preferredHeight:250
                    OrbitGlobe {
                        id:earthGlobe
                        anchors.fill:parent
                        observer:ui.orbitData?.observer || null;selected:ui.flatMap?null:ui.selected
                        sample:ui.flatMap?null:ui.sample;accent:ui.accent
                    }
                    GroundMap {
                        anchors.fill:parent;visible:ui.flatMap
                        observer:ui.orbitData?.observer || null;selected:visible?ui.selected:null
                        sample:visible?ui.sample:null;accent:ui.accent
                    }
                }
                Copy {
                    text:qsTr("◆ Observing point    ·    Station symbol marks the footprint")
                    color:ui.muted;font.pixelSize:13
                }
            }
        }
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
        App.PassSlider {
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
        Fact { Layout.fillWidth: true; label: "GROUND DISTANCE"; value: ui.sample ? ui.formatDistance(ui.sample.ground, 0) : "—" }
        Fact { Layout.fillWidth: true; label: "LINE-OF-SIGHT RANGE"; value: ui.sample ? ui.formatDistance(ui.sample.slant, 0) : "—" }
    }
    Copy {
        Layout.leftMargin: ui.margin; Layout.rightMargin: ui.margin; Layout.bottomMargin: ui.margin
        text: "Ground distance is to the point directly below the station. Weather is assessed separately.\n" +
            (ui.station ? "Elements epoch " + ui.time(ui.station.epoch, "ddd d MMM · HH:mm") + " local · " : "") +
            (ui.orbitData ? "Computed " + ui.time(ui.orbitData.generated, "HH:mm:ss") + " local · " : "") + "Made with Natural Earth."
        font.pixelSize: 12; color: ui.muted
    }
    IpcHandler {
        target: "omanova-orbit-preview"
        function sampleState(): string {
            if (Quickshell.env("OMASKY_FIXTURE") !== "1") return ""
            return JSON.stringify({station:ui.station?.name, passes:ui.station?.passes.length ?? 0,
                                   time:ui.sample?.time, flatMap:ui.flatMap, textured:earthGlobe.textured,
                                   starBackdrop:skyCompass.hasStarBackdrop, samples:ui.selected?.pass.length ?? 0})
        }
        function sampleControls(station:int, sample:int, flat:bool): bool {
            if (Quickshell.env("OMASKY_FIXTURE") !== "1" || station < 0 || station > 1) return false
            ui.stationIndex=station
            ui.sampleIndex=Math.min(Math.max(sample,0),Math.max(0,(ui.selected?.pass.length ?? 0)-1))
            ui.flatMap=flat
            return true
        }
    }

}
