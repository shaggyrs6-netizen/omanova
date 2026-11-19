import "../../qml/Omanova" as App
import QtQuick
Canvas {
 id:root
 property var dataSet:null
 Accessible.name:"Upright celestial pole diagram, not an optical reticle. Reference star offset from centre."
 onDataSetChanged:requestPaint();onWidthChanged:requestPaint();onHeightChanged:requestPaint()
 Connections {target:App.Palette;function onResolvedChanged(){root.requestPaint()}function onObservingModeChanged(){root.requestPaint()}}
 onPaint:{
  let c=getContext("2d");c.reset();if(!dataSet?.reference)return;let x=width/2,y=height/2,r=Math.min(width,height)/2-32,scale=r/1.5;
  c.font="12px sans-serif";c.textAlign="center";c.fillStyle=App.Palette.muted;c.fillText("Towards zenith · upright sky view",x,15);
  c.strokeStyle=App.Palette.border;c.lineWidth=1;for(let d of [.5,1,1.5]){c.beginPath();c.arc(x,y,d*scale,0,Math.PI*2);c.stroke();c.fillText(d+"°",x+8,y-d*scale+13)}
  c.strokeStyle=App.Palette.accent;c.beginPath();c.moveTo(x-8,y);c.lineTo(x+8,y);c.moveTo(x,y-8);c.lineTo(x,y+8);c.stroke();
  c.fillStyle=App.Palette.accent;c.fillText(dataSet.north?"NCP":"SCP",x+25,y+5);
  let px=x+dataSet.x*scale,py=y-dataSet.y*scale;c.fillStyle=App.Palette.ink;c.beginPath();c.arc(px,py,5,0,Math.PI*2);c.fill();c.fillText(dataSet.reference,px,py-12);
  c.fillStyle=App.Palette.muted;c.fillText(dataSet.north?"East ←   ·   → West":"West ←   ·   → East",x,height-10);
 }
}
