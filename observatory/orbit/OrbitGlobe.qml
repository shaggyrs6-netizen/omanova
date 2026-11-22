import "../../qml/Omanova" as App
import "../../qml/Omanova/StationGlyph.js" as StationGlyph
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: globe
    property var observer: null
    property var selected: null
    property var sample: null
    property color accent: App.Palette.accent
    property var coastlines: []
    readonly property real radius: Math.min(width, height) * 0.455
    readonly property real centreLon: (observer?.lon ?? 0) * Math.PI / 180
    readonly property real centreLat: (observer?.lat ?? 20) * Math.PI / 180
    readonly property bool textured: App.Palette.observingMode === "normal" && earth.status === Image.Ready &&
        disc.status !== ShaderEffect.Error && GraphicsInfo.api !== GraphicsInfo.Software
    Accessible.name: qsTr("Earth globe showing the observer, station footprint and predicted ground tracks")

    onObserverChanged: overlay.requestPaint()
    onSelectedChanged: overlay.requestPaint()
    onSampleChanged: overlay.requestPaint()
    onCoastlinesChanged: overlay.requestPaint()
    onAccentChanged: overlay.requestPaint()
    onTexturedChanged: overlay.requestPaint()

    Connections {
        target: App.Palette
        function onThemedChanged() { overlay.requestPaint() }
        function onResolvedChanged() { overlay.requestPaint() }
    }
    FileView {
        path: Quickshell.env("OMASKY_ORBIT_LAND")
        printErrors: false
        onLoaded: {
            try {
                const rings = []
                for (const feature of JSON.parse(text()).features)
                    for (const ring of feature.geometry.coordinates) rings.push(ring)
                globe.coastlines = rings
            } catch (_) { globe.coastlines = [] }
        }
    }

    Image {
        id: earth
        visible: false
        asynchronous: true
        source: App.Palette.observingMode === "normal" ? "../../mission-control/assets/earth.jpg" : ""
    }
    ShaderEffect {
        id: disc
        anchors.centerIn: parent
        width: 2 * globe.radius
        height: width
        // Red, dim and software sessions keep the vector coastlines.
        visible: globe.textured
        property var earthTexture: earth
        property real longitude: globe.centreLon
        property real latitude: globe.centreLat
        fragmentShader: "earth-disc.frag.qsb"
    }
    Canvas {
        id: overlay
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const c = getContext("2d")
            c.reset()
            const x = width / 2, y = height / 2
            const radius = globe.radius
            if (radius < 12) return
            const rad = Math.PI / 180
            const centreLon = globe.centreLon
            const centreLat = globe.centreLat
            const sinCentre = Math.sin(centreLat)
            const cosCentre = Math.cos(centreLat)

            function project(lon, lat) {
                const delta = lon * rad - centreLon
                const phi = lat * rad
                const cp = Math.cos(phi), sp = Math.sin(phi)
                return {
                    x: x + radius * cp * Math.sin(delta),
                    y: y - radius * (cosCentre * sp - sinCentre * cp * Math.cos(delta)),
                    front: sinCentre * sp + cosCentre * cp * Math.cos(delta) >= 0
                }
            }
            function line(points) {
                let penDown = false
                for (const point of points) {
                    const p = project(point[0], point[1])
                    if (p.front) {
                        if (penDown) c.lineTo(p.x, p.y)
                        else c.moveTo(p.x, p.y)
                    }
                    penDown = p.front
                }
            }

            const ocean = c.createRadialGradient(x - radius * .35, y - radius * .45, 0, x, y, radius)
            ocean.addColorStop(0, App.Palette.button)
            ocean.addColorStop(.74, App.Palette.field)
            ocean.addColorStop(1, App.Palette.shade)
            c.fillStyle = ocean
            c.strokeStyle = globe.accent
            c.lineWidth = 1
            c.beginPath()
            c.arc(x, y, radius, 0, 2 * Math.PI)
            if (!globe.textured) c.fill()
            c.stroke()
            c.save()
            c.clip()

            c.strokeStyle = App.Palette.line
            c.globalAlpha = globe.textured ? .42 : 1
            c.lineWidth = 1
            c.beginPath()
            for (let lat = -60; lat <= 60; lat += 30)
                line(Array.from({length:73}, (_, i) => [i * 5 - 180, lat]))
            for (let lon = -180; lon < 180; lon += 30)
                line(Array.from({length:37}, (_, i) => [lon, i * 5 - 90]))
            c.stroke()

            if (!globe.textured) {
                c.strokeStyle = App.Palette.ink
                c.lineWidth = 1.3
                c.globalAlpha = .64
                c.beginPath()
                for (const ring of coastlines) line(ring)
                c.stroke()
            }
            c.globalAlpha = 1

            c.strokeStyle = globe.textured ? "#d5e8ff" : App.Palette.muted
            c.setLineDash([4, 5])
            c.beginPath()
            line(selected?.track || [])
            c.stroke()
            c.setLineDash([])
            c.lineWidth = 2.5
            c.strokeStyle = globe.accent
            c.beginPath()
            line((selected?.pass || []).map(p => [p.lon, p.lat]))
            c.stroke()
            c.restore()

            if (observer) {
                c.fillStyle = App.Palette.ink
                c.beginPath()
                c.moveTo(x, y - 5); c.lineTo(x + 5, y)
                c.lineTo(x, y + 5); c.lineTo(x - 5, y)
                c.closePath()
                c.fill()
                c.lineWidth = 1.4
                c.strokeStyle = App.Palette.background
                c.stroke()
            }
            if (sample) {
                const station = project(sample.lon, sample.lat)
                if (station.front)
                    StationGlyph.draw(c, station.x, station.y, 25, globe.accent, App.Palette.background)
            }
        }
    }
}
