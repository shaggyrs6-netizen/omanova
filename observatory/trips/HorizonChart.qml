import QtQuick
Canvas {
    id: chart
    property var sectors: []
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
    onPaint: {
        const c=getContext("2d");c.clearRect(0,0,width,height)
        const left=36, right=width-14, top=12, bottom=height-30
        c.font="12px sans-serif";c.textAlign="right";c.textBaseline="middle"
        for(let el=0;el<=90;el+=15) {
            const y=bottom-(bottom-top)*el/90
            c.strokeStyle="#2a3e58";c.beginPath();c.moveTo(left,y);c.lineTo(right,y);c.stroke()
            c.fillStyle="#a7b7ce";c.fillText(el+"°",left-6,y)
        }
        c.textAlign="center"
        const labels=["N","NE","E","SE","S","SW","W","NW","N"]
        for(let i=0;i<labels.length;i++)c.fillText(labels[i],left+(right-left)*i/8,bottom+17)
        c.beginPath();c.moveTo(left,bottom)
        for(let a=0;a<=360;a++)c.lineTo(left+(right-left)*a/360,bottom-(bottom-top)*heightAt(a===360?0:a)/90)
        c.lineTo(right,bottom);c.closePath();c.fillStyle="#284851";c.fill()
        c.beginPath()
        for(let a=0;a<=360;a++) {
            const x=left+(right-left)*a/360,y=bottom-(bottom-top)*heightAt(a===360?0:a)/90
            if(a===0)c.moveTo(x,y);else c.lineTo(x,y)
        }
        c.strokeStyle="#70edeb";c.lineWidth=2;c.stroke()
    }
}
