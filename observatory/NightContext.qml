import QtQuick
import Quickshell
import Quickshell.Io
QtObject {
    id: root
    required property var skyModel
    property var dataSet: null
    property string error: ""
    readonly property string path: Quickshell.env("OMANOVA_NIGHT_CONTEXT")
    readonly property string locationId: skyModel.data?.place?.id || ""
    readonly property bool current: !!dataSet && dataSet.location_id === locationId &&
        Number.isFinite(Date.parse(dataSet.generated)) && skyModel.now >= Date.parse(dataSet.generated) &&
        skyModel.now-Date.parse(dataSet.generated) < 1800000
    function refresh() { if(!job.running && path && locationId) {error="";job.running=true} }
    readonly property string sourceKey: locationId+"|"+(skyModel.data?.settings?.weather === true)
    onSourceKeyChanged: { dataSet=null; refresh() }
    Component.onCompleted: refresh()
    property Process job: Process {
        command: [root.skyModel.runtime+"/.venv/bin/python",root.skyModel.runtime+"/observatory/night_context.py", "--state",root.skyModel.directory,"--output",root.path]
        environment: ({"OPENBLAS_NUM_THREADS":"1"})
        onExited: function(code) {
            if(code===0) file.reload()
            else {root.dataSet=null;root.error="Night strip unavailable. Other observing views remain available."}
            // A location change while the helper ran needs a second, matching calculation.
            if(root.locationId && root.dataSet && root.dataSet.location_id!==root.locationId) root.refresh()
        }
    }
    property FileView file: FileView {
        path:root.path;printErrors:false
        onLoaded: {try {root.dataSet=JSON.parse(text());if(!root.skyModel.fixture)root.skyModel.wallTime=Date.now();if(root.dataSet.location_id!==root.locationId)root.refresh()}catch(e){root.dataSet=null}}
    }
    property Timer timer: Timer {interval:300000;repeat:true;running:true;onTriggered:root.refresh()}
}
