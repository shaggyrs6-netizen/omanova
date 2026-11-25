import "../../qml/Omanova" as App
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

App.InstrumentCard {
    id: tools
    property string runtime
    property string siteSource
    property bool sample: false
    property string filePath: ""
    property string atlasPath: ""
    property string targetId: ""
    property string targetName: ""
    property string message: ""
    property string pending: ""

    function request(action) {
        if (sample || task.running) return
        pending = JSON.stringify({
            action: action, source: siteSource,
            path: action === "skyglow" ? atlasPath : filePath,
            device: device.text, target: targetId, confirm: confirmed.checked
        }) + "\n"
        confirmed.checked = false
        message = "Working locally…"
        task.stdinEnabled = true
        task.running = true
    }

    onSiteSourceChanged: { message = ""; confirmed.checked = false }
    onTargetIdChanged: confirmed.checked = false
    onFilePathChanged: message = ""
    onAtlasPathChanged: message = ""
    FileDialog {
        id: atlas
        title: "Choose a World Atlas 2015 GeoTIFF"
        nameFilters: ["GeoTIFF (*.tif *.tiff)"]
        onAccepted: tools.atlasPath = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""))
    }
    FileDialog {
        id: image
        title: "Choose a local sky image"
        nameFilters: ["Sky images (*.fit *.fits *.fts *.png *.jpg *.jpeg)"]
        onAccepted: tools.filePath = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""))
    }
    Process {
        id: task
        command: [tools.runtime + "/.venv/bin/python", tools.runtime + "/observatory/field/instruments.py"]
        environment: ({"OPENBLAS_NUM_THREADS": "1"})
        onStarted: { write(tools.pending); tools.pending = ""; stdinEnabled = false }
        stdout: StdioCollector { id: output }
        onExited: function(code) {
            try { tools.message = code === 0 ? JSON.parse(output.text).message : "Instrument request failed." }
            catch (error) { tools.message = "Instrument request failed." }
        }
    }

    component Copy: Text {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        color: App.Palette.ink
        font.pixelSize: 14
    }

    Copy { text: "Skyglow estimate"; font.bold: true }
    Copy { text: "Choose a local World Atlas 2015 GeoTIFF. The estimate uses the Finder location above. Your manual sky preference still controls suggestions."; color: App.Palette.muted }
    Flow {
        Layout.fillWidth: true
        spacing: 8
        App.ActionButton { text: "Choose atlas…"; enabled: !tools.sample && !task.running; onClicked: atlas.open() }
        App.ActionButton { text: "Estimate skyglow"; enabled: !!tools.atlasPath && !task.running; onClicked: tools.request("skyglow") }
    }

    Copy { visible: !!tools.atlasPath; text: tools.atlasPath.split("/").pop(); color: App.Palette.muted }

    Copy { text: "Plate solving"; font.bold: true }
    Copy { text: "Solve a local sky image for its centre, pixel scale and rotation with Astrometry.net and local indexes."; color: App.Palette.muted }
    Flow {
        Layout.fillWidth: true
        spacing: 8
        App.ActionButton { text: "Choose image…"; enabled: !tools.sample && !task.running; onClicked: image.open() }
        App.ActionButton { text: "Solve locally"; enabled: !!tools.filePath && !task.running; onClicked: tools.request("solve") }
    }

    Copy { visible: !!tools.filePath; text: tools.filePath.split("/").pop(); color: App.Palette.muted }

    Copy { text: "INDI telescope"; font.bold: true }
    Copy { text: "Use a local INDI server. Connect and align the mount there first. Go To uses your active observing site and a target selected below."; color: App.Palette.muted }
    TextField {
        id: device
        Layout.fillWidth: true
        Layout.maximumWidth: 400
        maximumLength: 80
        enabled: !tools.sample && !task.running
        placeholderText: "Exact INDI device name"
        Accessible.name: placeholderText
        color: App.Palette.ink
        placeholderTextColor: App.Palette.muted
        onTextChanged: confirmed.checked = false
        background: Rectangle { radius: 5; color: App.Palette.field; border.color: App.Palette.border }
    }
    Copy { text: tools.targetName ? "Selected for Go To · " + tools.targetName : "Select a deep-sky target from the Finder below." }
    CheckBox {
        id: confirmed
        Layout.fillWidth: true
        enabled: !!tools.targetId && !!device.text.trim() && !task.running
        implicitHeight: Math.max(40, contentItem.implicitHeight + 12)
        text: "The aligned mount is clear to move and under supervision."
        contentItem: Text {
            text: confirmed.text
            leftPadding: confirmed.indicator.width + confirmed.spacing
            wrapMode: Text.Wrap
            color: confirmed.enabled ? App.Palette.ink : App.Palette.muted
            verticalAlignment: Text.AlignVCenter
        }
    }
    Flow {
        Layout.fillWidth: true
        spacing: 8
        App.ActionButton { text: "Read mount position"; enabled: !!device.text.trim() && !task.running; onClicked: tools.request("position") }
        App.ActionButton { text: "Go To selected target"; enabled: confirmed.checked && confirmed.enabled; onClicked: tools.request("goto") }
        App.ActionButton { text: "Request stop"; enabled: !!device.text.trim() && !task.running; onClicked: tools.request("stop") }
    }
    Copy { visible: !!tools.message; text: tools.message; color: App.Palette.accent }
}
