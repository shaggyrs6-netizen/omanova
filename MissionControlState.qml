import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    readonly property string helper: Quickshell.env("OMANOVA_WALLPAPER_HELPER")
    readonly property bool configured: helper.length > 0
    readonly property bool busy: runner.running || settling
    property bool settling: false
    property var state: ({message: configured ? qsTr("Checking wallpaper…") :
                                      qsTr("Optional Mission Control component is unavailable.")})
    property string error: ""
    property string action: "status"

    function request(name) {
        if (!configured || runner.running || (settling && name !== "status") ||
                !["status", "start", "normal", "login-on", "login-off"].includes(name))
            return false
        action = name
        if (name !== "status") error = ""
        runner.running = true
        return true
    }

    property Process worker: Process {
        id: runner
        command: root.action.startsWith("login-") ?
                     [root.helper, "startup", root.action.slice(6)] : [root.helper, root.action]
        environment: ({
            XDG_RUNTIME_DIR: Quickshell.env("OMANOVA_WALLPAPER_RUNTIME"),
            XDG_CONFIG_HOME: Quickshell.env("OMANOVA_WALLPAPER_CONFIG")
        })
        stdout: StdioCollector { id: output }
        onExited: function(code) {
            let value = null
            try { value = JSON.parse(output.text) } catch (_) {}
            if (root.action === "status") {
                root.state = code === 0 && value ? value : {message: qsTr("Wallpaper status unavailable.")}
                root.settling = false
            } else {
                root.settling = true
                if (code !== 0 || value?.error)
                    root.error = value?.error || qsTr("Wallpaper change could not be verified. If needed, use Restore desktop in the Mission Control window.")
                Qt.callLater(root.request, "status")
            }
        }
    }
}
