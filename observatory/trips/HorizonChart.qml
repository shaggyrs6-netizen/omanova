import "./qml/Omanova" as App
import QtQuick
Canvas {
    id: chart
        Connections { target: App.Palette; function onResolvedChanged() { chart.requestPaint() } function onFollowChanged() { chart.requestPaint() } }
    property var sectors: []
    property var terrain: []
    onTerrainChanged: requestPaint()
    readonly property real ceiling: Math.max(10,Math.ceil(Math.max(0,...sectors.map(s=>s.height),...terrain)/5)*5)
    onCeilingChanged: requestPaint()
    Accessible.name: "Manual horizon profile: true compass bearing left to right, obstruction height bottom to top."
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
    function terrainAt(a) {
        if(terrain.length!==720)return 0
        const i=Math.floor(a*2)%720
        return terrain[i]
    }
    onPaint: {
        const c=getContext("2d");c.clearRect(0,0,width,height)
        const left=36, right=width-14, top=12, bottom=height-30
        c.setLineDash([]);c.font="12px sans-serif";c.textAlign="right";c.textBaseline="middle"
        for(let el=0;el<=ceiling;el+=ceiling/5) {
            const y=bottom-(bottom-top)*el/ceiling
            c.strokeStyle=App.Palette.line;c.beginPath();c.moveTo(left,y);c.lineTo(right,y);c.stroke()
            c.fillStyle=App.Palette.muted;c.fillText(Math.round(el)+"°",left-6,y)
        }
        c.textAlign="center"
        const labels=["N","NE","E","SE","S","SW","W","NW","N"]
        for(let i=0;i<labels.length;i++)c.fillText(labels[i],left+(right-left)*i/8,bottom+17)
        c.beginPath();c.moveTo(left,bottom)
        for(let a=0;a<=360;a++)c.lineTo(left+(right-left)*a/360,bottom-(bottom-top)*heightAt(a===360?0:a)/ceiling)
        c.lineTo(right,bottom);c.closePath();c.fillStyle=App.Palette.shade;c.fill()
        c.beginPath()
        for(let a=0;a<=360;a++) {
            const x=left+(right-left)*a/360,y=bottom-(bottom-top)*heightAt(a===360?0:a)/ceiling
            if(a===0)c.moveTo(x,y);else c.lineTo(x,y)
        }
        c.strokeStyle=App.Palette.accent;c.lineWidth=2;c.stroke()
        if(terrain.length===720) {
            c.beginPath()
            for(let i=0;i<=720;i++) {
                const x=left+(right-left)*i/720,y=bottom-(bottom-top)*terrain[i%720]/ceiling
                if(i===0)c.moveTo(x,y);else c.lineTo(x,y)
            }
            c.setLineDash([5,3]);c.strokeStyle=App.Palette.terrain;c.lineWidth=2;c.stroke()
        }
    }
}
