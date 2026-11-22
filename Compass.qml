import "./qml/Omanova" as App
import "./qml/Omanova/StationGlyph.js" as StationGlyph
import QtQuick

Canvas {
    id: root
        Connections { target: App.Palette; function onResolvedChanged() { root.requestPaint() } function onFollowChanged() { root.requestPaint() } }
    property var points: []
    property var marker: null
    property bool instrument: false
    readonly property url starBackdrop: Qt.resolvedUrl("observatory/assets/mission-control-stars.jpg")
    readonly property bool useStarBackdrop: instrument && App.Palette.observingMode === "normal" && !App.Palette.themed
    readonly property bool hasStarBackdrop: useStarBackdrop && backdropReady
    property bool backdropReady: false

    function prepareBackdrop() {
        if (available && useStarBackdrop && !backdropReady)
            loadImage(starBackdrop)
        requestPaint()
    }

    onAvailableChanged: prepareBackdrop()
    onUseStarBackdropChanged: prepareBackdrop()
    onImageLoaded: {
        backdropReady = isImageLoaded(starBackdrop)
        requestPaint()
    }
    onInstrumentChanged: requestPaint()
    onMarkerChanged: requestPaint()
    property bool highlightVisibility: true
    Accessible.name: "North-up sky compass. Concentric rings show elevation, with zenith at the centre."
    onPointsChanged: requestPaint()
    onHighlightVisibilityChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    property color ink: App.Palette.ink
    property color accent: App.Palette.accent
    onInkChanged: requestPaint()
    onAccentChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        const x = width / 2, y = height / 2
        const radius = Math.max(0, Math.min(x, y) - 23)
        if (radius === 0) return
        const normalInstrument = root.instrument && !App.Palette.themed
        if (normalInstrument) {
            const shade = ctx.createRadialGradient(x,y,0,x,y,radius)
            shade.addColorStop(0,"#122e47");shade.addColorStop(1,"#091323")
            ctx.fillStyle=shade
            ctx.beginPath();ctx.arc(x,y,radius,0,2*Math.PI);ctx.fill()
        }
        if (hasStarBackdrop) {
            ctx.save()
            ctx.beginPath()
            ctx.arc(x, y, radius, 0, Math.PI * 2)
            ctx.clip()
            ctx.drawImage(starBackdrop, x - radius, y - radius, 2 * radius, 2 * radius)
            ctx.restore()
        }
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
        if(root.instrument) {
            ctx.strokeStyle=root.accent
            ctx.beginPath()
            for(let az=0;az<360;az+=10){
                const angle=az*Math.PI/180
                const tip=radius+3, start=radius-(az%30===0?5:2)
                ctx.moveTo(x+start*Math.sin(angle),y-start*Math.cos(angle))
                ctx.lineTo(x+tip*Math.sin(angle),y-tip*Math.cos(angle))
            }
            ctx.stroke()
        }
        ctx.globalAlpha = 1
        ctx.font = root.instrument ? "bold 14px sans-serif" : "13px sans-serif"
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
        if (marker || points.length === 1) {
            const p = marker || points[0], angle = p.az * Math.PI / 180
            const distance = radius * (1 - Math.max(0, Math.min(90, p.el)) / 90)
            const markerX = x + distance * Math.sin(angle), markerY = y - distance * Math.cos(angle)
            ctx.globalAlpha = 1
            if (instrument) {
                StationGlyph.draw(ctx, markerX, markerY, 27, accent, App.Palette.background)
            } else {
                ctx.fillStyle = accent
                ctx.beginPath()
                ctx.arc(markerX, markerY, 5, 0, Math.PI * 2)
                ctx.fill()
            }
        }
        ctx.globalAlpha = 1
    }
}
