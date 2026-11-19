import "../../qml/Omanova" as App
import QtQuick
import "CameraProjection.js" as Projection

Rectangle {
    id: view
    required property var dataSet
    required property var camera
    required property var axes
    required property var centre
    readonly property var half: camera ? Projection.halfFrame(camera) : null
    readonly property var points: projectedObjects()
    readonly property string summary: {
        if (!axes) return ""
        const inside = points.filter(point => Math.abs(point.xy.x)<=half.x && Math.abs(point.xy.y)<=half.y)
        const targets = inside.filter(point => point.row.extent).map(point => point.row.id)
        const stars = inside.filter(point => point.row.mag!==undefined).length
        return (targets.length ? "Target centres in frame: "+targets.join(", ") : "No catalogue target centres in frame") +
            " · "+stars+" catalogue "+(stars===1?"star":"stars")
    }
    readonly property string targetFit: {
        if (!axes || !centre?.extent || !half) return ""
        const outline = Projection.targetOutline(centre, axes)
        const fits = outline.every(point => point && Math.abs(point.x)<=half.x && Math.abs(point.y)<=half.y)
        return fits ? "Approximate target outline fits inside the frame." :
                      "Approximate target outline extends beyond the frame."
    }
    color: App.Palette.field
    radius: 8
    border.color: App.Palette.border
    Accessible.name: "Camera framing detail. " + targetFit + " " + summary

    function projectedObjects() {
        if (!axes || !half || !dataSet) return []
        const objects = (dataSet.stars || []).concat(dataSet.objects || [], dataSet.targets || [])
        const result = []
        for (const row of objects) {
            const xy = Projection.project(row, axes)
            if (xy) result.push({row, xy})
        }
        return result
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: view
            function onPointsChanged() { canvas.requestPaint() }
            function onHalfChanged() { canvas.requestPaint() }
        }
        Connections {
            target: App.Palette
            function onResolvedChanged() { canvas.requestPaint() }
            function onObservingModeChanged() { canvas.requestPaint() }
        }
        onPaint: {
            const c = getContext("2d")
            c.reset()
            if (!view.axes || !view.half || width < 60 || height < 70) return
            const half = view.half
            const scale = Math.min((width-52)/(2*half.x), (height-62)/(2*half.y))
            const cx = width/2, cy = (height+10)/2
            const left = cx-half.x*scale, top = cy-half.y*scale, w = 2*half.x*scale, h = 2*half.y*scale
            c.fillStyle = App.Palette.background
            c.fillRect(left, top, w, h)
            c.font = "12px sans-serif"
            c.textAlign = "left"
            c.fillStyle = App.Palette.muted
            c.fillText("CAMERA FIELD", 14, 22)

            c.save()
            c.beginPath()
            c.rect(10, 30, width-20, height-40)
            c.clip()
            for (const point of view.points) {
                const row = point.row, xy = point.xy
                const x = cx+xy.x*scale, y = cy-xy.y*scale
                const inside = Math.abs(xy.x)<=half.x && Math.abs(xy.y)<=half.y
                c.globalAlpha = row.clear ? (inside ? 1 : .55) : .32
                if (row.extent) {
                    const outline = Projection.targetOutline(row, view.axes)
                    c.beginPath()
                    let started = false
                    for (const q of outline) {
                        if (!q) {started=false;continue}
                        const u=cx+q.x*scale, v=cy-q.y*scale
                        if (started) c.lineTo(u,v)
                        else {c.moveTo(u,v);started=true}
                    }
                    c.strokeStyle = App.Palette.warning
                    c.lineWidth = 1
                    c.setLineDash([4,3])
                    c.stroke()
                    c.setLineDash([])
                }
                if (x < 12 || x > width-10 || y < 32 || y > height-10) continue
                const r = row.mag === undefined ? 3 : Math.max(1,3-row.mag*.4)
                c.fillStyle = row.extent ? App.Palette.warning : App.Palette.ink
                c.beginPath()
                c.arc(x,y,r,0,Math.PI*2)
                c.fill()
                if (row.mag === undefined || row.mag < 3)
                    c.fillText(row.extent ? row.id : row.name, x+6, y-5)
            }
            c.restore()
            c.globalAlpha = 1
            c.strokeStyle = App.Palette.accent
            c.lineWidth = 2
            c.strokeRect(left,top,w,h)
            c.beginPath()
            c.moveTo(cx-5,cy);c.lineTo(cx+5,cy)
            c.moveTo(cx,cy-5);c.lineTo(cx,cy+5)
            c.stroke()
        }
    }
}
