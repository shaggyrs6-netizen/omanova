import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: ui
    spacing: 16
    property var lunar: null
    readonly property color ink: "#f2f7ff"
    readonly property color muted: "#a7b7ce"
    readonly property color cyan: "#70edeb"
    readonly property int gutter: width < 650 ? 15 : 28
    readonly property var full: lunar?.full || null
    readonly property bool named: Quickshell.env("OMASKY_NAMED_MOONS") === "1"

    function when(value, format) {
        return value ? Qt.formatDateTime(new Date(value), format || "ddd d MMM · HH:mm") : "Unavailable"
    }
    function interval(start, end) {
        const sameDay = new Date(start).toDateString() === new Date(end).toDateString()
        return when(start) + " – " + when(end, sameDay ? "HH:mm" : "ddd d MMM · HH:mm") + " local"
    }
    function percent(value) {
        return value > 0 && value < 0.01 ? "<1%" : Math.round(value * 100) + "%"
    }

    component Copy: Text {
        Layout.fillWidth: true
        color: ui.ink
        font.family: "sans-serif"
        font.pixelSize: 14
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }
    component Tag: Copy {
        color: ui.muted
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.letterSpacing: 1.1
    }
    component Rule: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: "#2a3e58"
    }
    component ViewingList: ColumnLayout {
        id: list
        property var windows: []
        spacing: 10
        Repeater {
            model: list.windows
            delegate: ColumnLayout {
                id: row
                required property var modelData
                Layout.fillWidth: true
                spacing: 4
                Rule {}
                Copy { text: ui.interval(row.modelData.start.time, row.modelData.end.time); color: ui.cyan }
                Copy {
                    text: "Start " + row.modelData.start.direction + " · " +
                        "Highest " + row.modelData.peak.direction + " at " + ui.when(row.modelData.peak.time, "HH:mm") +
                        " · " + Math.round(row.modelData.peak.el) + "° up · " + ui.percent(row.modelData.illumination) + " lit"
                    color: ui.muted
                }
            }
        }
        Copy { visible: !list.windows.length; text: "No darker-sky window found in this range."; color: ui.muted }
    }

    FileView {
        id: snapshot
        printErrors: false
        path: Quickshell.env("OMASKY_MOON")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { ui.lunar = JSON.parse(text()) }
            catch (error) { ui.lunar = null }
        }
    }

    readonly property string tool: Quickshell.env("OMASKY_MOON_TOOL")
    property string loadMessage: ""
    Component.onCompleted: {
        if (tool && snapshot.path) calculate.running = true
    }
    Process {
        id: calculate
        command: [ui.tool + "/.venv/bin/python", ui.tool + "/observatory/moon/moon.py",
            snapshot.path, Quickshell.env("OMASKY_FIXTURE") === "1" ? "fixture" : "live"]
        environment: ({ "OPENBLAS_NUM_THREADS": "1" })
        stderr: StdioCollector { id: diagnostics }
        onExited: function(code) {
            if (code === 0) snapshot.reload()
            else ui.loadMessage = diagnostics.text.trim() || "Moon calculation unavailable"
        }
    }
    Copy {
        visible: calculate.running || !!ui.loadMessage
        Layout.leftMargin: ui.gutter; Layout.rightMargin: ui.gutter
        text: calculate.running ? "Calculating lunar positions…" : ui.loadMessage
        color: ui.muted
    }
    function summary() {
        return { fixture: lunar?.fixture, phase: lunar?.phase, illumination: lunar?.illumination,
            full: full?.time, fullBelowHorizon: full ? full.el < 0 : null, windows: full?.windows.length,
            fullName: named ? full?.name : undefined, fullSize: named ? full?.size : undefined,
            nextRise: lunar?.horizon?.rise?.time,
            currentDisk: [currentDisk.width, currentDisk.height], fullDisk: [fullDisk.width, fullDisk.height] }
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.margins: ui.gutter
        Layout.bottomMargin: 0
        spacing: 4
        Tag { text: "OMANOVA  /  LUNAR ALMANAC"; color: ui.cyan }
        Copy { text: "Moon"; font.pixelSize: 43; font.weight: Font.DemiBold }
        Copy { text: ui.lunar?.fixture ? "Offline Nashville fixture" : "Local observing point · Calculated offline"; color: ui.muted }
    }
    GridLayout {
        Layout.fillWidth: true
        Layout.leftMargin: ui.gutter; Layout.rightMargin: ui.gutter
        columns: width < 600 ? 1 : 2
        columnSpacing: 22
        rowSpacing: 18
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            implicitHeight: 295
            radius: 10
            color: "#101c32"
            border.color: "#2a3e58"
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 13
                spacing: 3
                Tag { text: "CURRENT PHASE" }
                Copy { text: ui.lunar?.phase || "Calculating…"; font.pixelSize: 25; font.weight: Font.DemiBold }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    MoonDisk {
                        id: currentDisk
                        Layout.fillWidth: true; Layout.fillHeight: true
                        Layout.preferredWidth: 180
                        Layout.minimumHeight: 140
                        fraction: ui.lunar?.illumination || 0
                        waxing: ui.lunar?.waxing ?? true
                    }
                    ColumnLayout {
                        Layout.preferredWidth: 108
                        Copy { text: ui.lunar ? ui.percent(ui.lunar.illumination) : "—"; font.pixelSize: 32; color: ui.cyan }
                        Tag { text: "ILLUMINATED" }
                    }
                }
                Copy {
                    text: !ui.lunar ? "" : ui.lunar.position.el < 0 ? "Below your horizon at calculation time" :
                        "At calculation time · " + ui.lunar.position.direction + " · " + Math.round(ui.lunar.position.el) + "° above horizon"
                    color: ui.muted
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            spacing: 7
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                MoonDisk {
                    id: fullDisk
                    Layout.preferredWidth: 70; Layout.preferredHeight: 70
                    fraction: 1
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Tag { text: "NEXT FULL MOON"; color: ui.cyan }
                    Copy {
                        text: (ui.named && ui.full?.name) || ui.when(ui.full?.time) + " local"
                        font.pixelSize: 25; font.weight: Font.DemiBold
                    }
                    Copy {
                        visible: ui.named && !!ui.full?.size
                        text: visible ? ui.full.size + " · " + ui.full.distanceKm.toLocaleString(Qt.locale(), 'f', 0) + " km" : ""
                        color: ui.cyan
                    }
                }
            }
            Copy {
                visible: ui.named && !!ui.full
                text: "Exact phase · " + ui.when(ui.full?.time) + " local"
                color: ui.muted
            }
            Copy {
                text: !ui.full ? "Calculating…" : ui.full.el < 0 ? "Below your horizon at the exact full moon." :
                    "Above your horizon at the exact full moon · " + ui.full.direction + " · " +
                    Math.round(ui.full.el) + "° up" + (ui.full.dark ? "." : " · sky still bright.")
                color: ui.muted
            }
            Rule {}
            Copy { text: "Next moonrise · " + ui.when(ui.lunar?.horizon?.rise?.time) +
                    (ui.lunar?.horizon?.rise ? " · " + ui.lunar.horizon.rise.direction : "") }
            Copy { text: "Next moonset · " + ui.when(ui.lunar?.horizon?.set?.time) +
                    (ui.lunar?.horizon?.set ? " · " + ui.lunar.horizon.set.direction : "") }
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: ui.gutter; Layout.rightMargin: ui.gutter
        spacing: 8
        Tag { text: "DARKER-SKY WINDOWS AROUND FULL MOON"; color: ui.cyan }
        ViewingList { Layout.fillWidth: true; windows: ui.full?.windows || [] }
        Copy {
            visible: ui.named
            text: "Names follow common North American usage. Supermoon and micromoon use the nearest and farthest 10% of the orbit’s distance range around full phase."
            color: ui.muted
            font.pixelSize: 12
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: ui.gutter; Layout.rightMargin: ui.gutter
        spacing: 8
        Tag { text: "NEXT DARKER-SKY WINDOWS"; color: ui.cyan }
        ViewingList { Layout.fillWidth: true; windows: ui.lunar?.nextWindows || [] }
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: ui.gutter; Layout.rightMargin: ui.gutter
        spacing: 7
        Tag { text: "UPCOMING PHASES" }
        Repeater {
            model: ui.lunar?.phases || []
            delegate: Copy {
                required property var modelData
                text: modelData.name + " · " + ui.when(modelData.time) + " local"
            }
        }
    }
    Copy {
        Layout.leftMargin: ui.gutter; Layout.rightMargin: ui.gutter; Layout.bottomMargin: ui.gutter
        text: "Darker-sky windows use Moon ≥5° and Sun ≤−6°. A thin crescent can be hard to spot. Cloud and terrain are not included. Disk shows phase, not its tilt in your sky."
        color: ui.muted
        font.pixelSize: 12
    }
}
