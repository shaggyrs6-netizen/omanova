import "./qml/Omanova" as App
import QtQuick
Rectangle {
 id:root
 property var dataSet:null
 property string selection:""
 property var hits:[]
 color:App.Palette.field;radius:8;border.color:App.Palette.border
 Accessible.name:"Whole sky chart, north up and east left. Tap a star or planet for bearing and elevation."
 function xy(az,el) {let a=az*Math.PI/180,r=(Math.min(width,height)-80)/2*(90-el)/90;return Qt.point(width/2-r*Math.sin(a),height/2-r*Math.cos(a))}
 onDataSetChanged:{selection="";canvas.requestPaint()}
 Canvas {id:canvas;anchors.fill:parent;onWidthChanged:requestPaint();onHeightChanged:requestPaint()
  Connections {target:App.Palette;function onResolvedChanged(){canvas.requestPaint()}function onObservingModeChanged(){canvas.requestPaint()}}
  onPaint:{
   let c=getContext("2d");c.reset();let r=(Math.min(width,height)-80)/2,x=width/2,y=height/2;
   c.strokeStyle=App.Palette.border;c.lineWidth=1;c.font="12px sans-serif";c.textAlign="center";c.fillStyle=App.Palette.muted;
   for(let alt of [0,30,60]){c.beginPath();c.arc(x,y,r*(90-alt)/90,0,Math.PI*2);c.stroke();c.fillText(alt+"°",x+8,y-r*(90-alt)/90+14)}
   for(let v of [["N",x,y-r-14],["S",x,y+r+23],["E",x-r-18,y],["W",x+r+18,y]])c.fillText(v[0],v[1],v[2]);
   if(!root.dataSet?.stars||!root.dataSet?.horizon)return;
   c.beginPath();for(let a=0;a<=360;a++){let p=root.xy(a,root.dataSet.horizon[a%360]||0);if(a===0)c.moveTo(p.x,p.y);else c.lineTo(p.x,p.y)}c.closePath();c.strokeStyle=App.Palette.warning;c.setLineDash([3,4]);c.stroke();c.setLineDash([]);
   let stars=root.dataSet.stars,by={};for(let s of stars)by[s.id]=s;
   c.strokeStyle=App.Palette.border;c.lineWidth=1.2;
   for(let l of root.dataSet.lines){let a=by[l.a],b=by[l.b];if(!a||!b)continue;let p=root.xy(a.az,a.el),q=root.xy(b.az,b.el);c.beginPath();c.moveTo(p.x,p.y);c.lineTo(q.x,q.y);c.stroke()}
   let hits=[];
   for(let s of stars){let p=root.xy(s.az,s.el);c.beginPath();c.arc(p.x,p.y,Math.max(1,3.6-s.mag*.48),0,Math.PI*2);c.fillStyle=s.clear?App.Palette.ink:App.Palette.muted;c.globalAlpha=s.clear?1:.35;c.fill();c.globalAlpha=1;hits.push(Object.assign({},s,{x:p.x,y:p.y}));if(s.mag<1.4&&s.clear){c.fillStyle=App.Palette.muted;c.font="11px sans-serif";c.fillText(s.name,p.x,p.y-8)}}
   c.font="13px sans-serif";
   for(let s of root.dataSet.objects){let p=root.xy(s.az,s.el);c.beginPath();c.arc(p.x,p.y,5,0,Math.PI*2);c.fillStyle=s.name==="Sun"?App.Palette.warning:App.Palette.accent;c.fill();c.fillText(s.name,p.x,p.y-10);hits.push(Object.assign({},s,{x:p.x,y:p.y}))}
   root.hits=hits;
  }
 }
 MouseArea {anchors.fill:parent;onClicked:function(mouse){let nearest=null,d=18;for(let s of root.hits){let v=Math.hypot(s.x-mouse.x,s.y-mouse.y);if(v<d){d=v;nearest=s}}root.selection=nearest?nearest.name+" · "+nearest.az.toFixed(1)+"° true bearing · "+nearest.el.toFixed(1)+"° up"+(nearest.clear?"":" · saved horizon blocked"):"Tap closer to a star or planet"}}
 Text {anchors.bottom:parent.bottom;anchors.horizontalCenter:parent.horizontalCenter;anchors.bottomMargin:8;width:parent.width-20;horizontalAlignment:Text.AlignHCenter;wrapMode:Text.Wrap;text:root.selection;textFormat:Text.PlainText;color:App.Palette.ink;font.pixelSize:13}
}
