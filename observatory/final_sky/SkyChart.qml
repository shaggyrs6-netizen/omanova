import "../../qml/Omanova" as App
import QtQuick
import "CameraProjection.js" as CameraProjection
Rectangle {
 id:root
 property var dataSet:null
 property string objectName: ""
 property int starId: 0
 readonly property var selectedObject: {
  if (selectedSatellite) return satellites.find(o => o.id === selectedSatellite) || null
  if (starId) return dataSet?.stars?.find(o => o.id === starId) || null
  if (objectName) return dataSet?.objects?.find(o => o.name === objectName) || null
  return dataSet?.objects?.find(o => o.name === "Saturn") || dataSet?.objects?.[0] || dataSet?.stars?.[0] || null
 }
 readonly property string selection: selectedObject ? describe(selectedObject) : ""
 onSelectedObjectChanged: canvas.requestPaint()
 property var hits:[]
 property bool framing:false
 property var cameraCentre:null
 property var cameraFootprint:[]
 signal centreCamera(var point)
 onFramingChanged:canvas.requestPaint()
 onCameraCentreChanged:canvas.requestPaint()
 onCameraFootprintChanged:canvas.requestPaint()
 property var satellites:[]
 property int selectedSatellite:0
 onSelectedSatelliteChanged:canvas.requestPaint()
 property var formatDistance:km=>Math.round(km)+" km"
 onSatellitesChanged:canvas.requestPaint()
 color:App.Palette.field;radius:8;border.color:App.Palette.border
 Accessible.name:framing?"Whole sky chart. Tap the sky to centre the camera frame.":"Whole sky chart, north up and east left. Tap a star or planet for bearing and elevation."
 function chooseObject(item, satellite) {
  selectedSatellite = satellite ? item.id : 0
  starId = satellite ? 0 : item.id || 0
  objectName = item.name
 }
 function describe(s){return s.name+" · "+s.az.toFixed(1)+"° true bearing · "+s.el.toFixed(1)+"° up"+(s.clear?"":" · saved horizon blocked")+(s.satellite||s.id===selectedSatellite?" · "+root.formatDistance(s.rangeKm,0)+" slant range · elements "+s.ageHours.toFixed(1)+" h old · "+s.status:"")}
 function xy(az,el) {let a=az*Math.PI/180,r=(Math.min(width,canvas.height)-80)/2*(90-el)/90;return Qt.point(width/2-r*Math.sin(a),canvas.height/2-r*Math.cos(a))}
 onDataSetChanged:{canvas.requestPaint()}
 Canvas {id:canvas;anchors.fill:parent;onWidthChanged:requestPaint();onHeightChanged:requestPaint()
  Connections {target:App.Palette;function onResolvedChanged(){canvas.requestPaint()}function onObservingModeChanged(){canvas.requestPaint()}}
  onPaint:{
   const c=getContext("2d")
   c.reset()
   const r=(Math.min(width,height)-80)/2,x=width/2,y=height/2
   if(r<8)return
   const atlasColours=!App.Palette.themed
   const background=c.createRadialGradient(x,y,0,x,y,r)
   background.addColorStop(0,atlasColours?"#10283c":App.Palette.surface)
   background.addColorStop(1,atlasColours?"#0a1426":App.Palette.field)
   c.fillStyle=background
   c.beginPath();c.arc(x,y,r,0,Math.PI*2);c.fill()
   c.strokeStyle=atlasColours?"#3a5378":App.Palette.border
   c.lineWidth=1;c.font="12px sans-serif";c.textAlign="center";c.fillStyle=App.Palette.muted
   c.setLineDash([3,5])
   for(let az=0;az<360;az+=30){
    const p=root.xy(az,0)
    c.beginPath();c.moveTo(x,y);c.lineTo(p.x,p.y);c.stroke()
   }
   for(const alt of [30,60]){
    c.beginPath();c.arc(x,y,r*(90-alt)/90,0,Math.PI*2);c.stroke()
    c.fillText(alt+"°",x+10,y-r*(90-alt)/90+13)
   }
   c.setLineDash([])
   c.strokeStyle=atlasColours?"#87dded":App.Palette.accent
   c.lineWidth=1.8;c.beginPath();c.arc(x,y,r,0,Math.PI*2);c.stroke()
   c.fillStyle=App.Palette.ink;c.font="bold 14px sans-serif"
   for(const v of [["N",x,y-r-14],["S",x,y+r+23],["E",x-r-18,y+4],["W",x+r+18,y+4]])c.fillText(v[0],v[1],v[2]);
   if(!root.dataSet?.stars||!root.dataSet?.horizon)return;
   c.beginPath();for(let a=0;a<=360;a++){let p=root.xy(a,root.dataSet.horizon[a%360]||0);if(a===0)c.moveTo(p.x,p.y);else c.lineTo(p.x,p.y)}c.closePath();c.strokeStyle=App.Palette.warning;c.setLineDash([3,4]);c.stroke();c.setLineDash([]);
   let stars=root.dataSet.stars,by={};for(let s of stars)by[s.id]=s;
   const constellations=new Map()
   c.strokeStyle=atlasColours?"#688fa6":App.Palette.violet;c.lineWidth=1.15
   for(const line of root.dataSet.lines){
    const a=by[line.a],b=by[line.b]
    if(!a||!b)continue
    const p=root.xy(a.az,a.el),q=root.xy(b.az,b.el)
    c.globalAlpha=(a.clear&&b.clear) ? .8 : .32
    c.beginPath();c.moveTo(p.x,p.y);c.lineTo(q.x,q.y);c.stroke()
    if(line.name&&a.clear&&b.clear){
     const group=constellations.get(line.name)||[]
     group.push(p,q)
     constellations.set(line.name,group)
    }
   }
   const hits=[], labels=[]
   for(const star of stars){
    const p=root.xy(star.az,star.el)
    c.beginPath();c.arc(p.x,p.y,Math.max(.65,2.55-star.mag*.4),0,Math.PI*2)
    c.fillStyle=star.clear?App.Palette.ink:App.Palette.muted
    c.globalAlpha=star.clear?Math.max(.42,1-star.mag*.11):.24
    c.fill()
    hits.push(Object.assign({},star,{x:p.x,y:p.y}))
   }
   c.globalAlpha=1
   function label(name,x,y,colour){
    if(!name||labels.some(p=>Math.abs(p.x-x)<57&&Math.abs(p.y-y)<15))return
    labels.push({x,y})
    c.lineWidth=3;c.strokeStyle=App.Palette.field;c.strokeText(name,x,y)
    c.fillStyle=colour;c.fillText(name,x,y)
   }
   if(r>100){
    c.font="bold 12px sans-serif"
    for(const [name,points] of constellations){
     if(points.length<4)continue
     const sum=points.reduce((p,q)=>({x:p.x+q.x,y:p.y+q.y}),{x:0,y:0})
     label(name,sum.x/points.length,sum.y/points.length-9,atlasColours?"#c5d9e6":App.Palette.violet)
    }
   }
   c.font="11px sans-serif"
   for(const star of stars.filter(s=>s.mag<1.25&&s.clear).sort((a,b)=>a.mag-b.mag)){
    const p=root.xy(star.az,star.el)
    label(star.name,p.x,p.y-9,App.Palette.ink)
   }
   c.font="13px sans-serif";
   for(let s of root.dataSet.objects){let p=root.xy(s.az,s.el);c.beginPath();c.arc(p.x,p.y,5,0,Math.PI*2);c.fillStyle=s.name==="Sun"?App.Palette.warning:App.Palette.accent;c.fill();c.fillText(s.name,p.x,p.y-10);hits.push(Object.assign({},s,{x:p.x,y:p.y}))}
   for(let s of root.satellites){
    c.strokeStyle=App.Palette.accent;c.globalAlpha=s.potential?1:.45;c.lineWidth=1.5;c.beginPath();let first=true;
    for(let q of s.path){let p=root.xy(q.az,q.el);if(first){c.moveTo(p.x,p.y);first=false}else c.lineTo(p.x,p.y)}c.stroke();
    let p=root.xy(s.az,s.el);c.fillStyle=App.Palette.accent;c.beginPath();c.moveTo(p.x,p.y-6);c.lineTo(p.x+6,p.y);c.lineTo(p.x,p.y+6);c.lineTo(p.x-6,p.y);c.closePath();c.fill();c.globalAlpha=1;c.font="12px sans-serif";c.fillText(s.name,p.x,p.y-10);
    hits.push(Object.assign({},s,{x:p.x,y:p.y,satellite:true}));
   }
   if(root.framing){
    for(const s of root.dataSet.targets||[]){
     const p=root.xy(s.az,s.el);
     c.strokeStyle=App.Palette.warning;c.globalAlpha=s.clear?1:.35;c.lineWidth=1;c.strokeRect(p.x-3,p.y-3,6,6);c.globalAlpha=1;
     hits.push(Object.assign({},s,{x:p.x,y:p.y,catalogueTarget:true}));
    }
   }
   if(root.cameraFootprint.length&&root.cameraCentre){
    c.save();c.beginPath();c.arc(x,y,r,0,Math.PI*2);c.clip();
    c.beginPath();let first=true;
    for(const point of root.cameraFootprint){
     const p=root.xy(point.az,point.el);
     if(first){c.moveTo(p.x,p.y);first=false}else c.lineTo(p.x,p.y);
    }
    c.closePath();
    c.fillStyle=App.Palette.accent;c.globalAlpha=.15;c.fill();c.globalAlpha=1;
    c.strokeStyle=App.Palette.accent;c.lineWidth=2;c.stroke();
    const centre=root.xy(root.cameraCentre.az,root.cameraCentre.el);
    c.beginPath();c.arc(centre.x,centre.y,5,0,Math.PI*2);c.stroke();
    c.restore();
   }
   root.hits=hits;
   if(root.selectedObject) {
    const point=root.xy(root.selectedObject.az, root.selectedObject.el)
    c.strokeStyle=App.Palette.accent;c.lineWidth=2;c.beginPath()
    c.arc(point.x,point.y,9,0,2*Math.PI);c.stroke()
   }

  }
 }
 MouseArea {
  anchors.fill:canvas
  onClicked:function(mouse){
   let nearest=null,d=18;
   for(let s of root.hits.slice().reverse()){
    let v=Math.hypot(s.x-mouse.x,s.y-mouse.y);
    if(v<d){d=v;nearest=s}
   }
   if(root.framing){
    const point=CameraProjection.chartDirection(mouse.x-width/2, mouse.y-height/2, (Math.min(width,height)-80)/2);
    if(point){
     root.centreCamera(nearest?.catalogueTarget ? {target:nearest.id} :
                       nearest && !nearest.satellite ? (nearest.id ? {star:nearest.id} : {object:nearest.name}) : point);
    }
    return;
   }
   if (!nearest) return
   root.chooseObject(nearest, !!nearest.satellite)
  }
 }
}
