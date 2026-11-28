import "../../qml/Omanova" as App
import QtQuick
Canvas {
    id: chart
        Connections { target: App.Palette; function onResolvedChanged() { chart.requestPaint() } function onFollowChanged() { chart.requestPaint() } }
    property var sectors: []
    property var terrain: []
    property var sky: null
    property bool below: true
    signal selectObject(string name)
    readonly property real floor: sky && below ? -20 : 0
    readonly property real xStart: 36
    readonly property real xEnd: width - 14
    readonly property var markers: sky ? sky.objects.concat(sky.targets.filter(target => target.mag !== undefined)) : []
    onSkyChanged: requestPaint()
    onBelowChanged: requestPaint()
    onTerrainChanged: requestPaint()
    readonly property real ceiling: sky ? 90 : Math.max(10,Math.ceil(Math.max(0,...sectors.map(s=>s.height),...terrain)/5)*5)
    onCeilingChanged: requestPaint()
    Accessible.name: "Sky and horizon profile. True compass bearing left to right, altitude bottom to top. Use the object selector to inspect a target."
    onSectorsChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    function heightAt(a) {
        let height = 0
        for (const s of sectors) {
            const inside = s.from < s.to ? a >= s.from && a <= s.to : a >= s.from || a <= s.to
            if (inside) height = Math.max(height, s.height)
        }
        return height
    }
    function xAt(bearing) { return xStart+(xEnd-xStart)*bearing/360 }
    function yAt(elevation) { return height-30-(height-44)*(elevation-floor)/(ceiling-floor) }
    TapHandler {
        onTapped: point => {
            let distance = 18
            let selected = ""
            for (const target of chart.markers) {
                if (target.el < chart.floor) continue
                const delta = Math.hypot(chart.xAt(target.az)-point.position.x, chart.yAt(target.el)-point.position.y)
                if (delta < distance) {
                    distance = delta
                    selected = target.name
                }
            }
            if (selected) chart.selectObject(selected)
        }
    }
    onPaint: {
        const c=getContext("2d");c.clearRect(0,0,width,height)
        const left=xStart, right=xEnd, bottom=yAt(0)
        c.setLineDash([]);c.font="12px sans-serif";c.textAlign="right";c.textBaseline="middle"
        for(let el=0;el<=ceiling;el+=sky?15:ceiling/5) {
            const y=yAt(el)
            c.strokeStyle=App.Palette.line;c.beginPath();c.moveTo(left,y);c.lineTo(right,y);c.stroke()
            c.fillStyle=App.Palette.muted;c.fillText(Math.round(el)+"°",left-6,y)
        }
        if (floor < 0) {
            c.fillStyle=App.Palette.shade;c.fillRect(left,bottom,right-left,yAt(floor)-bottom)
            c.fillStyle=App.Palette.muted;c.fillText("−20°",left-6,yAt(floor))
        }
        c.textAlign="center"
        const labels=["N","NE","E","SE","S","SW","W","NW","N"]
        for(let i=0;i<labels.length;i++)c.fillText(labels[i],left+(right-left)*i/8,height-13)
        c.beginPath();c.moveTo(left,bottom)
        for(let a=0;a<=360;a++)c.lineTo(left+(right-left)*a/360,yAt(heightAt(a===360?0:a)))
        c.lineTo(right,bottom);c.closePath();c.fillStyle=App.Palette.shade;c.fill()
        c.beginPath()
        for(let a=0;a<=360;a++) {
            const x=left+(right-left)*a/360,y=yAt(heightAt(a===360?0:a))
            if(a===0)c.moveTo(x,y);else c.lineTo(x,y)
        }
        c.strokeStyle=App.Palette.accent;c.lineWidth=2;c.stroke()
        if(terrain.length===720) {
            c.beginPath();c.moveTo(left,bottom)
            for(let i=0;i<=720;i++)c.lineTo(xAt(i/2),yAt(terrain[i%720]))
            c.lineTo(right,bottom);c.closePath();c.fillStyle=App.Palette.shade;c.fill()
            c.beginPath()
            for(let i=0;i<=720;i++) {
                const x=left+(right-left)*i/720,y=yAt(terrain[i%720])
                if(i===0)c.moveTo(x,y);else c.lineTo(x,y)
            }
            c.setLineDash([5,3]);c.strokeStyle=App.Palette.terrain;c.lineWidth=2;c.stroke()
        }
        if (sky) {
            c.setLineDash([])
            for (const star of sky.stars) {
                if (star.el < floor) continue
                c.globalAlpha = star.status === "clear" ? 0.85 : 0.35
                c.fillStyle = App.Palette.ink
                c.beginPath();c.arc(xAt(star.az),yAt(star.el),Math.max(0.9,2.5-star.mag*0.45),0,Math.PI*2);c.fill()
            }
            c.globalAlpha=1
            const labels = []
            const ordered = [sky.selected].concat(markers.filter(target => target.name !== sky.selected.name))
            for (const target of ordered) {
                if (target.el < floor) continue
                const x=xAt(target.az), y=yAt(target.el)
                const selected=target.name===sky.selected.name
                c.fillStyle=target.status==="clear" ? App.Palette.ink : App.Palette.muted
                c.strokeStyle=target.status==="blocked" ? App.Palette.warning : App.Palette.muted
                c.lineWidth=1.5
                c.beginPath();c.arc(x,y,selected?5:target.mag===undefined?4:2.5,0,Math.PI*2)
                if(target.status==="clear")c.fill();else c.stroke()
                if(selected || target.mag===undefined) {
                    const textWidth=c.measureText(target.name).width
                    const labelX=x+textWidth+8>right ? Math.max(left,x-textWidth-8) : x+8
                    const labelY=y<26 ? y+14 : y-10
                    if (labels.some(label => Math.abs(label.y-labelY)<13 &&
                        label.x<labelX+textWidth+4 && label.x+label.width+4>labelX)) continue
                    labels.push({x:labelX,y:labelY,width:textWidth})
                    c.textAlign="left";c.fillText(target.name,labelX,labelY)
                }
            }
        }
    }
}
