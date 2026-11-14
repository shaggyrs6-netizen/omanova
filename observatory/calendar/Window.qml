import "./qml/Omanova" as App
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
ShellRoot {
    id:root
    readonly property string state:Quickshell.env("OMANOVA_CALENDAR_STATE")
    readonly property string runtime:Quickshell.env("OMANOVA_CALENDAR_RUNTIME")
    property var dataSet:null
    property var selected:[]
    property var receipt:null
    property string source:"sample"
    property string kind:"all"
    property int days:7
    property int lead:0
    property bool includeCaution:false
    property bool inspectBlocked:false
    property bool optionsOpen:false
    property string action:"refresh"
    property string pending:""
    property string result:""
    readonly property var rows:(dataSet?.rows||[]).filter(r=>(kind==="all"||r.kind===kind)&&(days===0||Date.parse(r.start)<Date.parse(dataSet.clock)+days*86400000)&&(inspectBlocked||!r.blocked))
    function selectable(r){return !r.blocked&&(!r.caution||includeCaution)}
    function choose(id,on){let ids=selected.filter(v=>v!==id);if(on&&ids.length<50)ids.push(id);selected=ids}
    function request(a){if(helper.running)return;action=a;pending=JSON.stringify({source:source,ids:selected,lead:lead,includeCaution:includeCaution})+"\n";result="Working…";helper.stdinEnabled=true;helper.running=true}
    function when(t){return Qt.formatDateTime(new Date(t),"ddd d MMM yyyy · HH:mm")+" desktop local"}
    onIncludeCautionChanged:if(!includeCaution)selected=selected.filter(id=>dataSet?.rows.some(r=>r.id===id&&!r.caution&&!r.blocked))
    FileView {
        id:view;path:root.state+"/view.json";watchChanges:true;printErrors:false
        onFileChanged:reload()
        onLoaded:{try{let d=JSON.parse(text());root.dataSet=d;root.selected=root.selected.filter(id=>d.rows.some(r=>r.id===id&&root.selectable(r)))}catch(e){root.dataSet=null;root.selected=[];root.result="Planning data unavailable."}}
    }
    FileView {id:receiptFile;path:root.state+"/receipt.json";printErrors:false;onLoaded:{try{root.receipt=JSON.parse(text())}catch(e){root.receipt=null}}}
    Process {
        id:helper
        command:[root.runtime+"/.venv/bin/python",root.runtime+"/observatory/calendar/calendar_export.py","--state",root.state,root.action]
        environment:({"OPENBLAS_NUM_THREADS":"1"});stdinEnabled:true
        onStarted:{write(root.pending);root.pending="";stdinEnabled=false}
        stderr:StdioCollector {id:errors}
        onExited:function(code){if(code===0){view.reload();if(root.action==="export")receiptFile.reload();root.result=root.action==="export"?"Saved locally. Import the .ics file into your calendar when ready.":"Local catalogue refreshed."}else{root.result=errors.text.trim()||"Export unavailable.";if(root.action!=="export"){root.dataSet=null;root.selected=[]}}}
    }
    FloatingWindow {
        title:"OMANOVA · Calendar export preview"
        color:App.Palette.background;implicitWidth:1080;implicitHeight:850;minimumSize:Qt.size(480,520)
        onVisibleChanged:if(!visible)Qt.quit()
        Rectangle {
            id:ui;anchors.fill:parent;color:App.Palette.background
            component Copy:Text {Layout.fillWidth:true;wrapMode:Text.Wrap;textFormat:Text.PlainText;color:App.Palette.ink;font.pixelSize:14}
            component Heading:Copy {font.pixelSize:25;font.bold:true}
            component Action:Button {
                id:b;implicitHeight:40;leftPadding:12;rightPadding:12
                contentItem:Text {text:b.text;textFormat:Text.PlainText;color:b.enabled?App.Palette.ink:App.Palette.muted;font.pixelSize:14;verticalAlignment:Text.AlignVCenter}
                background:Rectangle {radius:6;color:b.hovered?App.Palette.hover:App.Palette.button;border.color:b.activeFocus?App.Palette.accent:App.Palette.border}
            }
            component Toggle:CheckBox {
                id:t;enabled:!!root.dataSet&&!helper.running;padding:8;spacing:9
                contentItem:Text {text:t.text;textFormat:Text.PlainText;color:t.enabled?App.Palette.ink:App.Palette.muted;font.pixelSize:14;leftPadding:t.indicator.width+t.spacing;verticalAlignment:Text.AlignVCenter}
                indicator:Rectangle {x:t.leftPadding;y:(t.height-height)/2;implicitWidth:21;implicitHeight:21;radius:4;color:App.Palette.field;border.color:t.activeFocus?App.Palette.accent:App.Palette.border
                    Text {anchors.centerIn:parent;text:t.checked?"✓":"";color:App.Palette.accent;font.pixelSize:18}}
            }
            ScrollView {
                id:scroll;anchors.fill:parent;clip:true;contentWidth:availableWidth
                ColumnLayout {
                    width:scroll.availableWidth;spacing:14
                    ColumnLayout {
                        Layout.fillWidth:true;Layout.margins:24;spacing:10
                        Copy {text:"O M A N O V A   /   SEPARATE PREVIEW";color:App.Palette.accent;font.pixelSize:12}
                        Heading {text:"Take your observing plans with you"}
                        Copy {text:"Choose events and save an iCalendar (.ics) file. Import it into your calendar yourself. Nothing is sent to a calendar account.";color:App.Palette.muted}
                        Flow {
                            Layout.fillWidth:true;spacing:10
                            Action {text:(root.source==="sample"?"● ":"")+"Public examples";enabled:!helper.running;onClicked:{root.source="sample";root.selected=[];root.dataSet=null;root.request("refresh")}}
                            Action {text:(root.source==="live"?"● ":"")+"Live events · read-only";enabled:!helper.running;onClicked:{root.source="live";root.selected=[];root.dataSet=null;root.request("refresh")}}
                            Action {text:"Refresh list";enabled:!helper.running;onClicked:root.request("refresh")}
                        }
                        Copy {text:root.source==="sample"?"SIMULATED EXAMPLES · Fixed clock "+(root.dataSet?root.when(root.dataSet.clock):"loading")+". Exports are labelled SIMULATED.":"LIVE SNAPSHOT · Uses existing local planner data. No downloads, changes to the worker, or new alerts.";color:App.Palette.warning}
                        Copy {text:"Exported events are tentative, leave your free/busy time free, and omit your location name and coordinates. Calendar times use UTC and display in your calendar’s time zone.";color:App.Palette.muted}
                        Action {text:(root.optionsOpen?"Hide":"Show")+" filters, uncertain entries & reminders";onClicked:root.optionsOpen=!root.optionsOpen}
                        Copy {text:(root.days===0?"All available":root.days===1?"Next 24 hours":"Next "+root.days+" days")+" · "+(root.kind==="all"?"All event types":root.kind)+" · "+(root.lead===0?"No reminder":root.lead+" min reminder")+" · "+(root.includeCaution?"Uncertain entries allowed":"Uncertain entries need opt-in");color:App.Palette.muted}
                        ColumnLayout {
                            visible:root.optionsOpen;Layout.fillWidth:true;spacing:10
                        Copy {text:"Show events";font.bold:true}
                        Flow {
                            Layout.fillWidth:true;spacing:8
                            Repeater {model:[{key:1,label:"Next 24 hours"},{key:7,label:"Next 7 days"},{key:30,label:"Next 30 days"},{key:0,label:"All available"}]
                                Action {required property var modelData;text:(root.days===modelData.key?"● ":"")+modelData.label;onClicked:root.days=modelData.key}}
                        }
                        Flow {
                            Layout.fillWidth:true;spacing:8
                            Repeater {model:[{key:"all",label:"All types"},{key:"station",label:"ISS / Tiangong"},{key:"moon",label:"Moon"},{key:"meteor",label:"Meteor showers"},{key:"planet",label:"Planets"},{key:"conjunction",label:"Conjunctions"},{key:"comet",label:"Comets"},{key:"eclipse",label:"Eclipses"},{key:"satellite",label:"Satellites"},{key:"plume",label:"Launch plumes"},{key:"train",label:"Starlink trains"},{key:"aurora",label:"Aurora"}]
                                Action {required property var modelData;text:(root.kind===modelData.key?"● ":"")+modelData.label;onClicked:root.kind=modelData.key}}
                        }
                        Flow {
                            Layout.fillWidth:true;spacing:10
                            Toggle {text:"Allow uncertain / poor / safety-review entries";checked:root.includeCaution;onClicked:root.includeCaution=checked}
                            Toggle {text:"Inspect unavailable entries";checked:root.inspectBlocked;onClicked:root.inspectBlocked=checked}
                        }
                        Copy {text:"Reminders · opt-in, applied only when you import the file";font.bold:true}
                        Flow {
                            Layout.fillWidth:true;spacing:8
                            Repeater {model:[0,5,15,30,60]
                                Action {required property int modelData;text:(root.lead===modelData?"● ":"")+(modelData===0?"No reminder":modelData+" min before");onClicked:root.lead=modelData}}
                        }
                        }
                        Flow {
                            Layout.fillWidth:true;spacing:10
                            Action {text:"Select shown · max 50";enabled:!!root.dataSet&&!helper.running;onClicked:root.selected=root.rows.filter(r=>root.selectable(r)).slice(0,50).map(r=>r.id)}
                            Action {text:"Clear selection";enabled:!helper.running;onClicked:root.selected=[]}
                            Action {text:"Export selected ("+root.selected.length+")";enabled:root.selected.length>0&&!helper.running;onClicked:root.request("export")}
                        }
                        Copy {text:root.rows.length+" shown · "+(root.dataSet?.total||0)+" available · "+root.selected.length+" selected (including hidden by display filters)";color:App.Palette.accent}
                        Copy {visible:!!root.result;text:root.result;color:App.Palette.warning}
                        Copy {visible:!!root.dataSet?.error;text:root.dataSet?.error||"";color:App.Palette.warning}
                        Rectangle {
                            visible:!!root.receipt;Layout.fillWidth:true;implicitHeight:receiptBox.implicitHeight+24;radius:8;color:App.Palette.surface;border.color:App.Palette.border
                            ColumnLayout {id:receiptBox;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:12
                                Copy {text:"Last local export · "+(root.receipt?.count||0)+" events · "+(root.receipt?.source==="sample"?"SIMULATED":"live snapshot")}
                                Copy {text:root.receipt?.path||"";color:App.Palette.muted}
                                Action {text:"Open export folder";onClicked:Qt.openUrlExternally("file://"+root.state+"/exports")}
                            }
                        }
                        Copy {text:"One-off snapshot: times, weather and visibility can change. Exports do not update or cancel themselves. Re-import may create duplicates depending on your calendar. Use a separate test calendar for the simulated examples.";color:App.Palette.muted}
                    }
                    Repeater {
                        model:root.rows
                        Rectangle {
                            id:card;required property var modelData
                            Layout.fillWidth:true;Layout.leftMargin:24;Layout.rightMargin:24
                            implicitHeight:body.implicitHeight+28;radius:10;color:App.Palette.surface;border.color:root.selected.includes(modelData.id)?App.Palette.accent:App.Palette.line
                            ColumnLayout {
                                id:body;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:14;spacing:8
                                Toggle {text:card.modelData.name;checked:root.selected.includes(card.modelData.id);enabled:!helper.running&&root.selectable(card.modelData)&&(checked||root.selected.length<50);onClicked:root.choose(card.modelData.id,checked)}
                                Copy {text:card.modelData.kind.toUpperCase()+" · "+card.modelData.label+(card.modelData.blocked?" · Unavailable":"");color:card.modelData.caution||card.modelData.blocked?App.Palette.warning:App.Palette.accent}
                                Copy {text:root.when(card.modelData.start)+" – "+Qt.formatDateTime(new Date(card.modelData.end),"ddd d MMM · HH:mm")+"\nUTC: "+card.modelData.start+" – "+card.modelData.end}
                                Copy {text:card.modelData.blocked||card.modelData.notes.join("\n");color:App.Palette.muted}
                            }
                        }
                    }
                    Copy {Layout.margins:24;visible:!root.rows.length;text:"No matching events. Change the date/type filters, inspect unavailable entries or refresh the list."}
                    Copy {Layout.margins:24;text:"At most 500 catalogue entries are listed and 50 exported at once. This trial does not export Trip Planner destinations or connect/sync a calendar account.";color:App.Palette.muted}
                }
            }
        }
        IpcHandler {
            target:"omanova-calendar-preview"
            function summary():string {return JSON.stringify({source:root.source,rows:root.rows.length,selected:root.selected.length,lead:root.lead,caution:root.includeCaution,busy:helper.running,error:root.dataSet?.error,exported:root.receipt?.count})}
            function sampleReset():void {if(root.source==="sample"){root.selected=[];root.lead=0;root.includeCaution=false;root.inspectBlocked=false;root.optionsOpen=false;root.receipt=null}}
            function sampleSelect():void {if(root.source==="sample")root.selected=root.rows.filter(r=>root.selectable(r)).slice(0,50).map(r=>r.id)}
            function sampleExport():void {if(root.source==="sample"&&root.selected.length)root.request("export")}
            function capture():void {if(root.source==="sample")ui.grabToImage(r=>r.saveToFile(root.state+"/sample.png"))}
            function close():void {Qt.quit()}
        }
    }
}
