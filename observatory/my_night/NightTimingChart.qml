import "./qml/Omanova" as App
import QtQuick

Canvas {
    id: chart
    property var data: null
    readonly property string foreground: App.Palette.ink
    readonly property string accent: App.Palette.accent
    readonly property string warning: App.Palette.warning
    readonly property string grid: App.Palette.line
    readonly property string muted: App.Palette.muted
    readonly property string surface: App.Palette.surface
    onDataChanged: requestPaint()
    onForegroundChanged: requestPaint()
    onAccentChanged: requestPaint()
    onWarningChanged: requestPaint()
    onGridChanged: requestPaint()
    onMutedChanged: requestPaint()
    onSurfaceChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Accessible.role: Accessible.Graphic
    Accessible.name: "Timing chart. Begin, best and end times are listed above."
    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        if (!data) return
        const a = Date.parse(data.start), b = Date.parse(data.end)
        if (!(b > a) || width < 110) return
        const left = 40, right = width - 12, top = 12, bottom = height - 36
        const low = data.points.length ? Math.min(0, ...data.points.map(p=>p.el)) : 0
        function x(t) { return left + (Date.parse(t)-a)/(b-a)*(right-left) }
        function y(el) { return bottom - (el-low)/(90-low)*(bottom-top) }
        ctx.fillStyle = surface
        ctx.fillRect(0,0,width,height)
        ctx.save()
        ctx.beginPath();ctx.rect(left,top,right-left,bottom-top);ctx.clip()
        ctx.fillStyle = accent
        ctx.globalAlpha = .09
        for (let i=0;i<data.dark.length-1;i++) {
            if (data.dark[i].dark) ctx.fillRect(x(data.dark[i].time),top,x(data.dark[i+1].time)-x(data.dark[i].time),bottom-top)
        }
        ctx.globalAlpha = .21
        if (data.window.length===2)
            ctx.fillRect(x(data.window[0]),top,x(data.window[1])-x(data.window[0]),bottom-top)
        ctx.globalAlpha = 1
        ctx.strokeStyle = grid
        for (let el=0;el<=90;el+=30) {
            ctx.beginPath();ctx.moveTo(left,y(el));ctx.lineTo(right,y(el));ctx.stroke()
        }
        function line(key,color,dashed) {
            ctx.strokeStyle=color
            ctx.lineWidth=dashed?1.4:2.3
            ctx.setLineDash(dashed?[5,4]:[])
            ctx.beginPath()
            data.points.forEach((p,i)=>i===0?ctx.moveTo(x(p.time),y(p[key])):ctx.lineTo(x(p.time),y(p[key])))
            ctx.stroke()
        }
        if (data.points.length) {
            line("horizon",warning,true)
            line("el",accent,false)
        }
        if (data.best && data.window.length && Date.parse(data.best)>=Date.parse(data.window[0]) &&
                Date.parse(data.best)<=Date.parse(data.window[1])) {
            ctx.strokeStyle=foreground;ctx.lineWidth=1;ctx.setLineDash([2,4])
            ctx.beginPath();ctx.moveTo(x(data.best),top);ctx.lineTo(x(data.best),bottom);ctx.stroke()
        }
        ctx.restore()
        ctx.font="12px sans-serif";ctx.fillStyle=muted
        for (let el=0;el<=90;el+=30) ctx.fillText(el+"°",6,Math.max(12,y(el)+4))
        ctx.save()
        ctx.beginPath();ctx.rect(left,bottom+9,right-left,16);ctx.clip()
        ctx.fillStyle=muted
        ctx.globalAlpha=.55
        for (const hour of data.clouds) {
            const at=x(hour.time), span=(right-left)*3600000/(b-a)
            ctx.fillRect(at,bottom+28-hour.value*.17,span-1,hour.value*.17)
        }
        ctx.restore()
        for (const tick of data.ticks) {
            const offset=ctx.measureText(tick.label).width
            ctx.fillText(tick.label,Math.min(width-offset-2,Math.max(left-10,x(tick.time)-offset/2)),height-2)
        }
    }
}
