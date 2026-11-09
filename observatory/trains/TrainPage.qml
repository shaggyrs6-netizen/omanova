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
    readonly property string tool: Quickshell.env("OMASKY_TRAINS_TOOL")
    Component.onCompleted: if (tool && snapshot.path) calculate.running = true
    property double clock: Date.now()
    readonly property string examplePath: Quickshell.env("OMASKY_TRAINS_EXAMPLE")

    Timer {
        interval: 15000
        repeat: true
        running: !!page.catalog && !page.catalog.fixture
        onTriggered: page.clock = Date.now()
    }
    function activeWindows(batch) {
        return catalog?.fixture ? batch.windows : batch.windows.filter(w => Date.parse(w.end.time) > clock)
    }
    function stamp(value, format) {
        return Qt.formatDateTime(new Date(value), format || "ddd d MMM · HH:mm")
    }
    function position(point) {
        return qsTr("%1 (%2°) · %3° up").arg(point.direction).arg(point.azimuth).arg(point.altitude)
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
        path: page.example && page.examplePath ? page.examplePath : Quickshell.env("OMASKY_TRAINS")
        printErrors: false
        onPathChanged: { page.catalog = null; page.loadError = "" }
        onLoaded: {
            try { page.catalog = JSON.parse(text()) }
            catch (error) { page.loadError = qsTr("Could not read train predictions.") }
        }
        onLoadFailed: if (!page.tool) page.loadError = qsTr("Could not load train predictions.")
    }

    Process {
        id: calculate
        command: [page.tool + "/.venv/bin/python", page.tool + "/observatory/trains/trains.py",
            snapshot.path, page.tool + "/.preview/trains/cache",
            Quickshell.env("OMASKY_FIXTURE") === "1" ? "fixture" : "live"]
        environment: ({ "OPENBLAS_NUM_THREADS": "1" })
        stderr: StdioCollector { id: diagnostics }
        onExited: function(code) {
            if (code === 0) snapshot.reload()
            else page.loadError = diagnostics.text.trim() || qsTr("Train calculation unavailable. Local visibility remains unconfirmed.")
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.margins: 22
        spacing: 8
        Copy {
            text: page.tool ? qsTr("OMASKY OBSERVATORY  /  EXPERIMENTAL") : qsTr("OMASKY OBSERVATORY  /  EXPERIMENTAL PREVIEW")
            color: "#70edeb"
            font.letterSpacing: 1.4
            font.pixelSize: 12
        }
        Copy { text: qsTr("Starlink trains"); font.pixelSize: 34; font.bold: true }
        Copy {
            text: page.catalog?.fixture ? qsTr("SIMULATED EXAMPLE · Nashville · no real train")
                : qsTr("Saved observing location · times on your desktop clock")
            color: page.catalog?.fixture ? "#ffcc7b" : "#a7b7ce"
        }
        Copy {
            text: qsTr("Next 24 hours. A candidate needs at least three individually tracked members of one recent launch, clustered and sunlit at least 15° up against a dark sky. Brightness and actual sightings can vary.")
            color: "#a7b7ce"
        }
        Action {
            visible: !!page.examplePath
            text: page.example ? qsTr("Return to live check") : qsTr("Try a simulated train")
            onClicked: page.example = !page.example
        }
        Copy {
            color: "#ffcc7b"
            visible: !!text
            text: page.loadError || (!page.catalog ? qsTr("Checking launch-linked orbital data…")
                : !page.catalog.recentAvailable ? qsTr("Recent launch data unavailable. Local visibility remains unconfirmed.")
                : !page.catalog.batches.some(batch => page.activeWindows(batch).length)
                    ? qsTr("No potential train windows found in the current data.") : "")
        }
        Copy {
            visible: !!page.catalog
            text: page.catalog ? qsTr("Checked · %1 local").arg(page.stamp(page.catalog.computed)) : ""
            color: "#a7b7ce"
        }
    }

    Repeater {
        model: page.catalog?.batches ?? []
        delegate: Rectangle {
            id: card
            required property var modelData
            readonly property var windows: page.activeWindows(modelData)
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
                Copy { text: card.modelData.name; font.bold: true; font.pixelSize: 22 }
                Copy {
                    visible: !!card.modelData.net
                    text: visible ? (card.modelData.upcoming ? qsTr("Tentative launch · %1 UTC")
                        : qsTr("Launched · %1 local")).arg(card.modelData.upcoming
                            ? card.modelData.net.slice(0, 10) : page.stamp(card.modelData.net)) : ""
                    color: "#a7b7ce"
                }
                Copy {
                    text: card.windows.length ? qsTr("Potential train window")
                        : card.modelData.members < 3 ? qsTr("Local visibility unconfirmed")
                        : qsTr("No qualifying local window")
                    color: card.windows.length ? "#70edeb" : "#ffcc7b"
                    font.bold: true
                }
                Copy {
                    text: card.modelData.windows.length && !card.windows.length
                        ? qsTr("The sampled viewing interval has ended.") : card.modelData.reason
                    color: "#a7b7ce"
                }
                Copy {
                    visible: !card.modelData.upcoming
                    text: qsTr("Individually tracked members used · %1").arg(card.modelData.members)
                    color: "#a7b7ce"
                }
                Repeater {
                    model: card.windows
                    delegate: ColumnLayout {
                        id: viewing
                        required property var modelData
                        Layout.fillWidth: true
                        Copy {
                            text: qsTr("Sampled window · %1 – %2")
                                .arg(page.stamp(viewing.modelData.start.time, "ddd d MMM · HH:mm:ss"))
                                .arg(page.stamp(viewing.modelData.end.time, "HH:mm:ss"))
                            color: "#70edeb"
                        }
                        Copy {
                            text: qsTr("Start %1 · finish %2")
                                .arg(page.position(viewing.modelData.start)).arg(page.position(viewing.modelData.end))
                        }
                        Copy {
                            text: qsTr("Look around %1 · %2 · %3 members in the group")
                                .arg(page.stamp(viewing.modelData.best.time, "HH:mm:ss"))
                                .arg(page.position(viewing.modelData.best)).arg(viewing.modelData.best.count)
                            font.bold: true
                        }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    Action {
                        visible: !!card.modelData.source
                        text: qsTr("Launch source ↗")
                        onClicked: Qt.openUrlExternally(card.modelData.source)
                    }
                    Action {
                        visible: !!card.modelData.orbitSource
                        text: qsTr("CelesTrak launch match ↗")
                        onClicked: Qt.openUrlExternally(card.modelData.orbitSource)
                    }
                }
            }
        }
    }
    Item { implicitHeight: 12 }
}
