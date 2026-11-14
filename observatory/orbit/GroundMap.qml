import "./qml/Omanova" as App
import QtQuick
import Quickshell
import Quickshell.Io

Rectangle {
    id: map
    property var observer: null
    property var selected: null
    property var sample: null
    property color accent: App.Palette.accent
    readonly property real inset: 11
    readonly property real plotHeight: Math.max(1, Math.min((width - inset * 2) / 2, height - inset * 2))
    readonly property real plotWidth: plotHeight * 2
    implicitHeight: Math.min(356, width / 2 + inset)
    radius: 8
    color: App.Palette.field
    border.color: App.Palette.line
    Accessible.name: "Earth ground track, local observing point and selected sub-satellite position"

    function project(lon, lat) {
        return Qt.point((width - plotWidth) / 2 + (lon + 180) / 360 * plotWidth,
                        (height - plotHeight) / 2 + (90 - lat) / 180 * plotHeight)
    }
    onSelectedChanged: tracks.requestPaint()
    onObserverChanged: positionLayer.requestPaint()
    onSampleChanged: positionLayer.requestPaint()

    FileView {
        id: land
        path: Quickshell.env("OMASKY_ORBIT_LAND")
        property var features: []
        onLoaded: {
            try { features = JSON.parse(text()).features || [] }
            catch (error) { features = [] }
            base.requestPaint()
        }
    }

    Canvas {
        id: base
        Connections { target: App.Palette; function onResolvedChanged() { base.requestPaint() } function onFollowChanged() { base.requestPaint() } }
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.fillStyle = App.Palette.surface
            ctx.strokeStyle = App.Palette.border
            ctx.lineWidth = 0.7
            for (const feature of land.features) {
                ctx.beginPath()
                for (const ring of feature.geometry.coordinates) {
                    if (!ring.length) continue
                    const first = map.project(ring[0][0], ring[0][1])
                    ctx.moveTo(first.x, first.y)
                    for (let i = 1; i < ring.length; i++) {
                        const next = map.project(ring[i][0], ring[i][1])
                        ctx.lineTo(next.x, next.y)
                    }
                    ctx.closePath()
                }
                ctx.fill()
                ctx.stroke()
            }
            ctx.strokeStyle = App.Palette.line
            ctx.lineWidth = 0.65
            ctx.beginPath()
            for (let lon = -180; lon <= 180; lon += 30) {
                const top = map.project(lon, 90), bottom = map.project(lon, -90)
                ctx.moveTo(top.x, top.y); ctx.lineTo(bottom.x, bottom.y)
            }
            for (let lat = -90; lat <= 90; lat += 30) {
                const left = map.project(-180, lat), right = map.project(180, lat)
                ctx.moveTo(left.x, left.y); ctx.lineTo(right.x, right.y)
            }
            ctx.stroke()
        }
    }

    Canvas {
        id: tracks
        Connections { target: App.Palette; function onResolvedChanged() { tracks.requestPaint() } function onFollowChanged() { tracks.requestPaint() } }
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (!map.selected) return
            function path(points, stroke, width, dash) {
                ctx.strokeStyle = stroke
                ctx.lineWidth = width
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.setLineDash(dash)
                ctx.beginPath()
                let previous = null
                for (const [lon, lat] of points) {
                    const point = map.project(lon, lat)
                    if (previous === null) ctx.moveTo(point.x, point.y)
                    else if (Math.abs(lon - previous[0]) > 180) {
                        const edge = previous[0] > 0 ? 180 : -180
                        const adjusted = lon + 2 * edge
                        const fraction = adjusted === previous[0] ? 0 : (edge - previous[0]) / (adjusted - previous[0])
                        const crossing = previous[1] + fraction * (lat - previous[1])
                        const exit = map.project(edge, crossing), entry = map.project(-edge, crossing)
                        ctx.lineTo(exit.x, exit.y)
                        ctx.moveTo(entry.x, entry.y)
                        ctx.lineTo(point.x, point.y)
                    } else ctx.lineTo(point.x, point.y)
                    previous = [lon, lat]
                }
                ctx.stroke()
            }
            path(map.selected.track, App.Palette.muted, 1.6, [4, 5])
            path(map.selected.pass.map(point => [point.lon, point.lat]), map.accent, 3, [])
        }
    }

    Canvas {
        id: positionLayer
        Connections { target: App.Palette; function onResolvedChanged() { positionLayer.requestPaint() } function onFollowChanged() { positionLayer.requestPaint() } }
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (!map.observer) return
            const home = map.project(map.observer.lon, map.observer.lat)
            if (map.sample) {
                const sub = map.project(map.sample.lon, map.sample.lat)
                ctx.beginPath()
                ctx.moveTo(home.x, home.y)
                // Avoid an across-map chord at the antimeridian.
                if (Math.abs(map.sample.lon - map.observer.lon) <= 180) {
                    ctx.lineTo(sub.x, sub.y)
                    ctx.setLineDash([2, 3])
                    ctx.strokeStyle = App.Palette.violet
                    ctx.stroke()
                }
                ctx.setLineDash([])
                ctx.beginPath()
                ctx.arc(sub.x, sub.y, 5, 0, Math.PI * 2)
                ctx.fillStyle = App.Palette.violet
                ctx.fill()
                ctx.strokeStyle = App.Palette.background
                ctx.stroke()
            }
            ctx.beginPath()
            ctx.moveTo(home.x, home.y - 7)
            ctx.lineTo(home.x + 7, home.y)
            ctx.lineTo(home.x, home.y + 7)
            ctx.lineTo(home.x - 7, home.y)
            ctx.closePath()
            ctx.fillStyle = App.Palette.ink
            ctx.fill()
            ctx.strokeStyle = App.Palette.background
            ctx.stroke()
        }
    }
}
