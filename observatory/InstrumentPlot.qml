import "./qml/Omanova" as App
import QtQuick

Item {
    id: plot
    property var path: []
    property var viewing: null
    property var position: null
    property color accent: App.Palette.accent
    property color violet: App.Palette.violet
    readonly property real radius: Math.max(0, Math.min(width, height) / 2 - 28)

    Accessible.name: "North-up sky plot with horizon, elevation rings and station track"
    function project(point) {
        const az = point.az * Math.PI / 180
        const distance = radius * (1 - Math.max(0, Math.min(90, point.el)) / 90)
        return Qt.point(width / 2 + distance * Math.sin(az),
                        height / 2 - distance * Math.cos(az))
    }
    onPathChanged: chart.requestPaint()
    onViewingChanged: chart.requestPaint()
    onRadiusChanged: chart.requestPaint()
    onAccentChanged: chart.requestPaint()

    Canvas {
        id: chart
        Connections { target: App.Palette; function onResolvedChanged() { chart.requestPaint() } function onFollowChanged() { chart.requestPaint() } }
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const x = width / 2, y = height / 2, r = plot.radius
            if (r < 5) return
            ctx.strokeStyle = App.Palette.line
            ctx.lineWidth = 1
            for (let ring = 1; ring <= 3; ring++) {
                ctx.beginPath()
                ctx.arc(x, y, r * ring / 3, 0, Math.PI * 2)
                ctx.stroke()
            }
            for (let step = 0; step < 4; step++) {
                const angle = step * Math.PI / 4
                const dx = r * Math.cos(angle), dy = r * Math.sin(angle)
                ctx.beginPath()
                ctx.moveTo(x - dx, y - dy)
                ctx.lineTo(x + dx, y + dy)
                ctx.stroke()
            }
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"
            ctx.fillStyle = App.Palette.ink
            ctx.font = "600 15px sans-serif"
            ctx.fillText("N", x, y - r - 15)
            ctx.fillText("S", x, y + r + 15)
            ctx.fillText("W", x - r - 15, y)
            ctx.fillText("E", x + r + 15, y)
            ctx.fillStyle = App.Palette.muted
            ctx.font = "12px sans-serif"
            ctx.fillText("30°", x + 17, y - 2 * r / 3 - 9)
            ctx.fillText("60°", x + 17, y - r / 3 - 9)

            function trace(points, color, lineWidth, dashed) {
                if (points.length < 2) return
                ctx.strokeStyle = color
                ctx.lineWidth = lineWidth
                ctx.lineJoin = "round"
                ctx.lineCap = "round"
                ctx.setLineDash(dashed ? [4, 5] : [])
                ctx.beginPath()
                const first = plot.project(points[0])
                ctx.moveTo(first.x, first.y)
                for (let i = 1; i < points.length; i++) {
                    const point = plot.project(points[i])
                    ctx.lineTo(point.x, point.y)
                }
                ctx.stroke()
            }
            trace(plot.path, App.Palette.muted, 1.5, true)
            if (!plot.viewing) return
            const window = plot.viewing
            const track = plot.path.filter(point => point.time > window.start.time && point.time < window.end.time)
            trace([window.start, ...track, window.end], plot.accent, 3, false)
            const marks = [window.start, window.peak, window.end]
            const labels = [[-10, -13], [3, -16], [13, -8]]
            for (let i = 0; i < marks.length; i++) {
                const point = plot.project(marks[i])
                ctx.beginPath()
                ctx.arc(point.x, point.y, 4, 0, Math.PI * 2)
                ctx.fillStyle = App.Palette.surface
                ctx.fill()
                ctx.strokeStyle = plot.accent
                ctx.lineWidth = 1.5
                ctx.stroke()
                ctx.fillStyle = App.Palette.ink
                ctx.fillText(String(i + 1), point.x + labels[i][0], point.y + labels[i][1])
            }
        }
    }

    Rectangle {
        readonly property point projected: plot.position ? plot.project(plot.position) : Qt.point(0, 0)
        visible: plot.position !== null
        width: 15
        height: width
        radius: width / 2
        x: projected.x - width / 2
        y: projected.y - height / 2
        color: "transparent"
        border.width: 2
        border.color: plot.violet
    }
}
