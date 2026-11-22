import "../../qml/Omanova" as App
import "../../qml/Omanova/ObservationDraft.js" as Draft
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: page
    spacing: 14
    readonly property string directory: Quickshell.env("OMASKY_LOG_STATE")
    readonly property string tool: Quickshell.env("OMASKY_LOG_TOOL")
    property var entries: []
    property string selectedId: ""
    property bool composing: false
    readonly property var selectedEntry: entries.find(e=>e.id===selectedId) || entries[0] || null
    readonly property bool showForm: composing || !selectedEntry
    function localLabel(stamp, format) { return Qt.formatDateTime(new Date(stamp),format) }
    function beginDraft() {
        composing=true
        if (!dirty) { useNow(); draftContext="" }
        seen.forceActiveFocus()
    }
    property string message: ""
    property bool failed: false
    property string pending: ""
    property bool ready: false
    property var draftRequest: null
    property var replacementDraft: null
    property var exportReceipt: null
    property string lastDraftToken: ""
    property string draftContext: ""
    property string preservedInstant: ""
    property bool dirty: false
    property bool filling: false
    function markDirty() { if(!filling) dirty=true }
    function receiveDraft() {
        if(!draftRequest || String(draftRequest.token)===lastDraftToken) return
        lastDraftToken=String(draftRequest.token)
        composing=true
        if(dirty) replacementDraft=draftRequest
        else applyDraft(draftRequest)
    }
    function applyDraft(draft) {
        filling=true
        seen.text=draft.seen || ""
        where.text=draft.place || ""
        notes.text=draft.notes || ""
        const instant=new Date(draft.observed)
        if(Number.isFinite(instant.getTime())) {
            day.text=Qt.formatDateTime(instant,"yyyy-MM-dd")
            time.text=Qt.formatDateTime(instant,"HH:mm")
            preservedInstant=draft.observed
        }
        draftContext=draft.context || ""
        filling=false
        dirty=true
        replacementDraft=null
        message=qsTr("Draft only. Check what, where and when, then Save observation.")
        failed=false
        seen.forceActiveFocus()
    }
    onDraftRequestChanged: Qt.callLater(page.receiveDraft)
    readonly property bool embedded: Quickshell.env("OMASKY_LOG_EMBEDDED") === "1"

    function useNow() {
        const now = new Date()
        day.text = Qt.formatDateTime(now, "yyyy-MM-dd")
        time.text = Qt.formatDateTime(now, "HH:mm")
        preservedInstant = Draft.localStamp(now)
    }
    function timestamp(date, time) {
        const entered = date.trim() + "T" + time.trim()
        if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(entered)) return ""
        const local = new Date(entered)
        if (isNaN(local.getTime()) || Qt.formatDateTime(local, "yyyy-MM-dd'T'HH:mm") !== entered) return ""
        const offset = -local.getTimezoneOffset()
        const absolute = Math.abs(offset)
        const hours = String(Math.floor(absolute / 60)).padStart(2, "0")
        const minutes = String(absolute % 60).padStart(2, "0")
        return entered + (offset < 0 ? "-" : "+") + hours + ":" + minutes
    }
    function submit(object, location, detail, date, time) {
        if (!ready || save.running) return
        const observed = preservedInstant || timestamp(date, time)
        if (!observed || !object.trim() || !location.trim()) {
            failed = true
            message = !object.trim() ? qsTr("Enter what you saw.")
                : !location.trim() ? qsTr("Enter where you were.")
                : qsTr("Enter a valid date and time in your local time zone.")
            return
        }
        pending = JSON.stringify({ seen: object, place: location, notes: detail, observed: observed })
        message = qsTr("Saving…")
        failed = false
        save.running = true
    }

    Component.onCompleted: {
        useNow()
        if (embedded) initialise.running = true
        Qt.callLater(page.receiveDraft)
    }

    component Copy: Text {
        Layout.fillWidth: true
        color: App.Palette.ink
        font.pixelSize: 15
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }
    component Field: TextField {
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        implicitHeight: 39
        color: App.Palette.ink
        placeholderTextColor: App.Palette.muted
        selectionColor: App.Palette.button
        selectedTextColor: App.Palette.ink
        background: Rectangle {
            color: App.Palette.field
            border.color: parent.activeFocus ? App.Palette.accent : App.Palette.border
            radius: 6
        }
    }
    component Action: Button {
        id: action
        implicitHeight: 38
        leftPadding: 12
        rightPadding: 12
        contentItem: Text {
            text: action.text
            color: action.enabled ? App.Palette.ink : App.Palette.muted
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: 14
        }
        background: Rectangle {
            radius: 6
            color: action.down ? App.Palette.button : action.hovered ? App.Palette.hover : App.Palette.button
            border.color: action.visualFocus ? App.Palette.accent : App.Palette.border
        }
    }
    FileView {
        id: history
        path: page.directory + "/observations.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                if (parsed.schema !== 1 || !Array.isArray(parsed.entries))
                    throw new Error("Unsupported log")
                page.entries = parsed.entries
                page.ready = true
            } catch (error) {
                page.ready = false
                page.failed = true
                page.message = qsTr("Could not read the local log. Its contents have been kept.")
            }
        }
        onLoadFailed: {
            if (initialise.running) return
            page.ready = false
            page.failed = true
            page.message = qsTr("Could not open the local log.")
        }
    }

    Process {
        id: initialise
        command: [page.tool + "/.venv/bin/python", page.tool + "/observatory/observing-log/observing_log.py",
            page.directory, "init"]
        environment: ({ "OPENBLAS_NUM_THREADS": "1" })
        onExited: function(code) {
            if (code === 0) history.reload()
            else {
                page.ready = false
                page.failed = true
                page.message = qsTr("Could not open the local log.")
            }
        }
    }

    Process {
        id: save
        command: [page.tool + "/.venv/bin/python", page.tool + "/observatory/observing-log/observing_log.py",
            page.directory, "add"]
        environment: ({ "OPENBLAS_NUM_THREADS": "1" })
        stdinEnabled: true
        stdout: StdioCollector { id: receipt }
        stderr: StdioCollector { id: diagnostics }
        onStarted: write(page.pending + "\n")
        onExited: function(code) {
            page.pending = ""
            page.failed = code !== 0
            if (code !== 0) {
                page.message = diagnostics.text.trim() || qsTr("Could not save the observation.")
                return
            }
            try { page.selectedId=JSON.parse(receipt.text).id } catch (_) { page.selectedId="" }
            page.composing=false
            seen.clear()
            notes.clear()
            page.dirty = false
            page.draftContext = ""
            page.message = qsTr("Observation saved.")
            history.reload()
        }
        onRunningChanged: if (!running) Qt.callLater(() => {
            if (!running && page.pending) {
                page.pending = ""
                page.failed = true
                page.message = qsTr("Could not start the local log writer.")
            }
        })
    }

    Process {
        id: exportCsv
        command: [page.tool+"/.venv/bin/python",page.tool+"/observatory/observing-log/observing_log.py",page.directory,"export-csv"]
        environment: ({"OPENBLAS_NUM_THREADS":"1"})
        stdout: StdioCollector {id: exportOutput}
        stderr: StdioCollector {id: exportError}
        onExited: function(code) {
            page.failed=code!==0
            if(code===0) {
                try {
                    page.exportReceipt=JSON.parse(exportOutput.text)
                    page.message=qsTr("CSV saved locally · %1 entries. Your log is unchanged.").arg(page.exportReceipt.count)
                } catch(e) {page.failed=true;page.message=qsTr("Could not read the export receipt. Check the local exports folder.")}
            } else page.message=exportError.text.trim() || qsTr("Could not export the local log.")
        }
    }

    Flow {
        Layout.fillWidth:true;Layout.leftMargin:20;Layout.rightMargin:20;Layout.topMargin:14
        spacing:8
        Column {
            width:Math.max(220,parent.width-exportAction.width-newAction.width-20)
            spacing:4
            Copy {text:qsTr("Observing Log");font.pixelSize:29;font.bold:true}
            Copy {text:qsTr("Saved on this computer · Times shown in your local time zone");color:App.Palette.muted;font.pixelSize:14;width:parent.width}
        }
        Action {
            id:exportAction;text:qsTr("Export CSV")
            enabled:page.ready&&page.entries.length>0&&!save.running&&!exportCsv.running
            onClicked:{page.exportReceipt=null;exportCsv.running=true}
        }
        Action {
            id:newAction;text:page.dirty?qsTr("Resume draft"):qsTr("+ New observation")
            enabled:page.ready&&!save.running
            onClicked:page.beginDraft()
        }
    }
    Copy {
        Layout.leftMargin:20;Layout.rightMargin:20
        visible:!!page.message;text:page.message;color:page.failed?App.Palette.warning:App.Palette.accent
    }
    Action {
        visible:!!page.exportReceipt;Layout.leftMargin:20;text:qsTr("Open export folder")
        onClicked:Qt.openUrlExternally("file://"+page.directory.split("/").map(encodeURIComponent).join("/")+"/exports")
    }
    GridLayout {
        id:grid
        Layout.fillWidth:true;Layout.leftMargin:18;Layout.rightMargin:18
        columns:width>=715?2:1;columnSpacing:12;rowSpacing:12
        App.ViewPanel {
            appearance:"mission";Layout.fillWidth:true;Layout.preferredWidth:310;Layout.fillHeight:grid.columns===2
            Layout.alignment:Qt.AlignTop;implicitHeight:listBody.implicitHeight+30
            ColumnLayout {
                id:listBody;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:15;spacing:8
                RowLayout {
                    Layout.fillWidth:true
                    Copy {text:qsTr("Saved observations");font.pixelSize:19;font.bold:true}
                    Copy {Layout.fillWidth:false;text:String(page.entries.length);color:App.Palette.muted}
                }
                Copy {visible:page.ready&&!page.entries.length;text:qsTr("Your first saved observation will appear here.");color:App.Palette.muted}
                ListView {
                    id:list
                    Layout.fillWidth:true;Layout.preferredHeight:Math.min(contentHeight,grid.columns===1?182:422)
                    clip:true;model:page.entries;spacing:3
                    ScrollBar.vertical:ScrollBar {}
                    delegate:Column {
                        id:row
                        required property int index
                        required property var modelData
                        width:list.width
                        readonly property string dateLabel:page.localLabel(modelData.observed,"dddd · d MMM yyyy")
                        Text {
                            leftPadding:4;topPadding:10;bottomPadding:6
                            visible:row.index===0 || row.dateLabel!==page.localLabel(page.entries[row.index-1]?.observed || "","dddd · d MMM yyyy")
                            text:row.dateLabel;font.pixelSize:12;font.bold:true;color:App.Palette.muted
                        }
                        Button {
                            width:parent.width;height:62
                            Accessible.name:row.modelData.seen+" · "+row.dateLabel
                            enabled:!save.running
                            onClicked:{page.selectedId=row.modelData.id;page.composing=false}
                            readonly property bool picked:!page.showForm && page.selectedEntry?.id===row.modelData.id
                            background:Rectangle {radius:5;color:parent.picked?App.Palette.hover:App.Palette.field;border.color:parent.visualFocus||parent.picked?App.Palette.accent:App.Palette.line}
                            contentItem:ColumnLayout {
                                spacing:2
                                RowLayout {
                                    Layout.fillWidth:true
                                    Text {Layout.fillWidth:true;elide:Text.ElideRight;textFormat:Text.PlainText;text:row.modelData.seen;color:App.Palette.ink;font.bold:true;font.pixelSize:16}
                                    Text {text:page.localLabel(row.modelData.observed,"HH:mm");color:App.Palette.accent;font.pixelSize:14}
                                }
                                Text {Layout.fillWidth:true;elide:Text.ElideRight;textFormat:Text.PlainText;text:row.modelData.place;color:App.Palette.muted;font.pixelSize:13}
                            }
                        }
                    }
                }
            }
        }
        App.ViewPanel {
            visible:page.showForm;appearance:"mission";Layout.fillWidth:true;Layout.preferredWidth:660
            Layout.alignment:Qt.AlignTop;implicitHeight:form.implicitHeight+34
        ColumnLayout {
            id: form
            anchors.fill: parent
            anchors.margins: 17
            spacing: 7
            enabled: !save.running

            Copy { text: qsTr("New observation"); font.pixelSize: 22; font.bold: true }
            Copy {visible:!!page.draftContext;text:page.draftContext;color:App.Palette.muted}
            Copy {visible:!!page.replacementDraft;text:qsTr("You already have an unfinished entry. Keep it, or replace it with the selected event draft. Nothing has been saved.");color:App.Palette.warning}
            Flow {
                visible:!!page.replacementDraft;Layout.fillWidth:true;spacing:8
                Action {text:qsTr("Keep current draft");onClicked:page.replacementDraft=null}
                Action {text:qsTr("Use event draft");onClicked:page.applyDraft(page.replacementDraft)}
            }
            Copy {text:qsTr("Drafts stay while this Observatory window is open, including when switching pages. Save before closing the window.");color:App.Palette.muted;font.pixelSize:12}
            Copy { text: qsTr("What did you see?") }
            Field { id: seen; maximumLength: 120; Accessible.name: qsTr("What did you see?"); placeholderText: qsTr("e.g. ISS pass");onTextEdited:page.markDirty() }
            Copy { text: qsTr("Where were you?") }
            Field { id: where; maximumLength: 120; Accessible.name: qsTr("Where were you?"); placeholderText: qsTr("e.g. Home or a park");onTextEdited:page.markDirty() }
            Copy { text: qsTr("When did you see it?") }
            GridLayout {
                Layout.fillWidth: true
                columns: width < 295 ? 1 : 3
                Field { id: day; maximumLength: 10; Accessible.name: qsTr("Date, year month day"); placeholderText: "YYYY-MM-DD";onTextEdited:{page.preservedInstant="";page.markDirty()} }
                Field { id: time; maximumLength: 5; Accessible.name: qsTr("Time, 24-hour clock"); placeholderText: "HH:MM";onTextEdited:{page.preservedInstant="";page.markDirty()} }
                Action { text: qsTr("Use current time"); onClicked: {page.useNow();page.markDirty()} }
            }
            Copy { text: qsTr("Notes · optional") }
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 94
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                TextArea {
                    id: notes
                    onTextChanged:page.markDirty()
                    color: App.Palette.ink
                    placeholderTextColor: App.Palette.muted
                    placeholderText: qsTr("What stood out? How was the view?")
                    Accessible.name: qsTr("Notes")
                    wrapMode: TextEdit.Wrap
                    background: Rectangle {
                        color: App.Palette.field
                        border.color: parent.activeFocus ? App.Palette.accent : App.Palette.border
                        radius: 6
                    }
                }
            }
            Action {
                text: save.running ? qsTr("Saving…") : qsTr("Save observation")
                enabled: page.ready && !save.running
                onClicked: page.submit(seen.text, where.text, notes.text, day.text, time.text)
            }
        }
        }
        App.ViewPanel {
            visible:!page.showForm;appearance:"mission";Layout.fillWidth:true;Layout.preferredWidth:660
            Layout.alignment:Qt.AlignTop;implicitHeight:Math.max(295,detail.implicitHeight+40)
            ColumnLayout {
                id:detail;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:20;spacing:15
                Copy {text:page.selectedEntry?page.localLabel(page.selectedEntry.observed,"dddd, d MMMM yyyy"):"";color:App.Palette.muted}
                Copy {text:page.selectedEntry?.seen || "";font.pixelSize:34;font.bold:true}
                Rectangle {Layout.fillWidth:true;implicitHeight:1;color:App.Palette.line}
                GridLayout {
                    Layout.fillWidth:true;columns:2;columnSpacing:18
                    Copy {text:qsTr("Observed at");color:App.Palette.muted}
                    Copy {text:qsTr("Location");color:App.Palette.muted}
                    Copy {text:page.selectedEntry?page.localLabel(page.selectedEntry.observed,"HH:mm t"):"";font.pixelSize:21;font.bold:true;color:App.Palette.accent}
                    Copy {text:page.selectedEntry?.place || "";font.pixelSize:21;font.bold:true}
                }
                Rectangle {Layout.fillWidth:true;implicitHeight:1;color:App.Palette.line}
                Copy {text:qsTr("Observing notes");font.bold:true;font.pixelSize:18}
                Copy {text:page.selectedEntry?.notes || qsTr("No notes recorded.")}
            }
        }
    }
    IpcHandler {
        target:"omanova-log-actions"
        function summary():string {return JSON.stringify({ready:page.ready,count:page.entries.length,dirty:page.dirty,replacement:!!page.replacementDraft,context:!!page.draftContext,exported:page.exportReceipt?.count??null,busy:save.running||exportCsv.running})}
        function sampleFields():string {if(Quickshell.env("OMASKY_SETTINGS_PREVIEW")!=="1")return "";return JSON.stringify({seen:seen.text,place:where.text,day:day.text,time:time.text,observed:page.preservedInstant,notes:notes.text})}
        function sampleSave():void {if(Quickshell.env("OMASKY_SETTINGS_PREVIEW")==="1")page.submit(seen.text,where.text,notes.text,day.text,time.text)}
        function sampleExport():void {if(Quickshell.env("OMASKY_SETTINGS_PREVIEW")==="1"&&page.ready&&!exportCsv.running)exportCsv.running=true}
        function sampleKeep():void {if(Quickshell.env("OMASKY_SETTINGS_PREVIEW")==="1")page.replacementDraft=null}
    }
    Item { implicitHeight: 12 }
}
