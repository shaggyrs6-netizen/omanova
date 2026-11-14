import "./qml/Omanova" as App
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: page
    spacing: 14
    property var catalog: null
    property string loadError: ""
    readonly property string tool: Quickshell.env("OMASKY_SATELLITES_TOOL")
    Component.onCompleted: if (tool && snapshot.path) calculate.running = true
    property double clock: Date.now()
    readonly property var visibleWindows: (catalog?.windows ?? []).filter(window =>
        (filter.currentIndex <= 0 || window.number === filter.currentValue)
        && (catalog.fixture || Date.parse(window.end.time) > clock))

    Timer {
        running: !!page.catalog && !page.catalog.fixture
        interval: 15000
        repeat: true
        onTriggered: page.clock = Date.now()
    }
    function stamp(value, format) {
        return Qt.formatDateTime(new Date(value), format || "ddd d MMM · HH:mm")
    }
    function position(point) {
        return qsTr("%1 (%2°) · %3° up").arg(point.direction).arg(Math.round(point.az)).arg(Math.round(point.el))
    }

    component Copy: Text {
        Layout.fillWidth: true
        color: App.Palette.ink
        font.pixelSize: 15
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }
    FileView {
        id: snapshot
        path: Quickshell.env("OMASKY_SATELLITES")
        printErrors: false
        onLoaded: {
            try { page.catalog = JSON.parse(text()) }
            catch (error) { page.loadError = qsTr("Could not read the satellite predictions.") }
        }
        onLoadFailed: if (!page.tool) page.loadError = qsTr("Could not load the satellite predictions.")
    }

    Process {
        id: calculate
        command: [page.tool + "/.venv/bin/python", page.tool + "/observatory/satellites/watchlist.py",
            snapshot.path, page.tool + "/.preview/satellites/cache",
            Quickshell.env("OMASKY_FIXTURE") === "1" ? "fixture" : "live"]
        environment: ({ "OPENBLAS_NUM_THREADS": "1" })
        stderr: StdioCollector { id: diagnostics }
        onExited: function(code) {
            if (code === 0) snapshot.reload()
            else page.loadError = diagnostics.text.trim() || qsTr("Watchlist calculation unavailable.")
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.margins: 22
        spacing: 8
        Copy {
            text: page.tool ? qsTr("OMANOVA OBSERVATORY  /  NIGHT SKY") : qsTr("OMANOVA OBSERVATORY  /  PREVIEW")
            color: App.Palette.accent
            font.letterSpacing: 1.6
            font.pixelSize: 12
        }
        Copy { text: qsTr("Bright satellite watchlist"); font.pixelSize: 34; font.bold: true }
        Copy {
            text: page.catalog?.fixture ? qsTr("Nashville sample location · frozen orbital data")
                : qsTr("Saved observing location · times on your desktop clock")
            color: App.Palette.muted
        }
        Copy {
            text: qsTr("Next three days. Windows show sunlit passes at least 10° up with the Sun at least 6° below your horizon. Actual brightness varies with orientation and distance. Clouds and skyglow can hide a pass.")
            color: App.Palette.muted
        }
        ComboBox {
            id: filter
            Layout.preferredWidth: Math.min(280, page.width - 44)
            Accessible.name: qsTr("Filter by satellite")
            model: [{ name: qsTr("All watchlist satellites"), number: 0 }].concat(page.catalog?.targets ?? [])
            textRole: "name"
            valueRole: "number"
            palette.base: App.Palette.surface
            palette.button: App.Palette.button
            palette.text: App.Palette.ink
            palette.buttonText: App.Palette.ink
            palette.window: App.Palette.surface
            palette.windowText: App.Palette.ink
        }
        Copy {
            readonly property var missing: (page.catalog?.targets ?? []).filter(target => !target.usable)
            visible: missing.length > 0
            text: qsTr("Current elements unavailable for %1.").arg(missing.map(target => target.name).join(", "))
            color: App.Palette.warning
        }
        Copy {
            visible: !!page.catalog && !page.catalog.fixture
            text: page.catalog?.error ? qsTr("Feed refresh issue · %1. Only usable cached elements are shown.").arg(page.catalog.error)
                : !page.catalog?.online ? qsTr("Orbital downloads paused. Using any usable cached elements.")
                : page.catalog?.fetched ? qsTr("Orbital feed fetched · %1 local").arg(page.stamp(page.catalog.fetched)) : ""
            color: App.Palette.muted
        }
        Copy {
            visible: !!page.loadError || !page.catalog || !page.visibleWindows.length
            text: page.loadError || (!page.catalog ? qsTr("Loading passes…") : qsTr("No upcoming viewing windows for this selection."))
            color: App.Palette.warning
        }
    }

    Repeater {
        model: page.visibleWindows
        delegate: Rectangle {
            id: card
            required property var modelData
            Layout.fillWidth: true
            Layout.leftMargin: 22
            Layout.rightMargin: 22
            implicitHeight: details.implicitHeight + 32
            color: App.Palette.surface
            border.color: App.Palette.line
            radius: 12

            ColumnLayout {
                id: details
                anchors.fill: parent
                anchors.margins: 16
                spacing: 6
                Copy { text: card.modelData.name; font.pixelSize: 22; font.bold: true }
                Copy {
                    text: qsTr("Look from %1 to %2")
                        .arg(page.stamp(card.modelData.start.time, "ddd d MMM · HH:mm:ss"))
                        .arg(page.stamp(card.modelData.end.time, "HH:mm:ss"))
                    color: App.Palette.accent
                }
                Copy { text: qsTr("Start · %1").arg(page.position(card.modelData.start)) }
                Copy {
                    text: qsTr("Highest visible point · %1 · %2")
                        .arg(page.stamp(card.modelData.peak.time, "HH:mm:ss")).arg(page.position(card.modelData.peak))
                }
                Copy { text: qsTr("Finish · %1").arg(page.position(card.modelData.end)); color: App.Palette.muted }
                Copy {
                    text: qsTr("NORAD %1 · Elements %2 local")
                        .arg(card.modelData.number).arg(page.stamp(card.modelData.epoch))
                    color: App.Palette.muted
                    font.pixelSize: 13
                }
            }
        }
    }
    Button {
        Layout.leftMargin: 22
        Layout.bottomMargin: 18
        visible: !!page.catalog
        text: qsTr("CelesTrak bright-object catalogue ↗")
        onClicked: Qt.openUrlExternally(page.catalog.source)
    }
}
