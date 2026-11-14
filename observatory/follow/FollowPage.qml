import "./qml/Omanova" as App
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
Item {
    id:root
    readonly property color backgroundColour:App.Palette.background
    readonly property bool deployed:Quickshell.env("OMANOVA_FOLLOW_DEPLOYED")==="1"
    property string mode:deployed?"live":"sample"
    property var dataSet:null
    property string result:""
    property string pending:""
    property string operation:""
    property string requestedMode:"sample"
    property bool onlyFavourites:false
    property bool historyOnly:false
    readonly property string base:Quickshell.env("OMANOVA_FOLLOW_ROOT")
    readonly property string runtime:Quickshell.env("OMANOVA_FOLLOW_RUNTIME")
    readonly property var rows:(dataSet?.rows||[]).filter(r=>!onlyFavourites||r.favourite)
    function request(action,payload) {
        if(helper.running)return
        requestedMode=mode;operation=action;pending=JSON.stringify(payload||({}))+"\n"
        result="Updating followed launches…";helper.stdinEnabled=true;helper.running=true
    }
    function preference(key,value) {let p=JSON.parse(JSON.stringify(dataSet.prefs));p[key]=value;request("preferences",p)}
    function when(t) {return t?Qt.formatDateTime(new Date(t),"ddd d MMM · HH:mm:ss")+" local":"not checked"}
    FileView {
        id:stateFile;path:root.base+"/"+root.mode+"/view.json";watchChanges:true;printErrors:false
        onFileChanged:reload()
        onLoaded:{try{root.dataSet=JSON.parse(text())}catch(e){root.result="Preview state unavailable."}}
    }
    Process {
        id:helper
        command:[root.runtime+"/.venv/bin/python",root.runtime+"/observatory/follow/follow.py","--root",root.base,"--mode",root.requestedMode,root.operation]
        environment:({"OPENBLAS_NUM_THREADS":"1"});stdinEnabled:true
        onStarted:{write(root.pending);root.pending="";stdinEnabled=false}
        stderr:StdioCollector {id:errors}
        onExited:function(code){stateFile.reload();root.result=code===0?"Updated. Favourites saved locally.":errors.text.trim()||"Update unavailable."}
    }
    Timer {interval:60000;repeat:true;running:!helper.running&&!!root.dataSet&&(root.dataSet.prefs.downloads||root.dataSet.pending>0);onTriggered:root.request("tick")}
        Rectangle {
            id:ui;anchors.fill:parent;color:App.Palette.background
            component Copy:Text {Layout.fillWidth:true;wrapMode:Text.Wrap;textFormat:Text.PlainText;color:App.Palette.ink;font.pixelSize:14}
            component Heading:Copy {font.pixelSize:25;font.bold:true}
            component Action:Button {
                id:button;implicitHeight:38;leftPadding:12;rightPadding:12
                contentItem:Text {text:button.text;textFormat:Text.PlainText;color:button.enabled?App.Palette.ink:App.Palette.muted;font.pixelSize:14;verticalAlignment:Text.AlignVCenter}
                background:Rectangle {radius:6;color:button.hovered?App.Palette.hover:App.Palette.button;border.color:button.activeFocus?App.Palette.accent:App.Palette.border}
            }
            component Toggle:CheckBox {
                palette.windowText:App.Palette.ink;palette.text:App.Palette.ink;palette.buttonText:App.Palette.ink;palette.highlight:App.Palette.accent
                enabled:!!root.dataSet&&!helper.running
            }
            ColumnLayout {
                anchors.fill:parent;spacing:0
                ColumnLayout {
                    Layout.fillWidth:true;Layout.margins:22;spacing:8
                    Copy {text:"O M A N O V A   /   LAUNCH FOLLOWING";color:App.Palette.accent;font.pixelSize:12}
                    Heading {text:qsTr("Follow a launch")}
                    Copy {text:qsTr("Favourite missions and follow schedule changes or webcasts. These alerts do not mean a launch is visible from your location.");color:App.Palette.muted}
                    RowLayout {
                        Layout.fillWidth:true
                        ComboBox {
                            id:modeChoice;visible:!root.deployed;Layout.preferredWidth:300;Layout.minimumWidth:120;model:["Sample missions · offline","Live schedule · opt-in"]
                            enabled:!helper.running;palette.button:App.Palette.button;palette.buttonText:App.Palette.ink
                            onActivated:{root.mode=currentIndex===0?"sample":"live";root.dataSet=null;root.result="";root.historyOnly=false}
                        }
                        Toggle {text:qsTr("Favourites only");checked:root.onlyFavourites;onClicked:root.onlyFavourites=checked}
                        Copy {text:(root.dataSet?.prefs?.favourites?.length||0)+" / 5 followed";color:App.Palette.muted}
                    }
                    Flow {
                        Layout.fillWidth:true;spacing:12
                        Toggle {text:qsTr("Allow live launch downloads");enabled:root.mode==="live"&&!!root.dataSet&&!helper.running;checked:root.dataSet?.prefs?.downloads===true;onClicked:root.preference("downloads",checked)}
                        Toggle {text:qsTr("Opt into desktop alerts");checked:root.dataSet?.prefs?.alerts===true;onClicked:root.preference("alerts",checked)}
                        Toggle {text:qsTr("Delay / schedule changes");checked:root.dataSet?.prefs?.delayAlerts===true;onClicked:root.preference("delayAlerts",checked)}
                        Toggle {text:qsTr("Hold / explicit scrub or cancellation");checked:root.dataSet?.prefs?.statusAlerts===true;onClicked:root.preference("statusAlerts",checked)}
                    }
                    Action {text:root.historyOnly?qsTr("Back to launches"):qsTr("Change history (%1)").arg(root.dataSet?.history?.length||0);onClicked:{root.historyOnly=!root.historyOnly;scroll.contentItem.contentY=0}}
                    Copy {text:root.mode==="sample"?qsTr("SIMULATED MISSIONS. Favourite the Falcon 9 sample, opt into alerts, then try a change below. Webcast is a labelled sample link."):qsTr("Launch Library 2: upcoming data cached for 15 minutes; individual favourites checked at most hourly. Nine requests/hour maximum for launch following; other apps share the provider limit. Checks and alerts run while this window is open. The first fresh check after re-enabling alerts establishes a baseline.");color:App.Palette.warning}
                    Flow {
                        Layout.fillWidth:true;spacing:8;visible:root.mode==="sample"
                        Repeater {
                            model:[{label:"Original schedule",value:"original"},{label:"Delay 40 minutes",value:"delay"},{label:"Hold",value:"hold"},{label:"Explicit scrub",value:"scrub"},{label:"Cancellation",value:"cancel"},{label:"Date only",value:"coarse"},{label:"Missing from feed",value:"missing"},{label:"Provider outage",value:"outage"}]
                            Action {required property var modelData;text:modelData.label;enabled:!helper.running;onClicked:root.request("simulate",{scenario:modelData.value})}
                        }
                    }
                    RowLayout {
                        Layout.fillWidth:true
                        Action {visible:root.mode==="live";text:helper.running?qsTr("Checking…"):qsTr("Check schedule");enabled:root.dataSet?.prefs?.downloads===true&&!helper.running;onClicked:root.request("refresh")}
                        Copy {text:"Last source check: "+root.when(root.dataSet?.fetched);color:App.Palette.muted}
                    }
                    Copy {visible:root.result.length>0;text:root.result;color:App.Palette.muted}
                    Copy {visible:!!root.dataSet?.error;text:root.dataSet?.error||"";color:App.Palette.warning}
                }
                Rectangle {Layout.fillWidth:true;implicitHeight:1;color:App.Palette.line}
                ScrollView {
                    id:scroll;Layout.fillWidth:true;Layout.fillHeight:true;clip:true;contentWidth:availableWidth
                    ColumnLayout {
                        width:scroll.availableWidth;spacing:14
                        Copy {Layout.margins:20;visible:root.rows.length===0;text:root.mode==="live"&&!root.dataSet?.rows?.length?qsTr("Enable downloads and check the schedule. No observing location is requested."):qsTr("No matching launches. Favourites removed from the feed remain inspectable.")}
                        Repeater {
                            model:root.historyOnly?[]:root.rows
                            Rectangle {
                                required property var modelData
                                Layout.fillWidth:true;Layout.leftMargin:20;Layout.rightMargin:20
                                implicitHeight:card.implicitHeight+28;radius:10;color:App.Palette.surface;border.color:modelData.favourite?App.Palette.accent:App.Palette.line
                                ColumnLayout {
                                    id:card;anchors.fill:parent;anchors.margins:14;spacing:8
                                    RowLayout {
                                        Layout.fillWidth:true
                                        Heading {text:parent.parent.parent.modelData.name}
                                        Action {text:modelData.favourite?qsTr("★ Following · remove"):qsTr("☆ Favourite");enabled:!helper.running&&(modelData.favourite||(root.dataSet?.prefs?.favourites?.length||0)<5);onClicked:root.request("favourite",{id:modelData.id,on:!modelData.favourite})}
                                    }
                                    Copy {text:modelData.provider+" · "+modelData.site;color:App.Palette.muted}
                                    Copy {text:modelData.timeLabel;font.bold:true}
                                    Copy {text:modelData.status+" · "+(!modelData.available?"Missing from latest feed — status unconfirmed":modelData.fresh?"Recent source snapshot":"Cached/stale source — recheck");color:App.Palette.warning}
                                    Copy {text:qsTr("Local visibility unconfirmed. This is a schedule/webcast favourite, separate from observing alerts.");color:App.Palette.muted}
                                    RowLayout {
                                        Action {text:root.mode==="sample"?qsTr("Sample webcast link"):qsTr("Open webcast");enabled:!!modelData.stream;onClicked:Qt.openUrlExternally(modelData.stream)}
                                        Action {text:qsTr("Provider record");visible:root.mode==="live";onClicked:Qt.openUrlExternally(modelData.source)}
                                        Copy {visible:!modelData.stream;text:qsTr("No webcast supplied by the source.");color:App.Palette.muted}
                                    }
                                }
                            }
                        }
                        Heading {Layout.margins:20;text:qsTr("Change and alert history")}
                        Copy {Layout.leftMargin:20;Layout.rightMargin:20;visible:!(root.dataSet?.history?.length);text:qsTr("No changes recorded yet. Adding a favourite establishes a baseline without sending an alert.");color:App.Palette.muted}
                        Repeater {
                            model:root.dataSet?.history||[]
                            Copy {required property var modelData;Layout.leftMargin:20;Layout.rightMargin:20;text:root.when(modelData.at)+" · "+modelData.name+"\n"+modelData.messages.join("\n")+"\n"+modelData.delivery}
                        }
                        Copy {Layout.margins:20;text:qsTr("A time shift is not proof of a scrub. Holds are labelled separately; a scrub/cancellation must be explicit in the source status. Missing entries, provider errors and stale monitoring gaps do not generate scrub alerts. Monitoring stops when the Observatory closes. Launch schedule alerts have their own opt-in and are separate from local viewing alerts.");color:App.Palette.muted}
                    }
                }
            }
        }
        IpcHandler {
            target:"omanova-follow-preview"
            function summary():string {return JSON.stringify({mode:root.mode,busy:helper.running,rows:root.dataSet?.rows?.length,favourites:root.dataSet?.prefs?.favourites?.length,alerts:root.dataSet?.prefs?.alerts,downloads:root.dataSet?.prefs?.downloads,history:root.dataSet?.history?.length,error:root.dataSet?.error})}
            function sampleAction(action:string,value:string):void {
                if(root.mode!=="sample"||root.dataSet?.prefs?.alerts)return
                if(action==="favourite")root.request("favourite",{id:"421785e3-d1b4-4874-ae34-344a24fa2a01",on:value==="on"})
                else if(action==="simulate")root.request("simulate",{scenario:value})
            }
            function source(mode:string):void {if(!root.deployed&&!helper.running&&["sample","live"].includes(mode)){root.mode=mode;root.dataSet=null;modeChoice.currentIndex=mode==="sample"?0:1}}
            function capture():void {if(root.mode==="sample")ui.grabToImage(r=>r.saveToFile(root.base+"/sample.png"))}

        }
}
