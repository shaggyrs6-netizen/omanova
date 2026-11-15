import "./qml/Omanova" as App
import "./qml/Omanova/ObservationDraft.js" as Draft
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
    component Card: Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 22
        Layout.rightMargin: 22
        color: App.Palette.surface
        border.color: App.Palette.line
        radius: 12
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
        stderr: StdioCollector { id: diagnostics }
        onStarted: write(page.pending + "\n")
        onExited: function(code) {
            page.pending = ""
            page.failed = code !== 0
            if (code !== 0) {
                page.message = diagnostics.text.trim() || qsTr("Could not save the observation.")
                return
            }
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

    ColumnLayout {
        Layout.fillWidth: true
        Layout.margins: 22
        spacing: 8
        App.PageHeader { eyebrow:"LOG"; title:qsTr("Observing log") }
        Copy {
            text: page.embedded ? qsTr("Entries stay on this computer. Times use your computer’s time zone.")
                : qsTr("Entries stay on this computer in a separate preview log. Times use your computer’s time zone.")
            color: App.Palette.muted
        }
    }

    Card {
        implicitHeight: form.implicitHeight + 34
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
            Copy {
                visible: !!page.message
                text: page.message
                color: page.failed ? App.Palette.warning : App.Palette.accent
            }
        }
    }

    Card {
        implicitHeight:exportBody.implicitHeight+32
        ColumnLayout {
            id:exportBody;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:16;spacing:8
            Copy {text:qsTr("Export your log");font.pixelSize:22;font.weight:Font.DemiBold}
            Copy {text:qsTr("Export all saved entries to a local CSV, including places and notes. Unsaved drafts are excluded. Sharing is a separate action.");color:App.Palette.muted}
            Flow {
                Layout.fillWidth:true;spacing:8
                Action {text:exportCsv.running?qsTr("Exporting…"):qsTr("Export saved entries to CSV");enabled:page.ready&&page.entries.length>0&&!save.running&&!exportCsv.running;onClicked:{page.exportReceipt=null;exportCsv.running=true}}
                Action {text:qsTr("Open export folder");visible:!!page.exportReceipt;onClicked:Qt.openUrlExternally("file://"+page.directory.split("/").map(encodeURIComponent).join("/")+"/exports")}
            }
            Copy {visible:!!page.exportReceipt;text:page.exportReceipt ? "exports/"+page.exportReceipt.path.split("/").pop() : "";color:App.Palette.accent;font.pixelSize:12}
            Copy {text:qsTr("Spreadsheet formula-like text is escaped in CSV. The saved log stays unchanged. Files are private and never overwrite earlier exports.");color:App.Palette.muted;font.pixelSize:12}
        }
    }

    Copy {
        Layout.leftMargin: 22
        Layout.rightMargin: 22
        text: qsTr("Saved observations")
        font.pixelSize: 22
        font.bold: true
    }
    Copy {
        Layout.leftMargin: 22
        Layout.rightMargin: 22
        visible: page.ready && !page.entries.length
        text: qsTr("Your saved entries will appear here, newest observation first.")
        color: App.Palette.muted
    }
    Repeater {
        model: page.entries
        delegate: Card {
            id: entry
            required property var modelData
            implicitHeight: details.implicitHeight + 32
            ColumnLayout {
                id: details
                anchors.fill: parent
                anchors.margins: 16
                spacing: 6
                Copy { text: entry.modelData.seen; font.pixelSize: 20; font.bold: true }
                Copy { text: entry.modelData.observed.replace("T", " · "); color: App.Palette.accent }
                Copy { text: entry.modelData.place; color: App.Palette.muted }
                Copy { visible: !!entry.modelData.notes; text: entry.modelData.notes }
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
