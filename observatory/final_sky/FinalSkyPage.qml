import "../../qml/Omanova" as App
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "CameraProjection.js" as CameraProjection
Item {
 id: root
 required property var skyModel
 property string section: "chart"
 property string source: "active"
 property var dataSet: null
 property string pending: ""
 property string result: ""
 property double clock: Date.now()
 property int stationIndex: 0
 property bool satellitesOn:false
 property string fixtureTime:""
 property bool visibleOnly:true
 readonly property bool layerCurrent:!!dataSet && (fixture || (clock>=Date.parse(dataSet.generated) && clock-Date.parse(dataSet.generated)<=15000))
 readonly property bool fixture: skyModel.fixture
 readonly property string runtime: skyModel.runtime
 readonly property var station: dataSet?.stations?.[stationIndex] || null
 readonly property bool expired: !!dataSet && !fixture && (clock<Date.parse(dataSet.generated)||clock-Date.parse(dataSet.generated)>(section==="live"?30000:section==="transits"?300000:3600000))
 readonly property string title: ({chart:"Star Chart",live:"Live Orbit",polar:"Polar Alignment",transits:"Station Transits"})[section]
 signal openEquipment()
 property bool framing: false
 property string cameraName: ""
 property int cameraAngle: 0
 property var aim: ({az: 0, el: 90, name: "Zenith"})
 readonly property var cameras: skyModel.equipmentInvalid ? [] :
    (skyModel.equipmentProfile?.opticalSetups || []).filter(setup => !!setup.camera && setup.widthDeg>=.01 && setup.widthDeg<180 && setup.heightDeg>=.01 && setup.heightDeg<180)
 readonly property var camera: cameras.find(setup => setup.name===cameraName) ||
    cameras.find(setup => setup.name===skyModel.equipmentProfile?.activeOpticalSetup) || cameras[0] || null
 readonly property bool cameraMode: section==="chart" && framing && !!camera
 readonly property var cameraCentre: {
  if (!cameraMode || !dataSet) return null
  if (aim.target) return dataSet.targets?.find(target => target.id===aim.target) ?? null
  if (aim.star) return dataSet.stars?.find(star => star.id===aim.star) ?? null
  if (aim.object) return dataSet.objects?.find(object => object.name===aim.object) ?? null
  const horizon=dataSet.horizon?.[Math.round(aim.az)%360] ?? 0
  return {name:aim.name || "Chart point", az:aim.az, el:aim.el, clear:aim.el>horizon}
 }
 readonly property var axes: cameraCentre && Number.isFinite(dataSet?.poleAltitude) ?
    CameraProjection.basis(cameraCentre, dataSet.poleAltitude, cameraAngle) : null
 readonly property var cameraTargets: [{id:"", name:"Centre on a catalogue target…"}].concat(dataSet?.targets || [])
 function rotateCamera(degrees) {cameraAngle=((Math.round(degrees)%360)+360)%360}
 function request() {
  if(job.running)return
  pending=JSON.stringify({kind:section,source:source,time:instant.text,satellites:section==="chart"&&satellitesOn,fixtureNow:fixture?fixtureTime:""})+"\n"
  if(section!=="live" && !(section==="chart"&&satellitesOn))dataSet=null
  result="Calculating locally…";job.stdinEnabled=true;job.running=true
 }
 Component.onCompleted: if(section!=="transits")request()
 onSectionChanged: {satellitesOn=false;dataSet=null;instant.text="";if(section!=="transits")request()}
 Timer {interval:1000;running:true;repeat:true;onTriggered:root.clock=Date.now()}
 Timer {interval:root.section==="chart"?5000:10000;running:root.section==="live"||(root.section==="chart"&&root.satellitesOn);repeat:true;onTriggered:root.request()}
 Process {
  id:job
  command:[root.runtime+"/.venv/bin/python",root.runtime+"/observatory/final_sky/geometry.py","--state",root.skyModel.directory].concat(root.fixture?["--fixture"]:[])
  environment:({"OPENBLAS_NUM_THREADS":"1"});stdinEnabled:true
  onStarted:{write(root.pending);root.pending="";stdinEnabled=false}
  stdout:StdioCollector {id:output}
  stderr:StdioCollector {id:errors}
  onExited:function(code) {
   if(code===0) {try{let d=JSON.parse(output.text);if(d.kind===root.section&&d.source===root.source){root.clock=Date.now();root.dataSet=d;if(root.section==="chart"&&root.satellitesOn&&!d.satellites){Qt.callLater(root.request)}root.result="Local calculation · no downloads"}else if(root.section!=="transits")Qt.callLater(root.request)}catch(e){root.dataSet=null;root.result="Could not read sky calculation."}}
   else {root.dataSet=null;root.result=errors.text.trim()||"Calculation unavailable. Existing saved data retained."}
  }
 }
 component Copy:Text {Layout.fillWidth:true;color:App.Palette.ink;textFormat:Text.PlainText;wrapMode:Text.Wrap;font.pixelSize:14}
 component Action:TripButton {enabled:!job.running}
 ScrollView {id:scroll;anchors.fill:parent;clip:true;contentWidth:availableWidth;ScrollBar.horizontal.policy:ScrollBar.AlwaysOff
  ColumnLayout {width:scroll.availableWidth;spacing:14
   ColumnLayout {Layout.fillWidth:true;Layout.margins:24;spacing:12
    App.PageHeader {eyebrow:root.section==="live"||root.section==="transits"?"SATELLITES":"SKY";title:root.title}
    Copy {text:root.section==="chart"?"Your whole sky, at a chosen time. Tap a star or planet for its direction.":root.section==="polar"?"Set up an equatorial mount or star tracker. This aligns the tracking axis; it is not needed for ordinary alt-az viewing.":root.section==="live"?"ISS and Tiangong calculated from cached orbital elements. The ordinary Orbit page retains pass tracks and scrubbing.":"Search for ISS and Tiangong alignments with the Sun or Moon at this exact observing place. Candidates remain unconfirmed.";color:App.Palette.muted}
    Copy {visible:root.section==="transits";text:"SOLAR SAFETY · Never use unfiltered binoculars, a telescope or a camera to look at the Sun. Appropriate solar filters must be secured over the FRONT of every optical instrument. Eclipse glasses alone do not protect through optics. Equipment preferences do not certify solar safety.";color:App.Palette.warning;font.bold:true}
    Flow {Layout.fillWidth:true;spacing:8
     Repeater {model:[{id:"active",label:"Active location"},{id:"trip-home",label:"Trip Home"},{id:"trip-destination",label:"Trip destination"}]
      Action {required property var modelData;text:(root.source===modelData.id?"● ":"")+modelData.label;onClicked:{root.source=modelData.id;root.dataSet=null;instant.text="";if(root.section!=="transits")root.request()}}
     }
    }
    Flow {Layout.fillWidth:true;spacing:10
     TripField {id:instant;visible:root.section==="chart"||root.section==="polar";width:250;maximumLength:32;placeholderText:"UTC: 2026-11-15T02:00Z";Accessible.name:"Chart or pole time, ISO date with timezone";enabled:!job.running&&!root.satellitesOn}
     Action {text:root.section==="transits"?"Search next 24 hours locally":"Refresh locally";onClicked:root.request()}
     Action {visible:root.section==="chart"||root.section==="polar";text:"Use current time";onClicked:{instant.text="";root.request()}}
    }
    Copy {text:root.result;color:App.Palette.muted}
    Copy {visible:!!root.dataSet;text:(root.fixture?"DEMONSTRATION · ":"")+(root.dataSet?.place||"")+" · "+(root.dataSet?.localTime||"")+" · "+(root.dataSet?.zone||"")+"\nUTC "+(root.dataSet?.time||"");color:App.Palette.accent}
    Copy {visible:root.expired;text:"Old calculation / clock changed · refresh before using. Positions and candidates below are inspect-only.";color:App.Palette.warning;font.bold:true}
    Flow {visible:root.section==="chart";Layout.fillWidth:true;spacing:8
     Action {text:root.satellitesOn?"Live satellites · On":"Live satellites · Off";onClicked:{root.satellitesOn=!root.satellitesOn;instant.text="";root.request()}}
     Action {visible:root.satellitesOn;text:root.visibleOnly?"Potentially visible only":"All above horizon";onClicked:root.visibleOnly=!root.visibleOnly}
    }
    Copy {visible:root.section==="chart"&&root.satellitesOn;text:"LIVE SKY · current time, refreshed every 5 seconds from cached elements. Toggle off to choose another chart time. Tap a satellite for details.";color:App.Palette.accent}
    Copy {visible:root.section==="chart"&&root.satellitesOn&&root.layerCurrent;text:(root.dataSet?.satellites?.objects||[]).filter(s=>s.el>=0&&(!root.visibleOnly||s.potential)).length+" markers match · "+(root.dataSet?.satellites?.objects?.length||0)+" valid cached objects. Zero markers can mean none are above your horizon or match the filter.";color:App.Palette.muted}
    Copy {visible:root.section==="chart"&&root.satellitesOn&&!root.layerCurrent;text:"Satellite positions unavailable or old; markers withheld.";color:App.Palette.warning}
    Action {
     visible:root.section==="chart"
     text:root.framing?"Camera framing · On":"Camera framing · Off"
     onClicked:root.framing=!root.framing
    }
    Flow {
     visible:root.section==="chart"&&root.framing&&!root.camera
     Layout.fillWidth:true;spacing:8
     Action {text:"Set up a camera in My Equipment and Sky";onClicked:root.openEquipment()}
    }
    ColumnLayout {
     visible:root.cameraMode
     Layout.fillWidth:true;spacing:8
     Flow {
      Layout.fillWidth:true;spacing:8
      TripChoice {
       width:Math.min(230,parent.width)
       model:root.cameras.map(setup=>setup.name)
       currentIndex:root.cameras.findIndex(setup=>setup.name===root.camera?.name)
       Accessible.name:"Camera setup"
       onActivated:index=>root.cameraName=root.cameras[index].name
      }
      TripChoice {
       width:Math.min(275,parent.width)
       model:root.cameraTargets.map(target=>target.name)
       currentIndex:Math.max(0,root.cameraTargets.findIndex(target=>target.id===root.aim.target))
       Accessible.name:"Centre camera on a catalogue target"
       onActivated:index=>{
        if(index>0)root.aim={target:root.cameraTargets[index].id}
        else root.aim={az:0,el:90,name:"Zenith"}
       }
      }
      Action {text:"Centre on zenith";onClicked:root.aim={az:0,el:90,name:"Zenith"}}
     }
     Copy {text:"Tap the whole-sky chart to move the frame. Use the detail view to check what's inside.";color:App.Palette.muted}
     Copy {text:"Rotation "+root.cameraAngle+"°";font.bold:true}
     Flow {
      Layout.fillWidth:true;spacing:8
      Slider {
       width:Math.min(245,parent.width);height:38
       palette.highlight:App.Palette.accent
       from:0;to:359;stepSize:1
       value:root.cameraAngle
       onMoved:root.rotateCamera(value)
       Accessible.name:"Camera position angle in degrees"
      }
      Action {text:"+90°";Accessible.name:"Rotate camera 90 degrees";onClicked:root.rotateCamera(root.cameraAngle+90)}
      Action {text:"Reset angle";onClicked:root.rotateCamera(0)}
     }
     Copy {
      text:root.axes?.atPole ? "Angle uses the local chart reference at the celestial pole." :
          "0° points the top of the frame toward celestial north. Positive angles turn it toward celestial east."
      color:App.Palette.muted
     }
     Copy {
      visible:!!root.cameraCentre
      text:root.cameraCentre ? root.cameraCentre.name+" · "+root.camera.widthDeg.toPrecision(4)+"° × "+
          root.camera.heightDeg.toPrecision(4)+"°"+(root.cameraCentre.clear?"":" · behind saved horizon") : ""
      font.bold:true;color:root.cameraCentre?.clear?App.Palette.accent:App.Palette.warning
     }
     Copy {visible:!!root.dataSet&&!root.cameraCentre;text:"The selected centre is below the chart horizon at this time. Choose another point or time.";color:App.Palette.warning}
    }
    GridLayout {
     visible:root.section==="chart"&&!!root.dataSet
     Layout.fillWidth:true;columnSpacing:12;rowSpacing:12
     columns:root.cameraMode&&width>=860?2:1
     SkyChart {
      id:skyChart
      Layout.fillWidth:true;Layout.preferredWidth:450;Layout.preferredHeight:Math.min(520,width)
      dataSet:root.dataSet;formatDistance:root.skyModel.formatDistance
      satellites:root.satellitesOn&&root.layerCurrent?
          (root.dataSet?.satellites?.objects||[]).filter(s=>s.el>=0&&(!root.visibleOnly||s.potential)):[]
      framing:root.cameraMode;cameraCentre:root.cameraCentre
      cameraFootprint:root.axes ? CameraProjection.footprint(root.camera,root.axes) : []
      onCentreCamera:point=>root.aim=point
     }
     CameraChart {
      id:cameraChart
      visible:root.cameraMode&&!!root.axes
      Layout.fillWidth:true;Layout.preferredWidth:450;Layout.preferredHeight:skyChart.height
      dataSet:root.dataSet;camera:root.camera;axes:root.axes;centre:root.cameraCentre
     }
    }
    Copy {visible:root.cameraMode&&cameraChart.targetFit!=="";text:cameraChart.targetFit;font.bold:true}
    Copy {visible:root.cameraMode&&!!root.axes;text:cameraChart.summary;color:App.Palette.accent}
    Copy {
     visible:root.cameraMode&&!!root.axes
     text:"Dashed outlines show approximate catalogue sizes. Dim points are outside the frame or behind your saved horizon. Real target shapes and lens distortion can change the image."
     color:App.Palette.muted
    }
    Copy {visible:root.section==="chart"&&!!root.dataSet;text:"920 bright catalogue stars + Sun, Moon and five planets (above the geometric horizon only). Dotted/dim stars are behind your saved horizon. Some constellation guide lines only. "+((root.dataSet?.sunAltitude??-90)>-6?"DAYLIGHT / BRIGHT TWILIGHT: chart objects may be invisible.":"Weather, glare and equipment still affect visibility.");color:App.Palette.muted}
    ColumnLayout {visible:root.section==="polar"&&!!root.dataSet;Layout.fillWidth:true;spacing:10
     Copy {text:"Aim true "+(root.dataSet?.north?"north":"south")+" · "+(root.dataSet?.bearing??0)+"° bearing · pole "+Number(root.dataSet?.poleAltitude??0).toFixed(1)+"° above level horizon";font.pixelSize:19;font.bold:true}
     Copy {text:(root.dataSet?.reference||"")+" is "+Number(root.dataSet?.offset??0).toFixed(3)+"° from the pole · reference star "+Number(root.dataSet?.starAltitude??0).toFixed(1)+"° up"}
     Copy {visible:root.dataSet?.referenceClear===false;text:"Reference star is below the level or saved horizon. This diagram is orientation only.";color:App.Palette.warning}
     Copy {visible:root.dataSet?.nearEquator||false;text:"Near the equator, the pole is close to the horizon. This simple orientation guide is not a practical precision alignment solution.";color:App.Palette.warning}
     PoleChart {Layout.fillWidth:true;Layout.preferredHeight:300;dataSet:root.dataSet}
     Copy {text:"1. Level the mount and set its latitude scale to the pole altitude above.\n2. Aim the tracking axis towards the TRUE pole, using your mount manual.\n3. Use the reference star’s offset for orientation only, then use the manufacturer’s alignment procedure.\nThis upright sky diagram is NOT a polar-scope reticle. Optics can mirror, invert or rotate it. Saved trees/terrain can block the reference star; confirm the view outdoors."}
    }
    ColumnLayout {visible:root.section==="live"&&!!root.dataSet;Layout.fillWidth:true;spacing:10
     Flow {Layout.fillWidth:true;spacing:8
      Repeater {model:["ISS","Tiangong"];Action {required property string modelData;required property int index;text:(root.stationIndex===index?"● ":"")+modelData;onClicked:root.stationIndex=index}}
     }
     GroundMap {Layout.fillWidth:true;observer:root.dataSet?.observer||null;sample:root.station?.usable&&!root.expired?root.station:null;selected:root.station?.usable?{track:root.station.track,pass:[]}:null}
     Copy {text:!root.station?"No cached station positions.":!root.station.usable?root.station.name+" · stale / future elements: current marker withheld.":root.station.name+" · "+Number(root.station.el).toFixed(1)+"° up · "+Number(root.station.az).toFixed(1)+"° true bearing · "+root.skyModel.formatDistance(root.station.slant,0)+" slant range\n"+(root.station.el>0?"Above geometric horizon":"Below geometric horizon")+" · "+(root.station.sunlit?"station sunlit":"station in shadow")+" · "+(root.station.skyDark?"sky dark enough":"sky bright")+" · visibility unconfirmed";color:root.expired?App.Palette.warning:App.Palette.ink}
     Copy {text:root.station?"Element epoch "+root.station.epoch+" · age "+Number(root.station.ageHours).toFixed(1)+" h":"";color:App.Palette.muted}
    }
    Copy {visible:root.section==="transits"&&!!root.dataSet;text:(root.dataSet?.events?.length||0)+" close approaches / candidate crossings.\n"+(root.dataSet?.coverage||[]).join("\n");color:App.Palette.muted}
    Repeater {model:root.section==="transits"?(root.dataSet?.events||[]):[]
     Rectangle {required property var modelData;Layout.fillWidth:true;implicitHeight:card.implicitHeight+28;radius:8;color:App.Palette.surface;border.color:App.Palette.border
      ColumnLayout {id:card;anchors.fill:parent;anchors.margins:14;spacing:8
       Copy {text:modelData.station+" / "+modelData.target+" · "+modelData.status;font.bold:true;color:App.Palette.warning}
       Copy {text:"Model closest approach: "+modelData.localTime+" · "+(root.dataSet?.zone||"")+"\nUTC "+modelData.time}
       Copy {text:"Look "+modelData.az.toFixed(1)+"° true bearing · "+modelData.el.toFixed(1)+"° up\nSeparation "+modelData.separation.toFixed(4)+"° · disc radius "+modelData.radius.toFixed(4)+"°"}
       Copy {visible:modelData.disc;text:"Point-station disc duration "+(modelData.duration===null?"unresolved":modelData.duration.toFixed(3)+" s")+"\nModel ingress "+(modelData.ingress||"unresolved")+"\nModel egress "+(modelData.egress||"unresolved")}
       Copy {text:"Element epoch "+modelData.epoch+" · "+modelData.ageHours.toFixed(1)+" h at event\n"+modelData.uncertainty;color:App.Palette.muted}
      }
     }
    }
    Copy {visible:!!root.dataSet;text:root.dataSet?.basis||"";color:App.Palette.muted}
    Copy {visible:root.section==="chart"&&root.satellitesOn;text:(root.dataSet?.satellites?.basis||"")+"\n"+(root.dataSet?.satellites?.withheld||[]).map(s=>s.name+": "+s.reason).join("\n");color:App.Palette.muted}
    Copy {visible:root.section==="chart";text:"Star data: HYG v4.0, David Nash / Astronexus · adapted subset CC BY-SA 4.0. See bundled data attribution.";color:App.Palette.muted;font.pixelSize:12}
   }
  }
 }
 IpcHandler {target:"omanova-final-sky";function summary():string{return JSON.stringify({section:root.section,busy:job.running,ready:!!root.dataSet,error:root.result,stars:root.dataSet?.stars?.length,objects:root.dataSet?.objects?.length,stations:root.dataSet?.stations?.length,events:root.dataSet?.events?.length,expired:root.expired,satellitesOn:root.satellitesOn,layerCurrent:root.layerCurrent,satelliteCount:root.dataSet?.satellites?.objects?.length,markers:(root.dataSet?.satellites?.objects||[]).filter(s=>s.el>=0&&(!root.visibleOnly||s.potential)).length,selection:root.fixture?skyChart.selection:""})}
  function sampleScroll(y:int):bool {if(!root.fixture)return false;scroll.contentItem.contentY=Math.max(0,Math.min(y,scroll.contentHeight-scroll.height));return true}
  function sampleFilter(potential:bool):bool {if(!root.fixture)return false;root.visibleOnly=potential;return true}
  function sampleTime(at:string):bool {if(!root.fixture)return false;root.fixtureTime=at;return true}
  function sampleMarker():bool {if(!root.fixture)return false;let s=(root.dataSet?.satellites?.objects||[]).find(s=>s.el>=0);if(!s)return false;skyChart.selectedSatellite=s.id;return true}
  function satelliteSample(on:bool):bool {if(!root.fixture)return false;root.satellitesOn=on;instant.text="";root.request();return true}
  function search():bool {if(!root.fixture)return false;root.request();return true}
  function sampleCamera(target:string, angle:int):bool {
   if(!root.fixture||root.section!=="chart"||!root.cameras.length)return false
   root.framing=true;root.aim={target:target};root.rotateCamera(angle)
   return !!root.axes
  }
  function sampleCameraState():string {
   if(!root.fixture||!root.axes)return ""
   return JSON.stringify({angle:root.cameraAngle,centre:root.cameraCentre?.name,summary:cameraChart.summary,fit:cameraChart.targetFit,
                          footprint:skyChart.cameraFootprint})
  }
  function sampleCameraCapture():void {
   if(root.fixture&&root.axes)cameraChart.grabToImage(r=>r.saveToFile(root.skyModel.directory+"/camera-chart.png"))
  }
  function capture():void {if(root.fixture)root.grabToImage(r=>r.saveToFile(root.skyModel.directory+"/final-"+root.section+".png"))}
 }
}
