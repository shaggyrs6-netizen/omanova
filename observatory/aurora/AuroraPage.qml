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
    readonly property bool embedded: Quickshell.env("OMASKY_AURORA_EMBEDDED") === "1"
    Component.onCompleted: if (embedded && snapshot.path) refresh.running = true
    property double clock: Date.now()
    readonly property string examplePath: Quickshell.env("OMASKY_AURORA_EXAMPLE")
    readonly property var current: catalog?.current
    readonly property bool expired: !!current?.valid && !catalog.fixture
        && clock > Date.parse(current.valid) + 600000
    readonly property string verdict: expired ? "uncertain" : current?.verdict ?? "uncertain"

    function stamp(value, format) {
        return Qt.formatDateTime(new Date(value), format || "ddd d MMM · HH:mm")
    }
    function span(first, last) {
        const sameDay = new Date(first).toDateString() === new Date(last).toDateString()
        return stamp(first) + " – " + stamp(last, sameDay ? "HH:mm" : "ddd d MMM · HH:mm")
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
            color: action.enabled ? "#eef5ff" : "#8190a6"
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
    component Card: Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 22
        Layout.rightMargin: 22
        color: "#111e31"
        border.color: "#2a3e58"
        radius: 12
    }

    Timer {
        interval: 15000
        repeat: true
        running: !!page.catalog && !page.catalog.fixture
        onTriggered: page.clock = Date.now()
    }
    FileView {
        id: snapshot
        path: page.example && page.examplePath ? page.examplePath : Quickshell.env("OMASKY_AURORA")
        printErrors: false
        onPathChanged: { page.catalog = null; page.loadError = "" }
        onLoaded: {
            try { page.catalog = JSON.parse(text()); page.clock = Date.now() }
            catch (error) { page.loadError = qsTr("Could not read aurora data.") }
        }
        onLoadFailed: if (!page.embedded) page.loadError = qsTr("Could not load aurora data.")
    }
    Process {
        id: refresh
        readonly property string tool: Quickshell.env("OMASKY_AURORA_TOOL")
        command: [tool + "/.venv/bin/python", tool + "/observatory/aurora/aurora.py",
            Quickshell.env("OMASKY_AURORA"), tool + "/.preview/aurora/cache", Quickshell.env("OMASKY_AURORA_MODE")]
        environment: ({ "OPENBLAS_NUM_THREADS": "1" })
        stderr: StdioCollector { id: diagnostics }
        onExited: function(code) {
            if (code === 0) { page.loadError = ""; snapshot.reload() }
            else page.loadError = diagnostics.text.trim() || qsTr("Refresh failed.")
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.margins: 22
        spacing: 8
        Copy { text: page.embedded ? qsTr("OMANOVA OBSERVATORY  /  SPACE WEATHER") : qsTr("OMANOVA OBSERVATORY  /  PREVIEW"); color: "#70edeb"; font.letterSpacing: 1.5; font.pixelSize: 12 }
        Copy { text: qsTr("Aurora"); font.pixelSize: 34; font.bold: true }
        Copy {
            text: page.catalog?.fixture ? qsTr("SIMULATED STORM · Nashville · no real alert")
                : qsTr("Saved observing location · times on your desktop clock")
            color: page.catalog?.fixture ? "#ffcc7b" : "#a7b7ce"
        }
        Flow {
            Layout.fillWidth: true
            spacing: 8
            Action {
                visible: !!page.examplePath
                enabled: !refresh.running
                text: page.example ? qsTr("Return to live forecast") : qsTr("Try a simulated storm")
                onClicked: page.example = !page.example
            }
            Action {
                visible: !page.example && Quickshell.env("OMASKY_AURORA_MODE") === "live"
                enabled: !refresh.running && page.catalog?.enabled !== false
                text: refresh.running ? qsTr("Refreshing…") : qsTr("Refresh forecast")
                onClicked: refresh.running = true
            }
        }
        Copy {
            visible: !page.catalog?.fixture && page.catalog?.enabled === false
            text: qsTr("Aurora downloads paused · Showing any usable cached guidance. Enable in Settings.")
            color: "#ffcc7b"
        }
        Copy {
            visible: !!page.loadError || !!page.catalog?.issues.length
            text: page.loadError || qsTr("Feed refresh issue · %1").arg(page.catalog?.issues.join(", ") ?? "")
            color: "#ffcc7b"
        }
    }

    Card {
        implicitHeight: nearTerm.implicitHeight + 34
        ColumnLayout {
            id: nearTerm
            anchors.fill: parent
            anchors.margins: 17
            spacing: 8
            Copy { text: qsTr("Near-term outlook"); font.pixelSize: 22; font.bold: true }
            Copy {
                text: refresh.running && !page.catalog ? qsTr("Checking NOAA guidance…")
                    : page.verdict === "possible" ? qsTr("Possible from here · visibility uncertain")
                    : page.verdict === "daylight" ? qsTr("Sky too bright at the forecast time")
                    : page.verdict === "unlikely" ? qsTr("Unlikely from here in this model run")
                    : qsTr("Visibility uncertain · fresh local model guidance unavailable")
                color: page.verdict === "possible" ? "#70edeb" : "#ffcc7b"
                font.bold: true
            }
            Copy {
                visible: !!page.current?.valid
                text: visible ? qsTr("Model valid around %1").arg(page.stamp(page.current.valid)) : ""
                color: "#a7b7ce"
            }
            Copy {
                visible: page.verdict === "possible" && !!page.current?.look
                text: visible ? qsTr("Look %1 (%2°), around %3° above a clear horizon.")
                    .arg(page.current.look.direction).arg(page.current.look.bearing).arg(page.current.look.elevation) : ""
                font.bold: true
            }
            Copy {
                text: qsTr("The NOAA model shows where the aurora may occur. This view checks whether part of it could be above your horizon in darkness. Clouds, skyglow and aurora height can change what you see.")
                color: "#a7b7ce"
            }
            Action {
                text: qsTr("NOAA aurora forecast ↗")
                onClicked: Qt.openUrlExternally("https://www.swpc.noaa.gov/products/aurora-30-minute-forecast")
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 22
        Layout.rightMargin: 22
        Copy { text: qsTr("After dark · next three nights"); font.pixelSize: 22; font.bold: true }
        Copy {
            text: qsTr("Kp is a global activity forecast. These times are for checking the next local model run. Kp alone gives no local sighting prediction.")
            color: "#a7b7ce"
        }
    }
    Repeater {
        model: page.catalog?.nights ?? []
        delegate: Card {
            id: night
            required property var modelData
            implicitHeight: nightDetails.implicitHeight + 32
            ColumnLayout {
                id: nightDetails
                anchors.fill: parent
                anchors.margins: 16
                spacing: 6
                Copy {
                    text: qsTr("Dark sky · %1").arg(page.span(night.modelData.start, night.modelData.end))
                    color: "#70edeb"
                    font.bold: true
                }
                Copy {
                    text: night.modelData.kp === null ? qsTr("No Kp guidance for this night")
                        : qsTr("Highest Kp in the dark hours · %1 · %2")
                            .arg(night.modelData.kp.toLocaleString(Qt.locale(), "f", 1))
                            .arg(page.span(night.modelData.kpStart, night.modelData.kpEnd))
                }
                Copy { text: qsTr("Local visibility uncertain until a fresh near-term model covers this time."); color: "#a7b7ce" }
            }
        }
    }
    Item { implicitHeight: 12 }
}
