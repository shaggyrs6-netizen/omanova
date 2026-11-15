import "." as App
import QtQuick
import QtQuick.Layouts
Rectangle {
    id: card
    required property var sky
    Layout.fillWidth:true
    implicitHeight:body.implicitHeight+32
    color:App.Palette.surface;border.color:App.Palette.line;radius:10
    function identityText(value) {
        if(!value) return "Not reported by this worker"
        return (value.version || "unknown")+" · "+(value.build || "build not reported")+
            (value.revision?" · "+value.revision.slice(0,8):" · revision not recorded")
    }
    component Copy:Text {
        Layout.fillWidth:true;wrapMode:Text.Wrap;textFormat:Text.PlainText
        color:App.Palette.ink;font.pixelSize:14
    }
    ColumnLayout {
        id:body;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:16;spacing:8
        Copy {text:"Runtime & data status";font.pixelSize:21;font.weight:Font.DemiBold}
        Copy {text:card.sky.runtimeStatus;color:card.sky.snapshotStale||card.sky.runtimeMismatch?App.Palette.warning:App.Palette.accent;font.weight:Font.DemiBold}
        Copy {text:"Running snapshot: "+card.identityText(card.sky.runningRuntime)}
        Copy {text:"Installed files: "+card.identityText(card.sky.installedRuntime);color:App.Palette.muted}
        Copy {text:card.sky.data?.generated?"Snapshot updated: "+Qt.formatDateTime(new Date(card.sky.data.generated),"ddd d MMM yyyy · HH:mm:ss")+" local":"No worker snapshot received yet.";color:App.Palette.muted}
        Copy {visible:card.sky.runtimeMismatch;text:"Installed files and worker snapshot report different builds. Restart the worker to load the installed build.";color:App.Palette.warning}
        Copy {visible:!card.sky.runningRuntime&&!card.sky.fixture;text:"This snapshot has no build identity. Refresh or restart the worker after upgrading; older runtimes may not report it.";color:App.Palette.warning}
        Copy {text:card.sky.plannerStale?"Planning data: missing, stale or for a different location. Recommendations are withheld.":"Planning data: current for this location.";color:card.sky.plannerStale?App.Palette.warning:App.Palette.muted}
        Copy {text:"Current means a valid snapshot arrived within three minutes. It does not prove the process is still running or that every external source is fresh. Individual views show source and forecast age.";color:App.Palette.muted}
        Flow {
            Layout.fillWidth:true;spacing:8
            ActionButton {text:"Refresh status";onClicked:card.sky.refreshRuntimeStatus()}
            Copy {width:Math.max(200,body.width-160);text:"Worker check: systemctl --user status omanova-worker.service";color:App.Palette.muted;font.pixelSize:12}
        }
    }
}
