import "./qml/Omanova" as App
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
Item {
    id:root
    readonly property string state:Quickshell.env("OMANOVA_EQUIPMENT_STATE")
    readonly property string runtime:Quickshell.env("OMANOVA_EQUIPMENT_RUNTIME")
    readonly property bool deployed:Quickshell.env("OMANOVA_EQUIPMENT_DEPLOYED")==="1"
    readonly property color backgroundColour:App.Palette.background
    Component.onCompleted:if(deployed)request("tick")
    property var dataSet:null
    property string action:"tick"
    property string pending:""
    property string result:""
    function request(a,p) {
        if(helper.running)return
        action=a;pending=JSON.stringify(p||({}))+"\n";result="Updating…"
        helper.stdinEnabled=true;helper.running=true
    }
    function preference(k,v) {let p=JSON.parse(JSON.stringify(dataSet.profile));p[k]=v;request("save",p)}
    function gear(k,on) {let g=dataSet.profile.gear.filter(v=>v!==k);if(on)g.push(k);preference("gear",g)}
    function when(t) {return t?Qt.formatDateTime(new Date(t),"ddd d MMM · HH:mm")+" local":"Unknown"}
    FileView {
        id:view;path:root.state+"/view.json";watchChanges:true;printErrors:false
        onFileChanged:reload()
        onLoaded:{try{root.dataSet=JSON.parse(text())}catch(e){root.result="Preview data unavailable."}}
    }
    Process {
        id:helper
        command:[root.runtime+"/.venv/bin/python",root.runtime+"/observatory/equipment/equipment.py","--state",root.state,root.action]
        environment:({"OPENBLAS_NUM_THREADS":"1"});stdinEnabled:true
        onStarted:{write(root.pending);root.pending="";stdinEnabled=false}
        stderr:StdioCollector {id:errors}
        onExited:function(code){if(code===0)view.reload();else root.dataSet=null;root.result=code===0?root.deployed?"Equipment and sky profile saved locally.":"Saved in this preview only.":errors.text.trim()||"Update unavailable. Try selecting a data source again."}
    }
    Timer {interval:30000;repeat:true;running:!!root.dataSet&&!helper.running&&root.dataSet.source==="live";onTriggered:root.request("tick")}
        Rectangle {
            id:ui;anchors.fill:parent;color:App.Palette.background
            component Copy:Text {Layout.fillWidth:true;wrapMode:Text.Wrap;textFormat:Text.PlainText;color:App.Palette.ink;font.pixelSize:14}
            component Heading:Copy {font.pixelSize:26;font.bold:true}
            component Action:Button {
                id:b;implicitHeight:40;leftPadding:14;rightPadding:14
                contentItem:Text {text:b.text;textFormat:Text.PlainText;color:b.enabled?App.Palette.ink:App.Palette.muted;font.pixelSize:14;verticalAlignment:Text.AlignVCenter}
                background:Rectangle {radius:6;color:b.hovered?App.Palette.hover:App.Palette.button;border.color:b.activeFocus?App.Palette.accent:App.Palette.border}
            }
            component Toggle:CheckBox {
                id:t;enabled:!!root.dataSet&&!helper.running
                padding:8;spacing:9
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
                        Copy {text:root.deployed?"O M A N O V A   /   MY EQUIPMENT AND SKY":"O M A N O V A   /   SEPARATE PREVIEW";font.pixelSize:12;color:App.Palette.accent}
                        Heading {text:"My Equipment and Sky"}
                        Copy {text:"Choose what you have and the sky you expect. Suggestions explain what fits, what is uncertain and what needs a different setup.";color:App.Palette.muted}
                        Flow {
                            Layout.fillWidth:true;spacing:10;visible:!root.deployed
                            Action {text:root.dataSet?.source==="sample"?"● Public examples":"Public examples";enabled:!helper.running;onClicked:root.request("source",{source:"sample"})}
                            Action {text:root.dataSet?.source==="live"?"● Live suggestions · read-only":"Live suggestions · read-only";enabled:!helper.running;onClicked:root.request("source",{source:"live"})}
                        }
                        Copy {text:root.dataSet?.source==="live"?"READ-ONLY LIVE SNAPSHOT · Rechecks local planner data every 30 seconds. No new downloads, alerts or live setting changes.":"SIMULATED EXAMPLES · Fixed sample clock: "+root.when(root.dataSet?.clock)+". These are filter exercises, not tonight’s predictions.";color:App.Palette.warning}
                        Copy {text:"My equipment · choose one or more";font.bold:true}
                        Flow {
                            Layout.fillWidth:true;spacing:12
                            Repeater {
                                model:[{key:"eye",label:"Naked eye"},{key:"binoculars",label:"Binoculars"},{key:"telescope",label:"Telescope"},{key:"camera",label:"Camera"}]
                                Toggle {required property var modelData;text:modelData.label;checked:root.dataSet?.profile?.gear?.includes(modelData.key)||false;onClicked:root.gear(modelData.key,checked)}
                            }
                        }
                        Copy {text:"A camera means a wide-field/tripod overview. Aperture, tracking, field of view and exposure are unassessed. Telescope selection alone does not establish faint-target capability.";color:App.Palette.muted}
                        Copy {text:"My sky · manual description";font.bold:true}
                        Flow {
                            Layout.fillWidth:true;spacing:8
                            Repeater {
                                model:[{key:"unknown",label:"Not sure"},{key:"bright",label:"Bright / urban"},{key:"moderate",label:"Moderate / suburban"},{key:"dark",label:"Dark / rural"}]
                                Action {required property var modelData;text:(root.dataSet?.profile?.sky===modelData.key?"● ":"")+modelData.label;enabled:!helper.running&&!!root.dataSet;onClicked:root.preference("sky",modelData.key)}
                            }
                        }
                        Copy {text:"Your description is a planning preference, not a measured darkness rating. Cloud, Moon, glare and your horizon can still limit a sighting.";color:App.Palette.muted}
                        Flow {
                            Layout.fillWidth:true;spacing:10
                            Toggle {text:"Filter suggestions";checked:root.dataSet?.profile?.filter===true;onClicked:root.preference("filter",checked)}
                            Toggle {text:"Include uncertain matches";checked:root.dataSet?.profile?.uncertain===true;onClicked:root.preference("uncertain",checked)}
                            Toggle {text:"Inspect filtered-out entries";checked:root.dataSet?.profile?.showExcluded===true;onClicked:root.preference("showExcluded",checked)}
                        }
                        Copy {text:(root.dataSet?.counts?.shown||0)+" shown / "+(root.dataSet?.counts?.total||0)+" total · "+(root.dataSet?.counts?.eligible||0)+" eligible after profile · "+(root.dataSet?.counts?.uncertain||0)+" uncertain · "+(root.dataSet?.counts?.excluded||0)+" filtered";color:App.Palette.accent}
                        Copy {visible:root.result.length>0;text:root.result;color:App.Palette.muted}
                        Copy {visible:!!root.dataSet?.error;text:root.dataSet?.error||"";color:App.Palette.warning}
                    }
                    Repeater {
                        model:root.dataSet?.rows||[]
                        Rectangle {
                            id:card;required property var modelData
                            Layout.fillWidth:true;Layout.leftMargin:24;Layout.rightMargin:24
                            implicitHeight:body.implicitHeight+32;radius:10;color:App.Palette.surface;border.color:modelData.excluded?App.Palette.line:App.Palette.border
                            ColumnLayout {
                                id:body;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:16;spacing:8
                                Copy {text:card.modelData.kind.toUpperCase()+" · "+card.modelData.profileBadge;color:card.modelData.eligible?App.Palette.good:App.Palette.warning;font.pixelSize:12;font.bold:true}
                                Heading {text:card.modelData.name;font.pixelSize:22}
                                Copy {text:root.when(card.modelData.start)+" – "+Qt.formatDateTime(new Date(card.modelData.end),"HH:mm")+" · "+(card.modelData.look.direction||"Direction unknown")+" · "+(card.modelData.look.el===null?"altitude unknown":Math.round(card.modelData.look.el)+"° up")}
                                Copy {text:"Source visibility: "+card.modelData.visibility+" · Weather: "+card.modelData.conditions.label+" · "+(card.modelData.eligible?"Eligible after profile checks":"Inspect only / not an eligible suggestion");color:App.Palette.muted}
                                Copy {text:card.modelData.notes.join("\n");color:App.Palette.muted}
                                Copy {visible:!!card.modelData.safety;text:card.modelData.safety;color:App.Palette.warning}
                                Action {visible:!!card.modelData.source;text:card.modelData.restricted?"Read solar safety guidance":"Open source guidance";onClicked:Qt.openUrlExternally(card.modelData.source)}
                            }
                        }
                    }
                    Copy {Layout.margins:24;visible:!root.dataSet?.rows?.length;text:"No suggestions match these choices. Try another equipment choice or inspect filtered-out entries."}
                    Copy {Layout.margins:24;text:root.dataSet?.limits||"";color:App.Palette.muted}
                }
            }
        }
        IpcHandler {
            target:"omanova-equipment"
            function summary():string {return JSON.stringify({source:root.dataSet?.source,profile:root.dataSet?.profile,counts:root.dataSet?.counts,busy:helper.running,error:root.dataSet?.error})}
            function sampleProfile(value:string):void {if(root.dataSet?.source==="sample")root.request("save",JSON.parse(value))}
            function capture():void {if(root.dataSet?.source==="sample")ui.grabToImage(r=>r.saveToFile(root.state+"/sample.png"))}
        }
}
