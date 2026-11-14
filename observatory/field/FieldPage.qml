import "./qml/Omanova" as App
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
Item {
 id:root
 property string section:"sites"
 property string source:"active"
 property var dataSet:null
 property string result:""
 property string pending:""
 property bool nearby:true
 property double clock:Date.now()
 readonly property string state:Quickshell.env("OMANOVA_FIELD_STATE")
 readonly property string runtime:Quickshell.env("OMANOVA_FIELD_RUNTIME")
 readonly property bool old:!!dataSet&&(clock-Date.parse(dataSet.generated)>7200000||clock<Date.parse(dataSet.generated))
 function request(){if(job.running)return;pending=JSON.stringify({source:source,night:night.text})+"\n";dataSet=null;result="Calculating locally…";job.stdinEnabled=true;job.running=true}
 Component.onCompleted:request()
 Timer {interval:30000;repeat:true;running:true;onTriggered:root.clock=Date.now()}
 FileView {id:file;path:root.state+"/"+root.section+".json";printErrors:false;onLoaded:{try{root.clock=Date.now();root.dataSet=JSON.parse(text());if(root.dataSet.night)night.text=root.dataSet.night}catch(e){root.result="Could not read field results."}}}
 Process {id:job;command:[root.runtime+"/.venv/bin/python",root.runtime+"/observatory/field/field.py","--state",root.state].concat(Quickshell.env("OMASKY_FIXTURE")==="1"?["--fixture"]:[]).concat([root.section]);environment:({"OPENBLAS_NUM_THREADS":"1"});stdinEnabled:true
  onStarted:{write(root.pending);root.pending="";stdinEnabled=false}
  stderr:StdioCollector {id:errors}
  onExited:function(code){if(code===0){file.reload();root.result="Updated locally. No coordinates sent or data downloaded."}else root.result=errors.text.trim()||"Field results unavailable."}
 }
 component Copy:Text {Layout.fillWidth:true;wrapMode:Text.Wrap;textFormat:Text.PlainText;color:App.Palette.ink;font.pixelSize:14}
 component Action:Button {id:b;implicitHeight:40;leftPadding:12;rightPadding:12;enabled:!job.running
  contentItem:Text {text:b.text;textFormat:Text.PlainText;color:b.enabled?App.Palette.ink:App.Palette.muted;font.pixelSize:14;verticalAlignment:Text.AlignVCenter}
  background:Rectangle {radius:6;color:b.hovered?App.Palette.hover:App.Palette.button;border.color:b.activeFocus?App.Palette.accent:App.Palette.border}
 }
 ScrollView {id:scroll;anchors.fill:parent;clip:true;contentWidth:availableWidth
  ColumnLayout {width:scroll.availableWidth;spacing:14
   ColumnLayout {Layout.fillWidth:true;Layout.margins:24;spacing:10
    Copy {text:"O M A N O V A   /   FIELD TOOLS";color:App.Palette.accent;font.pixelSize:12}
    Copy {text:root.section==="sites"?"Destination dark-sky sites":"Small sky finder";font.pixelSize:28;font.bold:true}
    Copy {text:root.section==="sites"?"A curated starting list near your active or Trip Planner location. Distance is straight-line, not driving distance or permission to access the site.":"Constellation landmarks and a starter set of clusters, nebulae and a galaxy. Local geometry with saved obstructions; brightness and weather stay unconfirmed.";color:App.Palette.muted}
    Flow {Layout.fillWidth:true;spacing:10
     Repeater {model:[{key:"active",label:"Active location"},{key:"trip-home",label:"Trip Home"},{key:"trip-destination",label:"Trip destination"}]
      Action {required property var modelData;text:(root.source===modelData.key?"● ":"")+modelData.label;onClicked:{root.source=modelData.key;night.text="";root.request()}}}
     Action {visible:root.section==="sites";text:root.nearby?"Within 500 km · show all":"All curated sites · show within 500 km";onClicked:root.nearby=!root.nearby}
    }
    Flow {visible:root.section==="finder";Layout.fillWidth:true;spacing:10
     TextField {id:night;width:170;implicitHeight:40;placeholderText:"YYYY-MM-DD";maximumLength:10;color:App.Palette.ink;placeholderTextColor:App.Palette.muted;selectByMouse:true;enabled:!job.running;background:Rectangle {radius:6;color:App.Palette.field;border.color:App.Palette.border}}
     Action {text:"Calculate this night locally";onClicked:root.request()}
    }
    Copy {visible:root.section==="finder"&&!!root.dataSet;text:(root.dataSet?.zone||"")+" · "+(root.dataSet?.night||"")+" · "+(root.dataSet?.darkness?.darkHours||0)+" h astronomical darkness · "+(root.dataSet?.darkness?.moonFreeHours||0)+" h Moon-free darkness";color:App.Palette.accent}
    Copy {visible:root.section==="finder";text:root.dataSet?.darkness?.basis||"Darkness estimates use Sun/Moon geometry; background sky quality remains unknown.";color:App.Palette.muted}
    Copy {visible:root.old;text:"These results are old or future-dated. Recalculate before relying on them.";color:App.Palette.warning;font.bold:true}
    Copy {text:root.result;color:App.Palette.muted}
    Copy {text:root.dataSet?.limits||"";color:App.Palette.muted}
   }
   Repeater {model:root.section==="sites"?(root.dataSet?.rows||[]).filter(r=>!root.nearby||r.distanceKm<=500):root.dataSet?.rows||[]
    Rectangle {id:card;required property var modelData;Layout.fillWidth:true;Layout.leftMargin:24;Layout.rightMargin:24;implicitHeight:body.implicitHeight+28;radius:10;color:App.Palette.surface;border.color:App.Palette.line
     ColumnLayout {id:body;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:14;spacing:8
      Copy {text:card.modelData.name;font.pixelSize:22;font.bold:true}
      Copy {visible:root.section==="sites";text:(card.modelData.area||"")+" · "+(Quickshell.env("OMANOVA_DISTANCE_MI")==="1"?((card.modelData.distanceKm||0)/1.609344).toFixed(0)+" mi":(card.modelData.distanceKm||0).toFixed(0)+" km")+" straight-line";color:App.Palette.accent}
      Copy {visible:root.section==="sites";text:card.modelData.darkness||""}
      Copy {visible:root.section==="sites";text:card.modelData.access||"";color:App.Palette.warning}
      Copy {visible:root.section==="sites";text:"Evidence checked: "+(card.modelData.checked||"")+(card.modelData.evidenceOld?" · older than 90 days; recheck":" · recheck access before travelling");color:App.Palette.muted}
      Action {visible:root.section==="sites";text:"Official site/access guidance";onClicked:Qt.openUrlExternally(card.modelData.source)}
      Copy {visible:root.section==="finder";text:(card.modelData.type||"")+" · "+(card.modelData.status||"");color:App.Palette.warning}
      Copy {visible:root.section==="finder";text:card.modelData.hint||"";color:App.Palette.muted}
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
        Copy {text:modelData.equipment.join("\n")+"\n"+modelData.framing+(modelData.profileExcluded?"\nExcluded by current Equipment and Sky preferences · inspect only":"");color:modelData.profileExcluded?App.Palette.warning:App.Palette.muted}
       }
      }
     }
    }
   }
   Copy {Layout.margins:24;visible:root.section==="sites"&&!!root.dataSet&&!(root.dataSet.rows||[]).some(r=>!root.nearby||r.distanceKm<=500);text:"No curated sites within this range. Show all examples or use official local park guidance; absence is not a claim that no dark sites exist.";color:App.Palette.warning}
  }
 }
 IpcHandler {target:"omanova-field-"+root.section;function summary():string{return JSON.stringify({section:root.section,source:root.source,rows:root.dataSet?.rows?.length,busy:job.running,old:root.old,message:root.result})}}
}
