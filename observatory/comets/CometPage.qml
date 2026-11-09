import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: page
    spacing: 14
    property var catalog: null
    property double clock: Date.now()
    readonly property bool available: catalog?.available === true
        && (catalog.fixture || clock < Date.parse(catalog.until))
    Timer {
        interval: 30000
        running: page.available && !page.catalog?.fixture
        repeat: true
        onTriggered: page.clock = Date.now()
    }
    property string loadError: ""
    readonly property string tool: Quickshell.env("OMASKY_COMETS_TOOL")
    Component.onCompleted: if (tool && snapshot.path) calculate.running = true

    function stamp(value, format) {
        return Qt.formatDateTime(new Date(value), format || "ddd d MMM · HH:mm")
    }
    function span(start, end) {
        const sameDay = new Date(start).toDateString() === new Date(end).toDateString()
        return stamp(start) + " – " + stamp(end, sameDay ? "HH:mm" : "ddd d MMM · HH:mm")
    }
    function optics(tier) {
        switch (tier) {
        case "eye": return qsTr("Naked-eye candidate in dark skies")
        case "binoculars": return qsTr("Binoculars may work in dark skies")
        case "telescope": return qsTr("Telescope · dark sky")
        default: return qsTr("Large telescope or imaging · difficult")
        }
    }
    function coordinates(ra, dec) {
        const minutes = Math.round(ra * 60) % 1440
        const arcminutes = Math.round(Math.abs(dec) * 60)
        return qsTr("Finder (J2000) · RA %1h %2m · Dec %3%4° %5′")
            .arg(Math.floor(minutes / 60)).arg(minutes % 60)
            .arg(dec < 0 ? "−" : "+").arg(Math.floor(arcminutes / 60)).arg(arcminutes % 60)
    }

    component Copy: Text {
        Layout.fillWidth: true
        color: "#eef5ff"
        font.pixelSize: 15
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }

    FileView {
        id: snapshot
        path: Quickshell.env("OMASKY_COMETS")
        printErrors: false
        onLoaded: {
            try { page.catalog = JSON.parse(text()) }
            catch (error) { page.loadError = qsTr("Could not read the comet calculations.") }
        }
        onLoadFailed: if (!page.tool) page.loadError = qsTr("Could not load the comet calculations.")
    }

    Process {
        id: calculate
        command: [page.tool + "/.venv/bin/python", page.tool + "/observatory/comets/comets.py",
            snapshot.path, Quickshell.env("OMASKY_FIXTURE") === "1" ? "fixture" : "live"]
        environment: ({ "OPENBLAS_NUM_THREADS": "1" })
        stderr: StdioCollector { id: diagnostics }
        onExited: function(code) {
            if (code === 0) snapshot.reload()
            else page.loadError = diagnostics.text.trim() || qsTr("Comet calculation unavailable.")
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.margins: 22
        spacing: 8
        Copy {
            text: page.tool ? qsTr("OMANOVA OBSERVATORY  /  NIGHT SKY") : qsTr("OMANOVA OBSERVATORY  /  PREVIEW")
            color: "#70edeb"
            font.pixelSize: 12
            font.letterSpacing: 1.8
        }
        Copy { text: qsTr("Comets"); font.pixelSize: 34; font.bold: true }
        Copy {
            text: page.catalog?.fixture ? qsTr("Nashville test location · fixture")
                : qsTr("Saved observing location · times on your desktop clock")
            color: "#a7b7ce"
        }
        Copy {
            visible: page.available
            text: qsTr("Selected targets through %1. Windows require astronomical darkness and at least 20° elevation. Equipment estimates assume dark skies and use dated reports. A comet’s diffuse glow can be hard to see even with a telescope.")
                .arg(page.catalog?.until ? page.stamp(page.catalog.until, "ddd d MMM · HH:mm") : "")
            color: "#a7b7ce"
        }
        Copy {
            visible: page.available && !page.catalog.targets.some(
                target => target.windows.length && ["eye", "binoculars"].includes(target.equipment))
            text: qsTr("No naked-eye or binocular candidates in this selection.")
            color: "#ffcc7b"
        }
        Copy {
            visible: !!page.loadError || !page.catalog || !page.available
            text: page.loadError || (page.catalog
                ? qsTr("This dated comet snapshot has no current coverage. It needs updated ephemerides and brightness reports.")
                : qsTr("Loading comet windows…"))
            color: "#ffcc7b"
        }
    }

    Repeater {
        model: page.available ? page.catalog.targets : []
        delegate: Rectangle {
            id: card
            required property var modelData
            Layout.fillWidth: true
            Layout.leftMargin: 22
            Layout.rightMargin: 22
            implicitHeight: details.implicitHeight + 36
            color: "#111e31"
            border.color: "#2a3e58"
            radius: 12

            ColumnLayout {
                id: details
                anchors.fill: parent
                anchors.margins: 18
                spacing: 8
                Copy { text: card.modelData.name; font.pixelSize: 23; font.bold: true }
                Copy { text: page.optics(card.modelData.equipment); color: "#ffcc7b" }
                Copy {
                    text: qsTr("Reported magnitude %1 · %2 · %3 UTC")
                        .arg(card.modelData.magnitude.toLocaleString(Qt.locale(), "f", 1))
                        .arg(card.modelData.method === "visual" ? qsTr("visual") : qsTr("CCD"))
                        .arg(card.modelData.observed)
                    color: "#a7b7ce"
                }
                Copy {
                    visible: !card.modelData.windows.length
                    text: qsTr("No dark local window with this comet at least 20° up.")
                }
                Repeater {
                    model: card.modelData.windows
                    delegate: ColumnLayout {
                        id: period
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 4
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#2a3e58" }
                        Copy {
                            text: page.span(period.modelData.start, period.modelData.end)
                            color: "#70edeb"
                        }
                        Copy {
                            text: qsTr("Look around %1 · %2 (%3°) · %4° up")
                                .arg(page.stamp(period.modelData.time, "HH:mm")).arg(period.modelData.direction)
                                .arg(period.modelData.azimuth).arg(period.modelData.altitude)
                            font.bold: true
                        }
                        Copy {
                            text: qsTr("%1 · Moon %2")
                                .arg(page.coordinates(period.modelData.raHours, period.modelData.decDegrees))
                                .arg(period.modelData.moonDown ? qsTr("below horizon")
                                    : qsTr("%1% lit, above horizon").arg(period.modelData.moonPercent))
                            color: "#a7b7ce"
                        }
                    }
                }
                Button {
                    text: qsTr("COBS observations ↗")
                    onClicked: Qt.openUrlExternally("https://cobs.si/obs_list?id=" + card.modelData.cobs)
                }
            }
        }
    }
    Copy {
        visible: page.available
        Layout.margins: 22
        text: qsTr("Positions from JPL Horizons. Brightness from the Comet Observation Database (COBS).")
        color: "#a7b7ce"
    }
}
