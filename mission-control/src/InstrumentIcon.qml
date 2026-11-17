import QtQuick
Canvas {
 id: icon
 property int kind: 0
 property color ink: "#86e5ed"
 onKindChanged:requestPaint()
 onWidthChanged:requestPaint()
 onHeightChanged:requestPaint()
 onPaint:{
  let c=getContext("2d");c.clearRect(0,0,width,height);c.save();c.scale(width/48,height/48);c.strokeStyle=ink;c.fillStyle=ink;c.lineWidth=1.5
  if(kind===0){
   c.save();c.translate(24,24);c.rotate(-.45);c.strokeRect(-4,-9,8,18);c.strokeRect(-19,-12,11,24);c.strokeRect(8,-12,11,24)
   for(let y=-6;y<12;y+=6){c.beginPath();c.moveTo(-19,y);c.lineTo(-8,y);c.moveTo(8,y);c.lineTo(19,y);c.stroke()}
   c.beginPath();c.moveTo(-13,-12);c.lineTo(-13,12);c.moveTo(13,-12);c.lineTo(13,12);c.moveTo(-8,0);c.lineTo(8,0);c.stroke();c.restore()
  }else if(kind===2){
   c.beginPath();c.moveTo(24,4);c.bezierCurveTo(12,14,17,30,18,34);c.lineTo(30,34);c.bezierCurveTo(31,24,35,14,24,4);c.closePath();c.stroke()
   c.beginPath();c.arc(24,18,3,0,Math.PI*2);c.moveTo(17,25);c.lineTo(10,34);c.lineTo(18,32);c.moveTo(31,25);c.lineTo(38,34);c.lineTo(30,32);c.moveTo(20,37);c.lineTo(21,43);c.moveTo(25,37);c.lineTo(25,46);c.moveTo(29,37);c.lineTo(28,43);c.stroke()
  }else{
   c.beginPath();c.moveTo(10,32);c.bezierCurveTo(-1,25,10,16,16,21);c.bezierCurveTo(13,4,35,5,35,21);c.bezierCurveTo(46,15,48,34,38,34);c.lineTo(12,34);c.stroke()
   for(let x=17;x<36;x+=8){c.beginPath();c.moveTo(x,39);c.lineTo(x-3,44);c.stroke()}
  }
  c.restore()
 }
}
