import "./qml/Omanova" as App
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
Item {
    id:root
    readonly property string state:Quickshell.env("OMANOVA_OFFLINE_STATE")
    readonly property string runtime:Quickshell.env("OMANOVA_OFFLINE_RUNTIME")
    readonly property bool deployed:Quickshell.env("OMANOVA_OFFLINE_DEPLOYED")==="1"
    readonly property color backgroundColour:App.Palette.background
    Component.onCompleted:if(deployed)request("init")
    property var dataSet:null
    property var selected:[]
    property string source:deployed?"live":"sample"
    property bool includeStale:false
    property bool libraryOpen:false
    property string action:"refresh"
    property string pending:""
    property string result:""
    readonly property bool saved:dataSet?.mode==="saved"
    function request(a,guide){if(helper.running)return;action=a;pending=JSON.stringify({source:source,night:night.text,zone:zone.text,ids:selected,includeStale:includeStale,guide:guide||""})+"\n";result="Working…";helper.stdinEnabled=true;helper.running=true}
    function selectable(r){return !r.unsupported&&(includeStale||!r.staleAtCapture&&!r.sourceIssues)}
    function choose(id,on){let a=selected.filter(v=>v!==id);if(on&&a.length<50)a.push(id);selected=a}
    function draft(source){root.source=source;root.selected=[];request("refresh")}
    FileView {
        id:view;path:root.state+"/view.json";watchChanges:true;printErrors:false
        onFileChanged:reload()
        onLoaded:{try{let d=JSON.parse(text());root.dataSet=d;root.source=d.deck.source;night.text=d.deck.night;zone.text=d.deck.zone;root.selected=root.selected.filter(id=>d.deck.rows.some(r=>r.id===id&&root.selectable(r)))}catch(e){root.dataSet=null;root.result="Guide unavailable. Saved files have been retained."}}
    }
    Process {
        id:helper;command:[root.runtime+"/.venv/bin/python",root.runtime+"/observatory/offline/offline.py","--state",root.state,root.action]
        environment:({"OPENBLAS_NUM_THREADS":"1"});stdinEnabled:true
        onStarted:{write(root.pending);root.pending="";stdinEnabled=false}
        stderr:StdioCollector {id:errors}
        onExited:function(code){if(code===0){view.reload();root.result=root.action==="save"?"Guide saved locally. Reopen it here without live data, or use the self-contained HTML copy.":root.action==="open"?"Saved file checked using this device’s clock. No live data read.":"Viewing list built from available predictions."}else{root.dataSet=null;root.selected=[];root.result=errors.text.trim()||"Could not open guide. Saved files retained."}}
    }
    Timer {interval:30000;repeat:true;running:root.saved&&!helper.running;onTriggered:root.request("open",root.dataSet.guide)}
        Rectangle {
            id:ui;anchors.fill:parent;color:App.Palette.background
            component Copy:Text {Layout.fillWidth:true;wrapMode:Text.Wrap;textFormat:Text.PlainText;color:App.Palette.ink;font.pixelSize:14}
            component Heading:Copy {font.pixelSize:25;font.bold:true}
            component Action:Button {
                id:b;implicitHeight:40;leftPadding:12;rightPadding:12
                contentItem:Text {text:b.text;textFormat:Text.PlainText;color:b.enabled?App.Palette.ink:App.Palette.muted;font.pixelSize:14;verticalAlignment:Text.AlignVCenter}
                background:Rectangle {radius:6;color:b.hovered?App.Palette.hover:App.Palette.button;border.color:b.activeFocus?App.Palette.accent:App.Palette.border}
            }
            component Field:TextField {
                id:f;color:App.Palette.ink;placeholderTextColor:App.Palette.muted;selectByMouse:true;implicitHeight:40;font.pixelSize:14
                background:Rectangle {radius:6;color:App.Palette.field;border.color:f.activeFocus?App.Palette.accent:App.Palette.border}
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
                        Copy {text:root.deployed?"O M A N O V A   /   OFFLINE OBSERVING CARDS":"O M A N O V A   /   SEPARATE PREVIEW";font.pixelSize:12;color:App.Palette.accent}
                        Heading {text:root.saved?"Your saved night guide":"A night’s viewing, ready to take with you"}
                        Copy {text:root.saved?"This is a saved snapshot. Opening it reads only your saved guide and the device clock; predictions and forecasts are not refreshed.":"Choose a night, select cards and save a guide with times, directions and equipment. Live mode uses the active location’s existing predictions.";color:App.Palette.muted}
                        Flow {
                            Layout.fillWidth:true;spacing:10
                            Action {visible:!root.deployed;text:"Public examples";enabled:!helper.running;onClicked:root.draft("sample")}
                            Action {text:root.deployed?"Build a new guide":"Live list · read-only";enabled:!helper.running;onClicked:root.draft("live")}
                            Action {text:"Saved guides ("+(root.dataSet?.saved?.length||0)+")";enabled:!helper.running;onClicked:root.libraryOpen=!root.libraryOpen}
                        }
                        ColumnLayout {
                            visible:root.libraryOpen;Layout.fillWidth:true
                            Copy {visible:!(root.dataSet?.saved?.length);text:"No saved guides yet.";color:App.Palette.muted}
                            Repeater {model:root.libraryOpen?root.dataSet?.saved||[]:[]
                                Action {required property var modelData;text:modelData.night+" · "+modelData.zone+" · "+modelData.count+" cards · "+(modelData.source==="sample"?"SIMULATED":"live snapshot")+" · "+modelData.savedAt;enabled:!helper.running;onClicked:{root.selected=[];root.libraryOpen=false;root.request("open",modelData.id)}}}
                        }
                        Copy {text:(root.source==="sample"?"SIMULATED EXAMPLES · ":"ACTIVE LOCATION SNAPSHOT · ")+(root.dataSet?.deck?.night||"")+" · "+(root.dataSet?.deck?.zone||"")+" · "+(root.saved?"Saved "+root.dataSet.deck.savedAt:"Available predictions only; not a fresh calculation for another place/date.");color:App.Palette.warning}
                        ColumnLayout {
                            visible:!root.saved;Layout.fillWidth:true;spacing:8
                            Copy {text:"Night beginning (YYYY-MM-DD) · guide time zone (IANA name)";font.bold:true}
                            Flow {Layout.fillWidth:true;spacing:10
                                Field {id:night;width:160;placeholderText:"YYYY-MM-DD";maximumLength:10;enabled:!helper.running}
                                Field {id:zone;width:245;placeholderText:"America/Chicago";maximumLength:80;enabled:!helper.running}
                                Action {text:"Build viewing list";enabled:!helper.running;onClicked:{root.selected=[];root.request("refresh")}}
                            }
                            Copy {text:"Noon to next noon in the chosen zone, including the following morning. A date/zone change does not calculate a new observing location. Only existing event windows overlapping this night are included.";color:App.Palette.muted}
                            Toggle {text:"Allow stale / incomplete records · inspect only";checked:root.includeStale;onClicked:{root.includeStale=checked;root.selected=root.selected.filter(id=>root.dataSet.deck.rows.some(r=>r.id===id&&root.selectable(r)))}}
                            Flow {Layout.fillWidth:true;spacing:10
                                Action {text:"Select available · max 50";enabled:!!root.dataSet&&!helper.running;onClicked:root.selected=root.dataSet.deck.rows.filter(r=>root.selectable(r)).slice(0,50).map(r=>r.id)}
                                Action {text:"Clear";enabled:!helper.running;onClicked:root.selected=[]}
                                Action {text:"Save night guide ("+root.selected.length+")";enabled:root.selected.length>0&&!helper.running;onClicked:root.request("save")}
                            }
                        }
                        Flow {
                            visible:root.saved;Layout.fillWidth:true;spacing:10
                            Action {text:"Open offline HTML / print";onClicked:Qt.openUrlExternally("file://"+root.dataSet.html)}
                            Action {text:"Open saved folder";onClicked:Qt.openUrlExternally("file://"+root.state+"/guides/"+root.dataSet.guide)}
                            Action {text:"Check saved ages now";enabled:!helper.running;onClicked:root.request("open",root.dataSet.guide)}
                        }
                        Copy {visible:root.saved;text:root.dataSet?.html||"";color:App.Palette.muted}
                        Copy {text:(root.dataSet?.deck?.rows?.length||0)+" cards shown · "+(root.saved?"No live lookups on reopen":"Up to 300 catalogue rows shown; 50 cards per saved guide");color:App.Palette.accent}
                        Copy {visible:!!root.result;text:root.result;color:App.Palette.muted}
                        Copy {visible:!!root.dataSet?.deck?.issues?.length;text:(root.dataSet?.deck?.issues||[]).join("\n");color:App.Palette.warning}
                        Copy {text:"Timing snapshots need rechecking within two hours or an earlier source expiry. Weather has a separate six-hour age limit. Those are maximum recheck limits, not promises that conditions stay unchanged. Horizon obstructions and Trip Planner destinations are not applied by this guide.";color:App.Palette.muted}
                    }
                    Repeater {
                        model:root.dataSet?.deck?.rows||[]
                        Rectangle {
                            id:card;required property var modelData
                            Layout.fillWidth:true;Layout.leftMargin:24;Layout.rightMargin:24
                            implicitHeight:body.implicitHeight+28;radius:10;color:App.Palette.surface;border.color:root.selected.includes(modelData.id)?App.Palette.accent:App.Palette.line
                            ColumnLayout {
                                id:body;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:14;spacing:8
                                Toggle {visible:!root.saved;text:card.modelData.name;checked:root.selected.includes(card.modelData.id);enabled:!helper.running&&root.selectable(card.modelData)&&(checked||root.selected.length<50);onClicked:root.choose(card.modelData.id,checked)}
                                Heading {visible:root.saved;text:card.modelData.name;font.pixelSize:22}
                                Copy {text:card.modelData.kind.toUpperCase()+" · "+card.modelData.visibility+" · "+(card.modelData.solar?"Safety review required":"Visibility not guaranteed");color:App.Palette.warning;font.bold:true}
                                Copy {text:card.modelData.status;color:App.Palette.warning}
                                Copy {text:card.modelData.when+"\nUTC: "+card.modelData.segmentStart+" — "+card.modelData.segmentEnd+"\n"+card.modelData.directionText;font.bold:true}
                                Copy {visible:!!card.modelData.segmentNote;text:card.modelData.segmentNote;color:App.Palette.muted}
                                Copy {text:"Equipment: "+(card.modelData.equipment.join(", ")||"Capability unknown / review required")+"\n"+card.modelData.equipmentNote;color:App.Palette.muted}
                                Copy {text:"Weather at capture: "+card.modelData.conditions.label+" · "+card.modelData.weatherStatus+"\nForecast fetched: "+(card.modelData.conditions.fetched||"unknown")+" · expires: "+(card.modelData.weatherExpires||"unknown");color:App.Palette.muted}
                                Copy {text:"Source checked: "+(card.modelData.sourceGenerated||"unknown")+" · recheck by: "+card.modelData.recheckAt;color:App.Palette.muted}
                                Copy {text:card.modelData.unsupported||card.modelData.reason;color:App.Palette.muted}
                                Copy {visible:!!card.modelData.safety;text:card.modelData.safety;color:App.Palette.warning}
                            }
                        }
                    }
                    Copy {Layout.margins:24;visible:!root.dataSet?.deck?.rows?.length;text:"No events available for this night. Try a night covered by the current catalogue; offline mode cannot invent missing predictions."}
                }
            }
        }
        IpcHandler {
            target:"omanova-offline"
            function summary():string {return JSON.stringify({mode:root.dataSet?.mode,source:root.source,cards:root.dataSet?.deck?.rows?.length,selected:root.selected.length,saved:root.dataSet?.saved?.length,busy:helper.running,error:root.result})}
            function sampleSelect():void {if(root.source==="sample"&&!root.saved)root.selected=root.dataSet.deck.rows.filter(r=>root.selectable(r)).slice(0,50).map(r=>r.id)}
            function sampleSave():void {if(root.source==="sample"&&!root.saved&&root.selected.length)root.request("save")}
            function sampleOpen(guide:string):void {if(root.source==="sample")root.request("open",guide)}
            function capture():void {if(root.source==="sample")ui.grabToImage(r=>r.saveToFile(root.state+"/sample.png"))}
        }
}
