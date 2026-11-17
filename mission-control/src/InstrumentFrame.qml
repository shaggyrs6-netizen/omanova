import QtQuick

Item {
 id: frame
 property color edge: "#285769"
 property color accent: "#5de7ef"
 property color topFill: "#0a1c2c"
 property color bottomFill: "#040c17"
 property bool emphasis: false
 Canvas {
  id: surface
  anchors.fill: parent
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  Connections {target:frame; function onEdgeChanged(){surface.requestPaint()} function onEmphasisChanged(){surface.requestPaint()} function onTopFillChanged(){surface.requestPaint()} function onBottomFillChanged(){surface.requestPaint()} function onAccentChanged(){surface.requestPaint()}}
  onPaint: {
   let c=getContext("2d"),w=width,h=height,k=12
   c.clearRect(0,0,w,h)
   c.beginPath();c.moveTo(k,.5);c.lineTo(w-k,.5);c.lineTo(w-.5,k);c.lineTo(w-.5,h-k);c.lineTo(w-k,h-.5);c.lineTo(.5,h-.5);c.lineTo(.5,k);c.closePath()
   let g=c.createLinearGradient(0,0,w,h);g.addColorStop(0,frame.topFill);g.addColorStop(1,frame.bottomFill);c.fillStyle=g;c.fill();c.strokeStyle=frame.edge;c.lineWidth=1;c.stroke()
   c.strokeStyle=frame.accent;c.lineWidth=frame.emphasis?2:1.4
   c.beginPath();c.moveTo(.5,30);c.lineTo(.5,k);c.lineTo(k,.5);c.lineTo(Math.min(w*.23,86),.5);c.stroke()
   c.beginPath();c.moveTo(w-48,h-.5);c.lineTo(w-k,h-.5);c.lineTo(w-.5,h-k);c.lineTo(w-.5,h-29);c.stroke()
  }
 }
}
