import "../../qml/Omanova" as App
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
Item {
 id:root
 signal addToNight(string key)
 signal openEquipment()
 property string framingId:""
 property bool canAddToNight:false
 property var skyModel:null
 readonly property bool useMiles:skyModel?skyModel.useMiles:Quickshell.env("OMANOVA_DISTANCE_MI")==="1"
 property string section:"sites"
 property string source:"active"
 property var dataSet:null
 property string result:""
 property string pending:""
 property bool nearby:true
 property bool detailsOpen:false
 property int pageNumber:0
 property bool instrumentsOpen:false
 property bool instrumentsLoaded:false
 function showInstruments() {
  instrumentsLoaded=true
  instrumentsOpen=true
  Qt.callLater(() => {
   if (instrumentsOpen) scroll.contentItem.contentY=instruments.y
  })
 }
 property var instrumentTarget:null
 property string handoffRequest:""
 property string handoffResult:""
 property string handoffTarget:""
 function openStellarium(key) {
  if (handoff.running) return
  handoffTarget=key
  if (Quickshell.env("OMASKY_FIXTURE")==="1") {
   handoffResult="Sample only · would centre Stellarium on "+key+"."
   return
  }
  handoffRequest=JSON.stringify({action:"stellarium",target:key})+"\n"
  handoffResult="Contacting local Stellarium…"
  handoff.stdinEnabled=true
  handoff.running=true
 }
 readonly property int pageSize:12
 function finderMatches(row,query) {
  const term=query.trim().toLowerCase().replace(/’/g,"'").replace(/\s+/g," ")
  if(!term)return true
  const designation=term.match(/^(m|messier|ngc|ic)\s*0*(\d+)$/)
  if(designation) {
   const prefix=designation[1]==="messier"?"M":designation[1].toUpperCase()
   return row.id===prefix+designation[2] || row.name.toUpperCase().includes(prefix+" "+designation[2]+" ·")
  }
  return [row.id,row.name,row.type,row.constellation||""].some(value=>value.toLowerCase().replace(/’/g,"'").includes(term))
 }
 readonly property var shownRows:(dataSet?.rows||[]).filter(row=>section==="sites" ? !nearby||row.distanceKm<=500 : finderMatches(row,search.text))

 readonly property var pageRows:section==="sites"?shownRows:shownRows.slice(pageNumber*pageSize,(pageNumber+1)*pageSize)

 property double clock:Date.now()
 readonly property string state:Quickshell.env("OMANOVA_FIELD_STATE")
 readonly property string runtime:Quickshell.env("OMANOVA_FIELD_RUNTIME")
 readonly property bool old:!!dataSet&&(clock-Date.parse(dataSet.generated)>7200000||clock<Date.parse(dataSet.generated))
 function request(){if(job.running)return;pageNumber=0;pending=JSON.stringify({source:source,night:night.text})+"\n";dataSet=null;result="Calculating locally…";job.stdinEnabled=true;job.running=true}
 Component.onCompleted:request()
 Timer {interval:30000;repeat:true;running:true;onTriggered:root.clock=Date.now()}
 FileView {id:file;path:root.state+"/"+root.section+".json";printErrors:false;onLoaded:{try{root.clock=Date.now();root.dataSet=JSON.parse(text());if(root.dataSet.night)night.text=root.dataSet.night}catch(e){root.result="Could not read field results."}}}
 Process {id:job;command:[root.runtime+"/.venv/bin/python",root.runtime+"/observatory/field/field.py","--state",root.state].concat(Quickshell.env("OMASKY_FIXTURE")==="1"?["--fixture"]:[]).concat([root.section]);environment:({"OPENBLAS_NUM_THREADS":"1"});stdinEnabled:true
  onStarted:{write(root.pending);root.pending="";stdinEnabled=false}
  stderr:StdioCollector {id:errors}
  onExited:function(code){if(code===0){file.reload();root.result="Updated locally. No coordinates sent or data downloaded."}else root.result=errors.text.trim()||"Field results unavailable."}
 }
 Process {
  id:handoff
  command:[root.runtime+"/.venv/bin/python",root.runtime+"/observatory/field/instruments.py"]
  onStarted:{write(root.handoffRequest);root.handoffRequest="";stdinEnabled=false}
  stdout:StdioCollector {id:handoffOutput}
  onExited:function(code) {
   try {root.handoffResult=code===0 ? JSON.parse(handoffOutput.text).message : "Stellarium handoff failed."}
   catch (error) {root.handoffResult="Stellarium handoff failed."}
  }
 }
 component Copy:Text {Layout.fillWidth:true;wrapMode:Text.Wrap;textFormat:Text.PlainText;color:App.Palette.ink;font.pixelSize:14}
 component Action:Button {id:b;implicitHeight:40;leftPadding:12;rightPadding:12;enabled:!job.running
  contentItem:Text {text:b.text;textFormat:Text.PlainText;color:b.enabled?App.Palette.ink:App.Palette.muted;font.pixelSize:14;verticalAlignment:Text.AlignVCenter}
  background:Rectangle {radius:6;color:b.hovered?App.Palette.hover:App.Palette.button;border.color:b.activeFocus?App.Palette.accent:App.Palette.border}
 }
 ScrollView {id:scroll;anchors.fill:parent;clip:true;contentWidth:availableWidth
  ColumnLayout {width:scroll.availableWidth;spacing:14
   App.InstrumentCard {Layout.fillWidth:true;Layout.margins:18;spacing:10
    App.PageHeader {eyebrow:root.section==="sites"?"PLAN":"SKY";title:root.section==="sites"?"Destination Sites":"Sky Finder"}
    Copy {text:root.section==="sites"?"A curated starting list near your active or Trip Planner location. Distance is straight-line, not driving distance or permission to access the site.":"Find clusters, nebulae, galaxies and constellation landmarks. The finder uses your saved horizon to estimate viewing windows. Brightness and weather stay unconfirmed.";color:App.Palette.muted}
    Flow {Layout.fillWidth:true;spacing:10
     Repeater {model:[{key:"active",label:"Active location"},{key:"trip-home",label:"Trip Home"},{key:"trip-destination",label:"Trip destination"}]
      Action {required property var modelData;text:(root.source===modelData.key?"● ":"")+modelData.label;onClicked:{root.instrumentTarget=null;root.source=modelData.key;night.text="";root.request()}}}
     Action {visible:root.section==="sites";text:root.nearby?"Within 500 km · show all":"All curated sites · show within 500 km";onClicked:root.nearby=!root.nearby}
    }
    Flow {visible:root.section==="finder";Layout.fillWidth:true;spacing:10
     TextField {id:night;width:170;implicitHeight:40;placeholderText:"YYYY-MM-DD";maximumLength:10;color:App.Palette.ink;placeholderTextColor:App.Palette.muted;selectByMouse:true;enabled:!job.running;background:Rectangle {radius:6;color:App.Palette.field;border.color:App.Palette.border}}
     Action {text:"Calculate this night locally";onClicked:root.request()}
    }
    Flow {visible:root.section==="finder";Layout.fillWidth:true;spacing:10
     TextField {
      id:search;onTextChanged:root.pageNumber=0;width:Math.min(330,scroll.availableWidth-62);implicitHeight:40;maximumLength:80
      placeholderText:"Search name, M / NGC / IC number, or constellation"
      Accessible.name:"Search Sky Finder targets"
      color:App.Palette.ink;placeholderTextColor:App.Palette.muted;selectByMouse:true
      background:Rectangle {radius:6;color:App.Palette.field;border.color:search.activeFocus?App.Palette.accent:App.Palette.border}
     }
     Action {visible:search.text.length>0;text:"Clear search";onClicked:{search.clear();search.forceActiveFocus()}}
    }
    Copy {visible:root.section==="finder"&&!!root.dataSet
     text:!root.dataSet ? "" : search.text.trim()?root.shownRows.length+" of "+root.dataSet.rows.length+" matches":
          root.dataSet.rows.filter(r=>r.kind==="deep-sky").length+" deep-sky targets · "+root.dataSet.rows.filter(r=>r.kind==="landmark").length+" landmarks"
     color:App.Palette.accent}
    Copy {visible:root.section==="finder"&&!!root.dataSet&&!root.shownRows.length;text:"No matches. Try Beehive, M44, NGC 7000 or IC 5070.";color:App.Palette.muted}
    Copy {visible:root.section==="finder"&&!!root.dataSet;text:(root.dataSet?.zone||"")+" · "+(root.dataSet?.night||"")+" · "+(root.dataSet?.darkness?.darkHours||0)+" h astronomical darkness · "+(root.dataSet?.darkness?.moonFreeHours||0)+" h Moon-free darkness";color:App.Palette.accent}
    Action {visible:!!root.dataSet;text:root.detailsOpen?"Hide estimate details":"How this is estimated";onClicked:root.detailsOpen=!root.detailsOpen}
    Copy {visible:root.detailsOpen&&root.section==="finder";text:root.dataSet?.darkness?.basis||"Darkness estimates use Sun/Moon geometry; background sky quality remains unknown.";color:App.Palette.muted}
    Copy {visible:root.old;text:"These results are old or future-dated. Recalculate before relying on them.";color:App.Palette.warning;font.bold:true}
    Action {visible:root.section==="finder";text:root.instrumentsOpen?"Hide observing instruments":"Observing instruments";onClicked:{if(root.instrumentsOpen)root.instrumentsOpen=false;else root.showInstruments()}}
    Copy {text:root.result;color:App.Palette.muted}
    Copy {visible:root.detailsOpen;text:root.dataSet?.limits||"";color:App.Palette.muted}
   }
   Loader {
    id: instruments
    active: root.instrumentsLoaded && root.section==="finder"
    visible: root.instrumentsOpen
    Layout.fillWidth:true; Layout.leftMargin:18; Layout.rightMargin:18
    sourceComponent: InstrumentTools {
     runtime:root.runtime; siteSource:root.source
     sample:Quickshell.env("OMASKY_FIXTURE")==="1"
     targetId:root.instrumentTarget?.id||"";targetName:root.instrumentTarget?.name||""
    }
   }
   RowLayout {
    visible:root.section==="finder"&&root.shownRows.length>root.pageSize
    Layout.leftMargin:18
    Action {text:"Previous targets";enabled:!job.running&&root.pageNumber>0;onClicked:{root.framingId="";root.pageNumber--}}
    Copy {text:(root.pageNumber+1)+" / "+Math.ceil(root.shownRows.length/root.pageSize);Layout.fillWidth:false}
    Action {text:"Next targets";enabled:!job.running&&(root.pageNumber+1)*root.pageSize<root.shownRows.length;onClicked:{root.framingId="";root.pageNumber++}}
   }
   GridLayout {
    Layout.fillWidth:true;Layout.leftMargin:18;Layout.rightMargin:18
    columns:width>=920 && !root.framingId?2:1;rowSpacing:12;columnSpacing:12
   Repeater {id:cards;model:root.pageRows
    App.ViewPanel {appearance:"mission";id:card;required property var modelData;readonly property var framing:overlay.item;Layout.fillWidth:true;Layout.preferredWidth:1;Layout.minimumWidth:0;Layout.alignment:Qt.AlignTop;implicitHeight:body.implicitHeight+28;border.color:App.Palette.line
     ColumnLayout {id:body;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:14;spacing:8
      Copy {text:card.modelData.name;font.pixelSize:22;font.bold:true}
      Copy {visible:root.section==="sites";text:(card.modelData.area||"")+" · "+(root.useMiles?((card.modelData.distanceKm||0)/1.609344).toFixed(0)+" mi":(card.modelData.distanceKm||0).toFixed(0)+" km")+" straight-line";color:App.Palette.accent}
      Copy {visible:root.section==="sites";text:card.modelData.darkness||""}
      Copy {visible:root.section==="sites";text:card.modelData.access||"";color:App.Palette.warning}
      Copy {visible:root.section==="sites";text:"Evidence checked: "+(card.modelData.checked||"")+(card.modelData.evidenceOld?" · older than 90 days; recheck":" · recheck access before travelling");color:App.Palette.muted}
      Action {visible:root.section==="sites";text:"Official site/access guidance";onClicked:Qt.openUrlExternally(card.modelData.source)}
      Copy {visible:root.section==="finder";text:[card.modelData.type,card.modelData.constellation,card.modelData.status].filter(Boolean).join(" · ");color:App.Palette.warning}
      Copy {visible:root.section==="finder";text:card.modelData.hint||"";color:App.Palette.muted}
      Action {visible:root.section==="finder"&&root.canAddToNight;text:"Add to My Night";Accessible.name:"Add "+card.modelData.name+" to My Night";onClicked:root.addToNight(card.modelData.id)}
      Action {
       visible:root.section==="finder"&&root.canAddToNight&&!!card.modelData.extent
       text:root.framingId===card.modelData.id?"Hide field-of-view overlay":"Show field-of-view overlay"
       onClicked:root.framingId=root.framingId===card.modelData.id?"":card.modelData.id
      }
      Action {
       visible:root.section==="finder"&&root.instrumentsOpen&&root.source==="active"&&card.modelData.kind==="deep-sky"&&Quickshell.env("OMASKY_FIXTURE")!=="1"
       text:root.instrumentTarget?.id===card.modelData.id?"Selected for Go To":"Select for Go To"
       onClicked:{root.instrumentTarget=card.modelData;root.showInstruments()}
      }
      Action {
       visible:root.section==="finder"&&/^M[0-9]+$/.test(card.modelData.id)
       text:"Open in Stellarium"
       Accessible.name:"Open "+card.modelData.id+" in Stellarium"
       enabled:!handoff.running
       onClicked:root.openStellarium(card.modelData.id)
      }
      Copy {
       visible:root.handoffTarget===card.modelData.id&&!!root.handoffResult
       text:root.handoffResult;color:App.Palette.accent
      }
      Loader {
       id:overlay
       Layout.fillWidth:true;visible:root.framingId===card.modelData.id;active:visible
       sourceComponent:Component {
        App.FieldOfView {
         skyModel:root.skyModel
         extentDeg:card.modelData.extent
         onOpenEquipment:root.openEquipment()
        }
       }
      }
      Repeater {model:root.section==="finder"?card.modelData.windows||[]:[]
       ColumnLayout {required property var modelData;Layout.fillWidth:true;spacing:6
        Copy {text:(root.clock>Date.parse(modelData.event.end)?"Ended window · ":"")+(modelData.when||modelData.event.start+" — "+modelData.event.end);font.bold:true}
        Copy {text:"Look "+modelData.event.look.direction+" · "+modelData.event.look.az+"° azimuth · "+modelData.event.look.el+"° up · "+(modelData.lookWhen||modelData.event.look.time)}
        Canvas {id:compass;property var aim:parent.modelData.event.look;Layout.preferredWidth:210;Layout.preferredHeight:145
         onAimChanged:requestPaint();onWidthChanged:requestPaint();onHeightChanged:requestPaint()
         onPaint:{let c=getContext("2d"),x=width/2,y=height/2,r=height/2-18;c.reset();c.strokeStyle=App.Palette.border;c.lineWidth=1;c.beginPath();c.arc(x,y,r,0,Math.PI*2);c.stroke();c.fillStyle=App.Palette.muted;c.font="12px sans-serif";c.fillText("N",x-4,y-r-4);c.fillText("S",x-4,y+r+13);c.fillText("E",x+r+6,y+4);c.fillText("W",x-r-16,y+4);let angle=aim.az*Math.PI/180,rr=r*(90-aim.el)/90;c.fillStyle=App.Palette.accent;c.beginPath();c.arc(x+rr*Math.sin(angle),y-rr*Math.cos(angle),5,0,Math.PI*2);c.fill()}
         Connections {target:App.Palette;function onObservingModeChanged(){compass.requestPaint()}}
        }
        Copy {text:"Single-target compass at that suggested time; not a simultaneous whole-sky map. Moon "+modelData.moonAltitude+"° up · "+modelData.moonPercent+"% illuminated.";color:App.Palette.muted}
        Copy {text:modelData.equipment.join("\n")+(modelData.profileExcluded?"\nExcluded by current Equipment and Sky preferences · inspect only":"");color:modelData.profileExcluded?App.Palette.warning:App.Palette.muted}
       }
      }
     }
    }
   }
   }
   Copy {Layout.margins:24;visible:root.section==="sites"&&!!root.dataSet&&!(root.dataSet.rows||[]).some(r=>!root.nearby||r.distanceKm<=500);text:"No curated sites within this range. Show all examples or use official local park guidance; absence is not a claim that no dark sites exist.";color:App.Palette.warning}
  }
 }
 IpcHandler {
  target: "omanova-field-"+root.section
  function summary():string {
   return JSON.stringify({section:root.section,source:root.source,rows:root.dataSet?.rows?.length,
    matches:root.shownRows.length,busy:job.running,old:root.old,message:root.result})
  }
  function sampleSearch(query:string):string {
   if(root.section!=="finder"||Quickshell.env("OMASKY_FIXTURE")!=="1")return ""
   search.text=query
   return JSON.stringify(root.shownRows.map(row=>row.id))
  }
  function sampleFraming(key:string):bool {
   if(Quickshell.env("OMASKY_FIXTURE")!=="1"||!root.shownRows.some(row=>row.id===key&&row.extent))return false
   root.framingId=key
   return true
  }
  function sampleFramingState():string {
   if(Quickshell.env("OMASKY_FIXTURE")!=="1")return ""
   const panel=cards.itemAt(root.pageRows.findIndex(row=>row.id===root.framingId))?.framing
   return panel ? JSON.stringify(Object.assign({}, panel.comparison, {field:panel.fieldDeg, setup:panel.activeName, width:panel.activeSetup?.widthDeg, height:panel.activeSetup?.heightDeg})) : ""
  }
  function sampleSelectSetup(name:string):bool {
   if(Quickshell.env("OMASKY_FIXTURE")!=="1")return false
   const panel=cards.itemAt(root.pageRows.findIndex(row=>row.id===root.framingId))?.framing
   return panel?.selectSetup(name || null) ?? false
  }
  function sampleCaptureFraming():void {
   if(Quickshell.env("OMASKY_FIXTURE")!=="1")return
   cards.itemAt(root.pageRows.findIndex(row=>row.id===root.framingId))?.framing?.grabToImage(r=>r.saveToFile(root.state+"/framing.png"))
  }
  function sampleAdd(key:string):bool {
   if(Quickshell.env("OMASKY_FIXTURE")!=="1"||!root.canAddToNight||job.running||
      !root.shownRows.some(row=>row.id===key))return false
   root.addToNight(key)
   return true
  }
 }
}
