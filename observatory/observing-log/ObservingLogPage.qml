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
    readonly property bool embedded: Quickshell.env("OMASKY_LOG_EMBEDDED") === "1"

    function useNow() {
        const now = new Date()
        day.text = Qt.formatDateTime(now, "yyyy-MM-dd")
        time.text = Qt.formatDateTime(now, "HH:mm")
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
        const observed = timestamp(date, time)
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
    }

    component Copy: Text {
        Layout.fillWidth: true
        color: "#eef5ff"
        font.pixelSize: 15
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }
    component Field: TextField {
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        implicitHeight: 39
        color: "#eef5ff"
        placeholderTextColor: "#a7b7ce"
        selectionColor: "#365c77"
        selectedTextColor: "#ffffff"
        background: Rectangle {
            color: "#0a1424"
            border.color: parent.activeFocus ? "#70edeb" : "#36516d"
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
            color: action.enabled ? "#eef5ff" : "#8190a6"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: 14
        }
        background: Rectangle {
            radius: 6
            color: action.down ? "#243a54" : action.hovered ? "#1a3049" : "#15253c"
            border.color: action.visualFocus ? "#70edeb" : "#36516d"
        }
    }
    component Card: Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 22
        Layout.rightMargin: 22
        color: "#111e31"
        border.color: "#2a3e58"
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

    ColumnLayout {
        Layout.fillWidth: true
        Layout.margins: 22
        spacing: 8
        Copy { text: page.embedded ? qsTr("OMANOVA OBSERVATORY  /  FIELD NOTES") : qsTr("OMANOVA OBSERVATORY  /  PRIVATE PREVIEW"); color: "#70edeb"; font.letterSpacing: 1.5; font.pixelSize: 12 }
        Copy { text: qsTr("Observing log"); font.pixelSize: 34; font.bold: true }
        Copy {
            text: page.embedded ? qsTr("Entries stay on this computer. Times use your computer’s time zone.")
                : qsTr("Entries stay on this computer in a separate preview log. Times use your computer’s time zone.")
            color: "#a7b7ce"
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
            Copy { text: qsTr("What did you see?") }
            Field { id: seen; maximumLength: 120; Accessible.name: qsTr("What did you see?"); placeholderText: qsTr("e.g. ISS pass") }
            Copy { text: qsTr("Where were you?") }
            Field { id: where; maximumLength: 120; Accessible.name: qsTr("Where were you?"); placeholderText: qsTr("e.g. Home or a park") }
            Copy { text: qsTr("When did you see it?") }
            GridLayout {
                Layout.fillWidth: true
                columns: width < 295 ? 1 : 3
                Field { id: day; maximumLength: 10; Accessible.name: qsTr("Date, year month day"); placeholderText: "YYYY-MM-DD" }
                Field { id: time; maximumLength: 5; Accessible.name: qsTr("Time, 24-hour clock"); placeholderText: "HH:MM" }
                Action { text: qsTr("Use current time"); onClicked: page.useNow() }
            }
            Copy { text: qsTr("Notes · optional") }
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 94
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                TextArea {
                    id: notes
                    color: "#eef5ff"
                    placeholderTextColor: "#a7b7ce"
                    placeholderText: qsTr("What stood out? How was the view?")
                    Accessible.name: qsTr("Notes")
                    wrapMode: TextEdit.Wrap
                    background: Rectangle {
                        color: "#0a1424"
                        border.color: parent.activeFocus ? "#70edeb" : "#36516d"
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
                color: page.failed ? "#ffcc7b" : "#70edeb"
            }
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
        color: "#a7b7ce"
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
                Copy { text: entry.modelData.observed.replace("T", " · "); color: "#70edeb" }
                Copy { text: entry.modelData.place; color: "#a7b7ce" }
                Copy { visible: !!entry.modelData.notes; text: entry.modelData.notes }
            }
        }
    }
    Item { implicitHeight: 12 }
}
