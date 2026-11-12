import QtQuick

Canvas {
    id: root
    property var points: []
    property bool highlightVisibility: true
    Accessible.name: "North-up sky compass. Concentric rings show elevation, with zenith at the centre."
    onPointsChanged: requestPaint()
    onHighlightVisibilityChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    property color ink: "#eef5ff"
    property color accent: "#70edeb"
    onInkChanged: requestPaint()
    onAccentChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        const x = width / 2, y = height / 2
        const radius = Math.max(0, Math.min(x, y) - 23)
        if (radius === 0) return
        ctx.lineWidth = 1
        ctx.strokeStyle = ink
        ctx.fillStyle = ink
        ctx.globalAlpha = 0.33
        for (let i = 1; i <= 3; i++) {
            ctx.beginPath()
            ctx.arc(x, y, radius * i / 3, 0, Math.PI * 2)
            ctx.stroke()
        }
        ctx.beginPath()
        ctx.moveTo(x - radius, y); ctx.lineTo(x + radius, y)
        ctx.moveTo(x, y - radius); ctx.lineTo(x, y + radius)
        ctx.stroke()
        ctx.globalAlpha = 1
        ctx.font = "13px sans-serif"
        ctx.textAlign = "center"
        ctx.textBaseline = "middle"
        ctx.fillText("N", x, y - radius - 13)
        ctx.fillText("S", x, y + radius + 13)
        ctx.fillText("W", x - radius - 13, y)
        ctx.fillText("E", x + radius + 13, y)
        for (let i = 1; i < points.length; i++) {
            const a = points[i - 1], b = points[i]
            const aRad = a.az * Math.PI / 180, bRad = b.az * Math.PI / 180
            const ar = radius * (1 - Math.max(0, a.el) / 90)
            const br = radius * (1 - Math.max(0, b.el) / 90)
            const visible = root.highlightVisibility && a.visible && b.visible
            ctx.strokeStyle = visible ? accent : ink
            ctx.globalAlpha = visible ? 1 : 0.55
            ctx.lineWidth = visible ? 3 : 1
            ctx.beginPath()
            ctx.moveTo(x + ar * Math.sin(aRad), y - ar * Math.cos(aRad))
            ctx.lineTo(x + br * Math.sin(bRad), y - br * Math.cos(bRad))
            ctx.stroke()
        }
        if (points.length === 1) {
            const p = points[0], angle = p.az * Math.PI / 180
            const distance = radius * (1 - Math.max(0, Math.min(90, p.el)) / 90)
            ctx.globalAlpha = 1; ctx.fillStyle = accent
            ctx.beginPath(); ctx.arc(x + distance*Math.sin(angle), y - distance*Math.cos(angle), 5, 0, Math.PI*2); ctx.fill()
        }
        ctx.globalAlpha = 1
    }
}
