import "./qml/Omanova" as App
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
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
 readonly property bool fixture: skyModel.fixture
 readonly property string runtime: skyModel.runtime
 readonly property var station: dataSet?.stations?.[stationIndex] || null
 readonly property bool expired: !!dataSet && !fixture && (clock<Date.parse(dataSet.generated)||clock-Date.parse(dataSet.generated)>(section==="live"?30000:section==="transits"?300000:3600000))
 readonly property string title: ({chart:"Star Chart",live:"Live Orbit",polar:"Polar Alignment",transits:"Station Transits"})[section]
 function request() {
  if(job.running)return
  pending=JSON.stringify({kind:section,source:source,time:instant.text})+"\n"
  if(section!=="live")dataSet=null
  result="Calculating locally…";job.stdinEnabled=true;job.running=true
 }
 Component.onCompleted: if(section!=="transits")request()
 onSectionChanged: {dataSet=null;instant.text="";if(section!=="transits")request()}
 Timer {interval:1000;running:true;repeat:true;onTriggered:root.clock=Date.now()}
 Timer {interval:10000;running:root.section==="live";repeat:true;onTriggered:root.request()}
 Process {
  id:job
  command:[root.runtime+"/.venv/bin/python",root.runtime+"/observatory/final_sky/geometry.py","--state",root.skyModel.directory].concat(root.fixture?["--fixture"]:[])
  environment:({"OPENBLAS_NUM_THREADS":"1"});stdinEnabled:true
  onStarted:{write(root.pending);root.pending="";stdinEnabled=false}
  stdout:StdioCollector {id:output}
  stderr:StdioCollector {id:errors}
  onExited:function(code) {
   if(code===0) {try{let d=JSON.parse(output.text);if(d.kind===root.section&&d.source===root.source){root.dataSet=d;root.result="Local calculation · no downloads"}else if(root.section!=="transits")Qt.callLater(root.request)}catch(e){root.dataSet=null;root.result="Could not read sky calculation."}}
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
     TripField {id:instant;visible:root.section==="chart"||root.section==="polar";width:250;maximumLength:32;placeholderText:"UTC: 2026-11-15T02:00Z";Accessible.name:"Chart or pole time, ISO date with timezone";enabled:!job.running}
     Action {text:root.section==="transits"?"Search next 24 hours locally":"Refresh locally";onClicked:root.request()}
     Action {visible:root.section==="chart"||root.section==="polar";text:"Use current time";onClicked:{instant.text="";root.request()}}
    }
    Copy {text:root.result;color:App.Palette.muted}
    Copy {visible:!!root.dataSet;text:(root.fixture?"DEMONSTRATION · ":"")+(root.dataSet?.place||"")+" · "+(root.dataSet?.localTime||"")+" · "+(root.dataSet?.zone||"")+"\nUTC "+(root.dataSet?.time||"");color:App.Palette.accent}
    Copy {visible:root.expired;text:"Old calculation / clock changed · refresh before using. Positions and candidates below are inspect-only.";color:App.Palette.warning;font.bold:true}
    SkyChart {Layout.fillWidth:true;Layout.preferredHeight:Math.min(520,width);visible:root.section==="chart"&&!!root.dataSet;dataSet:root.dataSet}
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
    Copy {visible:root.section==="chart";text:"Star data: HYG v4.0, David Nash / Astronexus · adapted subset CC BY-SA 4.0. See bundled data attribution.";color:App.Palette.muted;font.pixelSize:12}
   }
  }
 }
 IpcHandler {target:"omanova-final-sky";function summary():string{return JSON.stringify({section:root.section,busy:job.running,ready:!!root.dataSet,error:root.result,stars:root.dataSet?.stars?.length,objects:root.dataSet?.objects?.length,stations:root.dataSet?.stations?.length,events:root.dataSet?.events?.length,expired:root.expired})}
  function search():bool {if(!root.fixture)return false;root.request();return true}
  function capture():void {if(root.fixture)root.grabToImage(r=>r.saveToFile(root.skyModel.directory+"/final-"+root.section+".png"))}
 }
}
