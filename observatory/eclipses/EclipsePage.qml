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
    readonly property string tool: Quickshell.env("OMASKY_ECLIPSES_TOOL")
    Component.onCompleted: if (tool && snapshot.path) calculate.running = true

    function when(stamp, format) {
        return Qt.formatDateTime(new Date(stamp), format || "ddd d MMM yyyy · HH:mm")
    }
    function span(first, last) {
        const sameDay = new Date(first).toDateString() === new Date(last).toDateString()
        return when(first) + " – " + when(last, sameDay ? "HH:mm" : "ddd d MMM · HH:mm")
    }
    function phaseName(kind) {
        switch (kind) {
        case "total": return qsTr("Total")
        case "annular": return qsTr("Annular")
        case "partial": return qsTr("Partial")
        default: return qsTr("Penumbral")
        }
    }

    component Copy: Text {
        Layout.fillWidth: true
        color: "#eef5ff"
        font.pixelSize: 15
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }
    component Section: Copy {
        Layout.leftMargin: 22
        Layout.rightMargin: 22
        font.pixelSize: 23
        font.bold: true
    }
    component WindowRows: ColumnLayout {
        id: rows
        property string label
        property var windows: []
        Layout.fillWidth: true
        spacing: 4
        Repeater {
            model: rows.windows
            delegate: Copy {
                required property var modelData
                text: qsTr("%1 · %2").arg(rows.label).arg(page.span(modelData.start, modelData.end))
                color: "#70edeb"
            }
        }
    }
    component EclipseCard: Rectangle {
        id: card
        required property var modelData
        property bool solar: false
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
            spacing: 7
            Copy {
                text: qsTr("%1 · %2").arg(page.phaseName(card.modelData.kind))
                    .arg(page.when(card.modelData.look.time, "ddd d MMM yyyy"))
                font.pixelSize: 21
                font.bold: true
            }
            Copy {
                text: card.solar ? qsTr("Local maximum · %1").arg(page.when(card.modelData.peak))
                    : qsTr("Greatest eclipse · %1").arg(page.when(card.modelData.peak))
                color: "#a7b7ce"
            }
            WindowRows { label: qsTr("Visible window"); windows: card.modelData.visible }
            WindowRows {
                label: qsTr("Moon in the darker shadow")
                windows: card.modelData.partial ?? []
                visible: windows.length > 0
            }
            WindowRows {
                label: card.modelData.kind === "annular" ? qsTr("Annularity visible") : qsTr("Totality visible")
                windows: card.modelData.central
                visible: windows.length > 0
            }
            Copy {
                text: qsTr("Look around %1 · %2 (%3°) · %4° up")
                    .arg(page.when(card.modelData.look.time, "HH:mm"))
                    .arg(card.modelData.look.direction).arg(card.modelData.look.azimuth)
                    .arg(Math.max(0, card.modelData.look.altitude))
                font.bold: true
            }
            Copy {
                visible: card.solar
                text: card.solar ? qsTr("%1% of the Sun’s disc covered at that time.")
                    .arg(card.modelData.coverage.toLocaleString(Qt.locale(), "f", 1)) : ""
            }
            Copy {
                visible: !card.solar && card.modelData.kind === "penumbral"
                text: qsTr("Expect subtle shading on the Moon. Twilight and haze can make it harder to notice.")
                color: "#a7b7ce"
            }
            Copy {
                visible: card.modelData.look.altitude <= 5
                text: qsTr("Low on the horizon. You’ll need a clear view in that direction.")
                color: "#ffcc7b"
            }
        }
    }

    FileView {
        id: snapshot
        path: Quickshell.env("OMASKY_ECLIPSES")
        printErrors: false
        onLoaded: {
            try { page.catalog = JSON.parse(text()) }
            catch (error) { page.loadError = qsTr("Could not read eclipse predictions.") }
        }
        onLoadFailed: if (!page.tool) page.loadError = qsTr("Could not load eclipse predictions.")
    }

    Process {
        id: calculate
        command: [page.tool + "/.venv/bin/python", page.tool + "/observatory/eclipses/eclipses.py",
            snapshot.path, Quickshell.env("OMASKY_FIXTURE") === "1" ? "fixture" : "live"]
        environment: ({ "OPENBLAS_NUM_THREADS": "1" })
        stderr: StdioCollector { id: diagnostics }
        onExited: function(code) {
            if (code === 0) snapshot.reload()
            else page.loadError = diagnostics.text.trim() || qsTr("Eclipse calculation unavailable.")
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
        Copy { text: qsTr("Eclipses"); font.pixelSize: 34; font.bold: true }
        Copy {
            text: page.catalog?.fixture ? qsTr("Nashville test location · fixture")
                : qsTr("Saved observing location · times on your desktop clock")
            color: "#a7b7ce"
        }
        Copy {
            text: qsTr("Local solar and lunar eclipses through 2029. The viewing windows account for sunrise, sunset, moonrise and moonset on an unobstructed horizon. Times are approximate.")
            color: "#a7b7ce"
        }
        Copy {
            visible: !page.catalog
            text: page.loadError || qsTr("Loading eclipse predictions…")
        }
    }

    Section { text: qsTr("Solar eclipses") }
    Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 22
        Layout.rightMargin: 22
        implicitHeight: safety.implicitHeight + 32
        radius: 12
        color: "#281e1d"
        border.color: "#795443"
        ColumnLayout {
            id: safety
            anchors.fill: parent
            anchors.margins: 16
            spacing: 7
            Copy { text: qsTr("Solar viewing safety"); font.bold: true; color: "#ffcc7b" }
            Copy {
                text: qsTr("Use ISO 12312-2 eclipse glasses or a safe handheld solar viewer throughout partial or annular phases. Sunglasses are unsafe. Cameras, binoculars and telescopes require a purpose-made solar filter over the front of the optics.")
            }
            Button {
                text: qsTr("NASA eclipse safety ↗")
                onClicked: Qt.openUrlExternally("https://science.nasa.gov/eclipses/safety/")
            }
        }
    }
    Repeater {
        model: page.catalog?.solar ?? []
        delegate: EclipseCard { solar: true }
    }
    Copy {
        Layout.leftMargin: 22
        Layout.rightMargin: 22
        visible: !!page.catalog && !page.catalog.solar.length
        text: qsTr("No visible solar eclipses in this forecast.")
    }

    Section { text: qsTr("Lunar eclipses") }
    Copy {
        Layout.leftMargin: 22
        Layout.rightMargin: 22
        text: qsTr("Lunar eclipses are safe to watch with the naked eye.")
        color: "#a7b7ce"
    }
    Repeater {
        model: page.catalog?.lunar ?? []
        delegate: EclipseCard {}
    }
    Copy {
        Layout.leftMargin: 22
        Layout.rightMargin: 22
        visible: !!page.catalog && !page.catalog.lunar.length
        text: qsTr("No visible lunar eclipses in this forecast.")
    }
    Item { implicitHeight: 12 }
}
