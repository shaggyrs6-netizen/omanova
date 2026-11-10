import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    readonly property string overridePath: Quickshell.env("OMASKY_STATE")
    readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")
    readonly property string directory: overridePath || (dataHome + "/omasky")
    readonly property string runtime: Quickshell.env("OMASKY_RUNTIME") || (directory + "/runtime")
    property var data: null
    property string message: ""
    property double wallTime: Date.now()
    readonly property bool fixture: data ? data.demo === true : Quickshell.env("OMASKY_FIXTURE") === "1"
    readonly property double now: data && fixture ? Date.parse(data.generated) : wallTime
    readonly property var events: data ? data.events.filter(event => Date.parse(event.end) > now) : []
    readonly property var candidate: data ? data.candidates.find(item => Date.parse(item.end) > now) : null
    readonly property var featured: candidate ? events.find(event => event.id === candidate.id) : null

    function bestWindow(event) {
        if (!event) return null
        const window = candidate && candidate.id === event.id
            ? event.windows.find(item => item.start.time === candidate.start)
            : event.windows.find(item => Date.parse(item.end.time) > now)
        if (!window) return null
        const conditions = window.conditions
        if (conditions.fetched && now - Date.parse(conditions.fetched) >= 21600000)
            return Object.assign({}, window, {
                conditions: { label: "Uncertain", reason: "Forecast expired", hours: [] }
            })
        return window
    }

    function countdown(when) {
        const minutes = Math.max(0, Math.ceil((Date.parse(when) - now) / 60000))
        if (!minutes) return "now"
        if (minutes < 60) return minutes + "m"
        return Math.floor(minutes / 60) + "h " + (minutes % 60) + "m"
    }

    function reload() { snapshot.reload() }

    property string runtimeHelp: ""
    property string pendingInput: ""

    function supports(command) {
        return root.runtimeHelp.split(/[\s,{}]+/).includes(command)
    }

    function run(args, input) {
        if (worker.running) return
        if (["save-stdin", "temporary-stdin"].includes(args[0]) &&
                !root.supports(args[0])) {
            root.message = "Update the OMANOVA runtime before changing this setting."
            return
        }
        message = "Updating…"
        root.pendingInput = input === undefined ? "" : JSON.stringify(input) + "\n"
        worker.command = [runtime + "/.venv/bin/python", runtime + "/worker.py", "--state", directory]
            .concat(fixture ? ["--fixture"] : [], args)
        worker.running = true
    }

    property Process capabilityProbe: Process {
        running: true
        command: [root.runtime + "/.venv/bin/python", root.runtime + "/worker.py", "--help"]
        environment: ({ "OPENBLAS_NUM_THREADS": "1" })
        stdout: StdioCollector { id: helpOutput }
        onExited: function(code) { root.runtimeHelp = code === 0 ? helpOutput.text : "" }
    }

    property FileView snapshotFile: FileView {
        id: snapshot
        path: root.directory + "/snapshot.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                if (parsed && parsed.schema_version === 1 && Array.isArray(parsed.events) &&
                    Array.isArray(parsed.candidates) && parsed.settings)
                    root.data = parsed
            } catch (error) {
                // Keep the last valid snapshot.
            }
        }
    }
    property Timer clock: Timer {
        running: true
        repeat: true
        interval: 15000
        onTriggered: {
            root.wallTime = Date.now()
            if (!root.data) root.reload()
        }
    }
    property Process settingsWorker: Process {
        id: worker
        stdinEnabled: true
        onStarted: {
            if (root.pendingInput) {
                write(root.pendingInput)
                root.pendingInput = ""
            }
        }
        environment: ({ "OPENBLAS_NUM_THREADS": "1" })
        stderr: StdioCollector { id: diagnostic }
        onExited: function(code) {
            root.message = code === 0 ? "Updated" : (diagnostic.text.trim().slice(0, 220) || "OMANOVA worker failed")
            root.reload()
        }
        onRunningChanged: {
            if (!running) Qt.callLater(() => {
                if (!running && root.message === "Updating…")
                    root.message = "Worker could not start. Check the local Python environment."
                if (!running) root.pendingInput = ""
            })
        }
    }
}
