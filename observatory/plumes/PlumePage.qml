import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: page
    spacing: 14
    property var catalog: null
    property bool example: false
    property string loadError: ""
    readonly property string tool: Quickshell.env("OMASKY_PLUMES_TOOL")
    property double wallTime: Date.now()
    readonly property bool fresh: catalog?.fresh === true
        && (catalog.fixture || wallTime - Date.parse(catalog.fetched) <= 7200000)
    Component.onCompleted: if (tool && snapshot.path) calculate.running = true

    Timer {
        interval: 30000
        running: !!page.catalog && !page.catalog.fixture
        repeat: true
        onTriggered: page.wallTime = Date.now()
    }
    readonly property string examplePath: Quickshell.env("OMASKY_PLUME_EXAMPLE")
    readonly property int candidates: catalog?.launches.filter(page.hasCandidate).length ?? 0

    function hasCandidate(launch) {
        return fresh && launch.verdict === "possible"
            && (catalog.fixture || launch.windows.some(window => Date.parse(window.end.time) > wallTime))
    }
    function stamp(value, format) {
        return Qt.formatDateTime(new Date(value), format || "ddd d MMM · HH:mm")
    }
    function direction(point) {
        return qsTr("%1 (%2°) · %3° up").arg(point.direction).arg(point.azimuth).arg(point.altitude)
    }
    function launchTime(launch) {
        if (!launch.net) return qsTr("Launch time unavailable")
        if (["SEC", "MIN"].includes(launch.precision))
            return qsTr("Scheduled · %1 local").arg(stamp(launch.net))
        if (launch.precision === "HR") return qsTr("Approximate hour · %1 local").arg(stamp(launch.net))
        return qsTr("Tentative date · %1 UTC").arg(launch.net.slice(0, 10))
    }

    component Copy: Text {
        Layout.fillWidth: true
        color: "#eef5ff"
        font.pixelSize: 15
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }
    component Action: Button {
        id: action
        implicitHeight: 35
        leftPadding: 12
        rightPadding: 12
        contentItem: Text {
            text: action.text
            color: "#eef5ff"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: 14
        }
        background: Rectangle {
            radius: 6
            color: action.hovered ? "#1a3049" : "#15253c"
            border.color: action.visualFocus ? "#70edeb" : "#36516d"
        }
    }

    FileView {
        id: snapshot
        path: page.example && page.examplePath ? page.examplePath : Quickshell.env("OMASKY_PLUMES")
        printErrors: false
        onPathChanged: { page.catalog = null; page.loadError = "" }
        onLoaded: {
            try { page.catalog = JSON.parse(text()) }
            catch (error) { page.loadError = qsTr("Could not read the plume results.") }
        }
        onLoadFailed: if (!page.tool) page.loadError = qsTr("Could not load the plume results.")
    }

    Process {
        id: calculate
        command: [page.tool + "/.venv/bin/python", page.tool + "/observatory/plumes/plumes.py",
            snapshot.path, Quickshell.env("OMASKY_PLUMES_SCHEDULE"),
            Quickshell.env("OMASKY_FIXTURE") === "1" ? "fixture" : "live"]
        environment: ({ "OPENBLAS_NUM_THREADS": "1" })
        stderr: StdioCollector { id: diagnostics }
        onExited: function(code) {
            if (code === 0) snapshot.reload()
            else page.loadError = diagnostics.text.trim() || qsTr("Plume calculation unavailable.")
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.margins: 22
        spacing: 8
        Copy {
            text: page.tool ? qsTr("OMASKY OBSERVATORY  /  EXPERIMENTAL") : qsTr("OMASKY OBSERVATORY  /  EXPERIMENTAL PREVIEW")
            color: "#70edeb"
            font.pixelSize: 12
            font.letterSpacing: 1.6
        }
        Copy { text: qsTr("Twilight launch plumes"); font.pixelSize: 34; font.bold: true }
        Copy {
            text: page.catalog?.fixture
                ? qsTr("SIMULATED EXAMPLE · Nashville sample location · no real launch")
                : qsTr("Saved observing location · times on your desktop clock")
            color: page.catalog?.fixture ? "#ffcc7b" : "#a7b7ce"
        }
        Copy {
            text: qsTr("A potential window needs a timed exhaust track, sunlit exhaust at least 5° above your horizon, and the Sun at least 6° below it. Geometry alone can’t predict plume brightness, clouds or how long a plume will linger.")
            color: "#a7b7ce"
        }
        Action {
            visible: !!page.examplePath
            text: page.example ? qsTr("Return to live schedule") : qsTr("Try a simulated viewing window")
            onClicked: page.example = !page.example
        }
        Copy {
            color: page.candidates ? "#70edeb" : "#ffcc7b"
            text: page.loadError || (!page.catalog ? qsTr("Loading launch schedule…")
                : !page.fresh ? qsTr("Schedule unavailable or stale. Visibility remains unconfirmed.")
                : page.candidates ? qsTr("%n potential viewing window candidate(s)", "", page.candidates)
                : qsTr("No upcoming launch has enough evidence for a local viewing window."))
        }
        Copy {
            visible: !!page.catalog?.fetched
            text: visible ? qsTr("Schedule snapshot · %1 local").arg(page.stamp(page.catalog.fetched)) : ""
            color: "#a7b7ce"
        }
    }

    Repeater {
        model: page.catalog?.launches ?? []
        delegate: Rectangle {
            id: card
            required property var modelData
            readonly property bool possible: page.hasCandidate(modelData)
            Layout.fillWidth: true
            Layout.leftMargin: 22
            Layout.rightMargin: 22
            implicitHeight: details.implicitHeight + 34
            color: "#111e31"
            border.color: "#2a3e58"
            radius: 12
            ColumnLayout {
                id: details
                anchors.fill: parent
                anchors.margins: 17
                spacing: 7
                Copy { text: card.modelData.name; font.pixelSize: 21; font.bold: true }
                Copy {
                    text: [card.modelData.site, card.modelData.region, card.modelData.status]
                        .filter(Boolean).join(" · ")
                    color: "#a7b7ce"
                }
                Copy { text: page.launchTime(card.modelData) }
                Copy {
                    visible: card.modelData.sunAltitude !== undefined
                    text: visible ? qsTr("Local Sun at scheduled liftoff · %1° elevation")
                        .arg(card.modelData.sunAltitude.toLocaleString(Qt.locale(), "f", 1)) : ""
                    color: "#a7b7ce"
                }
                Copy {
                    text: card.possible ? qsTr("Potential plume window") : qsTr("Local visibility unconfirmed")
                    color: card.possible ? "#70edeb" : "#ffcc7b"
                    font.bold: true
                }
                Copy {
                    text: !page.fresh ? qsTr("Launch schedule is stale or unavailable.")
                        : card.modelData.verdict === "possible" && !card.possible
                            ? qsTr("The sampled viewing interval has ended.")
                            : card.modelData.reason
                    color: "#a7b7ce"
                }
                Repeater {
                    model: card.possible ? card.modelData.windows : []
                    delegate: ColumnLayout {
                        id: row
                        required property var modelData
                        Layout.fillWidth: true
                        Copy {
                            text: qsTr("Sampled interval · %1 – %2 local")
                                .arg(page.stamp(row.modelData.start.time, "ddd d MMM · HH:mm:ss"))
                                .arg(page.stamp(row.modelData.end.time, "HH:mm:ss"))
                            color: "#70edeb"
                        }
                        Copy {
                            text: qsTr("Start %1 · highest %2 · finish %3")
                                .arg(page.direction(row.modelData.start)).arg(page.direction(row.modelData.highest))
                                .arg(page.direction(row.modelData.end))
                        }
                        Copy {
                            text: qsTr("Times assume liftoff at the scheduled time. A slip changes the window.")
                            color: "#a7b7ce"
                        }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    Action {
                        visible: !!card.modelData.source
                        text: qsTr("Schedule source ↗")
                        onClicked: Qt.openUrlExternally(card.modelData.source)
                    }
                    Action {
                        visible: !!card.modelData.trackSource
                        text: qsTr("Trajectory source ↗")
                        onClicked: Qt.openUrlExternally(card.modelData.trackSource)
                    }
                }
            }
        }
    }
    Item { implicitHeight: 12 }
}
