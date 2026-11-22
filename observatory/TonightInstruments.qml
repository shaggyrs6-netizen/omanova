import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".." as Core
import "./orbit" as Orbit
import "./moon" as Moon
import "../qml/Omanova" as App

ColumnLayout {
    id: hero
    required property var sky
    required property var strip
    required property bool weatherCurrent
    signal openOrbit(string station, string rise, string time)
    spacing: 10

    readonly property var event: sky.snapshotStale ? null : sky.events.find(e =>
        e.confidence !== "Stale orbit" && e.windows?.some(w => Date.parse(w.end.time) > sky.now))
    readonly property var window: event?.windows.find(w => Date.parse(w.end.time) > sky.now)
    readonly property var marker: window?.peak
    readonly property var place: sky.data?.place
    readonly property string key: event ? [place?.lat, place?.lon, event.id, sky.data?.orbit_fetched].join("/") : ""
    readonly property var cloud: {
        if (!marker || !weatherCurrent) return null
        const at = Date.parse(marker.time)
        const hour = strip.hours.find(h => Date.parse(h.time) <= at && at < Date.parse(h.time) + 3600000)
        return Number.isFinite(hour?.cloud) ? hour.cloud : null
    }
    readonly property string timeLabel: marker ? Qt.formatDateTime(new Date(marker.time), "HH:mm") : ""
    property var groundPass: null
    function loadTrack() {
        if (!key || !Quickshell.env("OMASKY_ORBIT_TOOL") || !Quickshell.env("OMASKY_ORBIT")) return
        if (calculate.running) return
        calculate.requestKey = key
        calculate.running = true
    }
    onKeyChanged: { groundPass = null; refresh.restart() }
    Timer { id: refresh; interval: 75; onTriggered: hero.loadTrack() }
    FileView {
        id: tracks
        printErrors: false
        path: Quickshell.env("OMASKY_ORBIT")
        onLoaded: {
            if (!hero.event || calculate.requestKey !== hero.key) return
            try {
                const data = JSON.parse(text())
                if (data.observer.lat !== hero.place?.lat || data.observer.lon !== hero.place?.lon) return
                const station = data.stations.find(s => s.name === hero.event.name)
                hero.groundPass = station?.passes.find(p => p.confidence !== "Stale orbit" &&
                    Math.abs(Date.parse(p.rise) - Date.parse(hero.event.start)) <= 5000) || null
            } catch (_) { hero.groundPass = null }
        }
    }
    Process {
        id: calculate
        property string requestKey: ""
        readonly property string tool: Quickshell.env("OMASKY_ORBIT_TOOL")
        command: [tool + "/.venv/bin/python", tool + "/observatory/orbit/tracks.py",
                  tracks.path, hero.sky.fixture ? "fixture" : "live"]
        environment: ({ "OPENBLAS_NUM_THREADS": "1" })
        onExited: function(code) {
            if (requestKey !== hero.key) refresh.restart()
            else if (code === 0) tracks.reload()
        }
    }
    readonly property var footprint: {
        if (!groundPass || !marker) return null
        const t = Date.parse(marker.time)
        return groundPass.pass.reduce((best,p) => !best || Math.abs(Date.parse(p.time)-t) <
            Math.abs(Date.parse(best.time)-t) ? p : best, null)
    }

    component Label: Text {
        color: App.Palette.ink
        font.pixelSize: 17
        font.bold: true
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }
    component Panel: App.ViewPanel {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        appearance: "mission"
        border.color: App.Palette.themed ? App.Palette.border : "#387b89"
    }
    RowLayout {
        Layout.fillWidth: true
        Label { text: qsTr("Tonight"); font.pixelSize: 21; Layout.fillWidth: true }
        Label { text: hero.place?.name || qsTr("No location"); color: App.Palette.muted; font.pixelSize: 14 }
    }
    GridLayout {
        Layout.fillWidth: true
        columns: width < 600 ? 1 : 2
        columnSpacing: 12
        rowSpacing: 10
        Panel {
            implicitHeight: hero.width < 600 ? 260 : 310
            Label { id: localTitle; x: 14; y: 10; text: qsTr("Local sky") }
            Core.Compass {
                anchors { top: localTitle.bottom; bottom: look.top; left: parent.left; right: parent.right }
                instrument: true
                points: hero.event?.path || []
                marker: hero.marker || null
            }
            Label {
                id: look
                anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 9 }
                font.pixelSize: 14; color: App.Palette.accent
                text: hero.marker ? qsTr("Look %1 · %2° up at %3").arg(hero.marker.direction)
                    .arg(Math.round(hero.marker.el)).arg(hero.timeLabel) : qsTr("No current viewing window")
            }
        }
        Panel {
            implicitHeight: hero.width < 600 ? 260 : 310
            Label { id: orbitTitle; x: 14; y: 10; text: qsTr("Orbit") }
            Canvas {
                anchors.fill: earth
                visible: earth.textured && !App.Palette.themed
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const c = getContext("2d")
                    c.reset()
                    const r = earth.radius
                    if (r <= 0) return
                    const halo = c.createRadialGradient(width/2,height/2,r-1,width/2,height/2,r+12)
                    halo.addColorStop(0,"#4986b4")
                    halo.addColorStop(1,"transparent")
                    c.fillStyle = halo; c.fillRect(0,0,width,height)
                }
            }
            Orbit.OrbitGlobe {
                id: earth
                anchors { fill: parent; topMargin: 22; bottomMargin: 22 }
                observer: hero.place
                selected: hero.groundPass
                sample: hero.footprint
            }
            Label {
                anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 9 }
                font.pixelSize: 14; color: App.Palette.muted
                text: hero.footprint ? qsTr("%1 at %2 local").arg(hero.event.name).arg(hero.timeLabel) :
                    calculate.running ? qsTr("Calculating ground track…") : qsTr("Ground track unavailable")
            }
            App.ActionButton {
                anchors { top: parent.top; right: parent.right; margins: 7 }
                text: qsTr("Open Orbit"); enabled: !!hero.footprint
                onClicked: hero.openOrbit(hero.event.name, hero.groundPass.rise, hero.marker.time)
            }
        }
    }
    GridLayout {
        Layout.fillWidth: true
        columns: width < 520 ? 1 : 3
        columnSpacing: 10
        rowSpacing: 8
        component Tile: Panel {
            property string heading
            property string value
            property string detail
            property bool moon: false
            property bool cloudIcon: false
            implicitHeight: Math.max(100, tileBody.implicitHeight + 20)
            ColumnLayout {
                id: tileBody
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                          leftMargin: 13; rightMargin: 13 }
                spacing: 3
                Label { text: heading; font.pixelSize: 16 }
                RowLayout {
                    Layout.fillWidth: true
                    Canvas {
                        visible: cloudIcon
                        Layout.preferredWidth: 45; Layout.preferredHeight: 34
                        property color outline: App.Palette.ink
                        property color fill: App.Palette.shade
                        onOutlineChanged: requestPaint()
                        onFillChanged: requestPaint()
                        onPaint: {
                            const c = getContext("2d")
                            c.reset()
                            c.beginPath()
                            c.moveTo(11,29)
                            c.bezierCurveTo(-1,29,0,13,11,13)
                            c.bezierCurveTo(13,-1,33,1,34,14)
                            c.bezierCurveTo(46,12,47,29,35,29)
                            c.closePath()
                            c.fillStyle = fill; c.fill()
                            c.strokeStyle = outline; c.lineWidth = 1.8; c.stroke()
                        }
                    }
                    Moon.MoonDisk {
                        visible: moon && Number.isFinite(hero.strip?.moonFraction)
                        Layout.preferredWidth: 36; Layout.preferredHeight: 36
                        fraction: hero.strip?.moonFraction ?? 0; waxing: hero.strip?.moonWaxing ?? true
                    }
                    Label { text: value; font.pixelSize: 27; Layout.fillWidth: true }
                }
                Label { text: detail; visible: !!text; font.bold: false; font.pixelSize: 13; color: App.Palette.muted; Layout.fillWidth: true }
            }
        }
        Tile { heading: qsTr("Next pass"); value: hero.event ? hero.event.name + " · " + hero.timeLabel : "—"
               detail: !hero.marker ? qsTr("No current prediction") :
                   !hero.weatherCurrent ? qsTr("Visibility uncertain") :
                   hero.window.conditions?.label || qsTr("Visibility uncertain") }
        Tile { heading: qsTr("Cloud cover"); cloudIcon: true; value: hero.cloud === null ? qsTr("Unknown") : hero.cloud + "%"
               detail: hero.marker ? qsTr("At the viewing peak") : "" }
        Tile { heading: qsTr("Moon"); moon: true
               value: Number.isFinite(hero.strip?.moonFraction) ? Math.round(100*hero.strip.moonFraction)+"%" : "—"
               detail: qsTr("Illuminated") }
    }
}
