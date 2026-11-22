import "./qml/Omanova" as App
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
Rectangle {
 id:root
 required property var sky
 property bool draftBlocked:false
 property var result:null
 property string action:"status"
 property bool accepted:false
 property bool notesOpen:false
 readonly property bool busy:job.running||result?.status==="running"
 implicitHeight:body.implicitHeight+32
 color:App.Palette.surface;radius:10;border.color:App.Palette.line
 function run(operation) {if(job.running)return;action=operation;job.running=true}
 Component.onCompleted:run("status")
 component Copy:Text {Layout.fillWidth:true;textFormat:Text.PlainText;color:App.Palette.ink;font.pixelSize:14;wrapMode:Text.Wrap}
 component Action:Button {id:b;implicitHeight:39;leftPadding:12;rightPadding:12;enabled:!root.busy
  contentItem:Text {text:b.text;textFormat:Text.PlainText;color:b.enabled?App.Palette.ink:App.Palette.muted;font.pixelSize:14;verticalAlignment:Text.AlignVCenter;horizontalAlignment:Text.AlignHCenter}
  background:Rectangle {radius:6;color:b.hovered?App.Palette.hover:App.Palette.button;border.color:b.activeFocus?App.Palette.accent:App.Palette.border}
 }
 ColumnLayout {id:body;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:16;spacing:10
  Copy {text:"OMANOVA updates";font.pixelSize:21;font.bold:true}
  Copy {text:"Installed "+(root.sky.installedRuntime?.version||root.sky.data?.runtime?.version||"unknown")+" · checks published stable GitHub releases only. No automatic checks or installs.";color:App.Palette.muted}
  Copy {text:root.result?.message||"Ready to check for updates.";color:root.result?.status==="error"||root.result?.status==="recovery"?App.Palette.warning:App.Palette.ink}
  Flow {Layout.fillWidth:true;spacing:8
   Action {text:job.running&&root.action==="check"?"Checking…":"Check for updates";onClicked:{root.accepted=false;root.run("check")}}
   Action {visible:!!root.result?.url;text:"Release notes on GitHub";onClicked:if(/^https:\/\/github.com\/shaggyrs6-netizen\/omanova\/releases\/tag\/v[0-9.]+$/.test(root.result.url))Qt.openUrlExternally(root.result.url)}
  }
  Copy {visible:!!root.result?.version;text:"Latest release: "+(root.result?.version||"");font.bold:true}
  Action {visible:!!root.result?.notes;text:root.notesOpen?"Hide release notes":"Show release notes";onClicked:root.notesOpen=!root.notesOpen}
  Copy {visible:root.notesOpen&&!!root.result?.notes;text:root.result?.notes||"";color:App.Palette.muted}
  Copy {visible:root.result?.status==="available"&&!!root.result?.canInstall;text:"Installation downloads and verifies the release, prepares its runtime/widget and restarts an active worker. Saved data and login startup are preserved. Previous files are kept for recovery. Save all forms first; close and reopen Observatory after success, then reload the shell to refresh the bar.";color:App.Palette.muted}
  Copy {visible:root.draftBlocked;text:"Save or clear your unfinished observing-log draft before installing.";color:App.Palette.warning}
  Action {visible:(root.result?.status==="available"&&root.result?.canInstall)||root.result?.status==="installed"||root.result?.status==="recovery";text:root.accepted?"✓ I have saved my changes":"I have saved my changes";onClicked:root.accepted=!root.accepted}
  Action {visible:root.result?.status==="available";enabled:!root.busy&&!!root.result?.canInstall&&root.accepted&&!root.draftBlocked;text:"Download & install "+(root.result?.version||"");onClicked:root.run("launch")}
  Action {visible:root.result?.status==="recovery"||root.result?.status==="installed";enabled:!root.busy&&!root.draftBlocked&&root.accepted;text:"Restore previous installation";onClicked:root.run("restore")}
  Copy {visible:!!root.result?.checked;text:"Last checked: "+Qt.formatDateTime(new Date(root.result?.checked||0),"ddd d MMM HH:mm t")+" · checks cached for five minutes";font.pixelSize:12;color:App.Palette.muted}
  Copy {text:"Your location and log are not sent to GitHub. Download checksums check integrity; they are not independent publisher signatures.";font.pixelSize:12;color:App.Palette.muted}
 }
 Timer {interval:2000;repeat:true;running:root.result?.status==="running";onTriggered:root.run("status")}
 Process {id:job;command:[root.sky.runtime+"/.venv/bin/python",root.sky.runtime+"/update_manager.py","--state",root.sky.directory].concat(root.sky.fixture?["--fixture"]:[]).concat([root.action]);environment:({"OPENBLAS_NUM_THREADS":"1"})
  stdout:StdioCollector {id:output}
  onExited:function(code){try{root.result=JSON.parse(output.text)}catch(e){root.result={status:"error",message:"Update check unavailable. Your installation has not been replaced."}}}
 }
 IpcHandler {target:"omanova-updates";function summary():string{return JSON.stringify({status:root.result?.status,busy:root.busy,canInstall:root.result?.canInstall,blocked:root.draftBlocked,accepted:root.accepted})}
  function sampleAcknowledge():bool{if(!root.sky.fixture)return false;root.accepted=true;return true}
  function sampleCheck():bool{if(!root.sky.fixture)return false;root.run("check");return true}
  function sampleInstall():bool{if(!root.sky.fixture)return false;root.accepted=true;root.run("launch");return true}
 }
}
