import QtQuick

Canvas {
    id: disk
    property real fraction: 0
    property bool waxing: true
    Accessible.name: "Moon phase diagram, " + (fraction > 0 && fraction < 0.01
        ? "less than 1" : Math.round(fraction * 100)) + " percent illuminated"
    onFractionChanged: requestPaint()
    onWaxingChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        const x = width / 2, y = height / 2, r = Math.min(width, height) * 0.42
        if (r < 3) return
        ctx.beginPath()
        ctx.arc(x, y, r, 0, Math.PI * 2)
        ctx.fillStyle = "#172840"
        ctx.strokeStyle = "#7588a7"
        ctx.lineWidth = 1.5
        ctx.fill()
        ctx.stroke()

        // Stylised surface shading keeps the disk readable near new Moon.
        function surface(fill) {
            ctx.fillStyle = fill
            for (const [dx, dy, size] of [[-0.32, -0.27, 0.22], [0.13, -0.4, 0.12],
                    [0.36, -0.05, 0.18], [-0.19, 0.23, 0.16], [0.2, 0.42, 0.11],
                    [-0.4, 0.42, 0.07]]) {
                ctx.beginPath()
                ctx.arc(x + dx * r, y + dy * r, size * r, 0, Math.PI * 2)
                ctx.fill()
            }
        }
        surface("#21344f")
        const side = waxing ? 1 : -1
        const terminator = 1 - 2 * Math.max(0, Math.min(1, fraction))
        ctx.beginPath()
        for (let i = 0; i <= 120; i++) {
            const vertical = (i / 60 - 1) * r
            const horizontal = Math.sqrt(Math.max(0, r * r - vertical * vertical))
            const edge = x + side * horizontal
            if (i === 0) ctx.moveTo(edge, y + vertical)
            else ctx.lineTo(edge, y + vertical)
        }
        for (let i = 120; i >= 0; i--) {
            const vertical = (i / 60 - 1) * r
            const horizontal = Math.sqrt(Math.max(0, r * r - vertical * vertical))
            ctx.lineTo(x + side * terminator * horizontal, y + vertical)
        }
        ctx.closePath()
        const light = ctx.createRadialGradient(x - r * 0.2, y - r * 0.25, r * 0.1, x, y, r)
        light.addColorStop(0, "#f2f7ff")
        light.addColorStop(1, "#a3b5cf")
        ctx.fillStyle = light
        ctx.fill()
        ctx.save()
        ctx.clip()
        surface("#899eb9")
        ctx.restore()
    }
}
