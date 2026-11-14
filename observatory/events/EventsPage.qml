import "./qml/Omanova" as App
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: page
    required property var sky
    property int mode: 0
    property var launchFeed: null
    signal inspect(string eventId)
    spacing: 14

    readonly property color ink: App.Palette.ink
    readonly property color muted: App.Palette.muted
    readonly property color accent: App.Palette.accent
    readonly property color amber: App.Palette.warning
    readonly property color line: App.Palette.line
    readonly property int gutter: width < 620 ? 16 : 30
    readonly property bool stale: sky.snapshotStale
    readonly property bool launchStale: launchFeed && launchFeed.fetched &&
        sky.now - Date.parse(launchFeed.fetched) >= 7200000
    readonly property var stations: sky.events.map(event => {
        const window = sky.bestWindow(event)
        const weather = window?.conditions
        const orbitStale = event.confidence === "Stale orbit"
        const local = window && !orbitStale && weather?.label !== "Poor"
        const badge = orbitStale ? "STALE ORBIT" : page.stale ? "DATA STALE" : !window ? "NO VIEWING WINDOW" :
            weather?.label === "Poor" ? "POOR CONDITIONS" :
            weather?.label === "Favourable" ? "POTENTIALLY VISIBLE" :
            weather?.label === "Mixed" ? "POSSIBLE · MIXED WEATHER" : "POSSIBLE · WEATHER UNKNOWN"
        return { event, window, local, badge,
            reason: orbitStale ? "Orbital elements are too old for a viewing recommendation." :
                page.stale ? "Refresh or check the foreground worker." :
                !window ? event.reason : weather?.reason || event.reason,
            sortTime: Date.parse(window?.start.time || event.start) }
    }).sort((a, b) => a.sortTime - b.sortTime)
    readonly property var rows: mode === 2 ? (launchFeed?.launches || []) :
        mode === 1 ? stations : stations.filter(row => row.local)

    FileView {
        id: launchFile
        watchChanges: true
        onFileChanged: reload()
        path: Quickshell.env("OMASKY_EVENTS")
        printErrors: false
        onLoaded: {
            try {
                const payload = JSON.parse(text())
                if (Array.isArray(payload.launches)) page.launchFeed = payload
            } catch (error) {
                page.launchFeed = null
            }
        }
    }

    Timer {
        interval: 1500
        running: page.launchFeed === null && !page.sky.fixture
        repeat: true
        onTriggered: launchFile.reload()
    }

    function when(value, timeOnly) {
        return value ? Qt.formatDateTime(new Date(value), timeOnly ? "HH:mm" : "ddd d MMM · HH:mm") : "Time unavailable"
    }
    function interval(start, end) {
        const startLabel = when(start, false)
        const endLabel = when(end, false)
        if (startLabel === endLabel)
            return startLabel + ":" + Qt.formatDateTime(new Date(start), "ss") + "–" +
                Qt.formatDateTime(new Date(end), "HH:mm:ss")
        const sameDay = new Date(start).toDateString() === new Date(end).toDateString()
        return startLabel + "–" + when(end, sameDay)
    }
    function launchTime(row) {
        if (!row.net) return "Time not announced"
        if (["SEC", "MIN"].includes(row.precision)) return when(row.net, false) + " local"
        if (row.precision === "HR") return "Around " + when(row.net, false) + " local · Hour estimate"
        if (row.precision === "DAY") return row.net.slice(0, 10) + " UTC · Time TBD"
        if (row.precision === "MTH") return row.net.slice(0, 7) + " · Month only"
        if (row.precision === "YR") return row.net.slice(0, 4) + " · Year only"
        return "Time not confirmed"
    }
    function launchCountdown(row) {
        const remaining = Date.parse(row.net) - sky.now
        return row.statusId === 1 && ["SEC", "MIN"].includes(row.precision) && remaining > 0 &&
            remaining < 86400000 && !launchStale && !launchFeed?.error &&
            (launchFeed?.fixture || launchFeed?.enabled === true) ? "T−" + sky.countdown(row.net) : ""
    }
    function summary() {
        return JSON.stringify({ mode, count: rows.length, sample: launchFeed?.fixture,
            states: mode === 2 ? rows.map(row => row.status) : rows.map(row => row.badge) })
    }

    component Copy: Text {
        Layout.fillWidth: true
        color: page.ink
        font.family: "sans-serif"
        font.pixelSize: 14
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }
    component Tag: Copy {
        color: page.muted
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.letterSpacing: 0.8
    }
    component LinkButton: Button {
        id: button
        focusPolicy: Qt.StrongFocus
        hoverEnabled: true
        leftPadding: 11
        rightPadding: 11
        implicitHeight: 36
        contentItem: Text {
            text: button.text
            textFormat: Text.PlainText
            color: page.ink
            font.pixelSize: 13
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
        }
        background: Rectangle {
            radius: 6
            color: button.down || button.hovered ? App.Palette.surface : App.Palette.surface
            border.color: button.visualFocus ? page.accent : page.line
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.margins: page.gutter
        Layout.bottomMargin: 0
        spacing: 8
        Tag { text: "04 / MISSION SCHEDULE"; color: page.accent }
        Copy { text: "Events"; font.pixelSize: page.width < 620 ? 32 : 42; font.weight: Font.DemiBold }
        Copy {
            text: "Local station passes and worldwide launches"
            color: page.muted
        }
        Flow {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: ["Local opportunities", "All station passes", "Rocket launches"]
                delegate: LinkButton {
                    required property string modelData
                    required property int index
                    text: (page.mode === index ? "●  " : "") + modelData
                    Accessible.description: page.mode === index ? "Selected filter" : ""
                    onClicked: page.mode = index
                }
            }
        }
        Copy {
            color: page.mode === 2 && (page.launchStale || page.launchFeed?.error) ? page.amber :
                page.mode !== 2 && page.stale ? page.amber : page.muted
            text: page.mode === 2
                ? (page.launchFeed?.fixture ? "Sample launches. Local visibility is unconfirmed."
                    : page.launchFeed?.enabled === false ? (page.launchFeed.fetched
                        ? "Launch downloads paused · Cached " + page.when(page.launchFeed.fetched, false) + " local"
                        : "Launch downloads paused · Enable in Settings.")
                    : page.launchFeed?.error ? "Launch feed unavailable. " +
                        (page.launchFeed.fetched ? "Showing cached schedules." : "No cached schedule.")
                    : page.launchStale ? "Cached launch schedule. Confirm times with the provider."
                    : page.launchFeed?.fetched ? "Launch Library 2 · Updated " + page.when(page.launchFeed.fetched, false) + " local"
                    : "Launch schedule unavailable.")
                : page.stale ? "Cached station snapshot. Restart the foreground worker for updates."
                : page.mode === 0 ? "Sunlit passes in darker skies. Weather may still prevent a sighting."
                : "Includes passes that are too low, in daylight or in Earth’s shadow."
        }
    }

    Copy {
        visible: !page.rows.length
        Layout.leftMargin: page.gutter
        Layout.rightMargin: page.gutter
        text: page.mode === 2 ? "No upcoming launches available." : page.mode === 0 ?
            "No local viewing opportunities in the current prediction window." : "No station passes available."
        color: page.muted
    }

    Repeater {
        model: page.rows
        delegate: Rectangle {
            id: card
            required property var modelData
            readonly property bool launch: page.mode === 2
            readonly property var row: modelData
            readonly property var event: launch ? null : row.event
            readonly property var view: launch ? null : row.window
            Layout.fillWidth: true
            Layout.leftMargin: page.gutter
            Layout.rightMargin: page.gutter
            implicitHeight: details.implicitHeight + 28
            radius: 9
            color: App.Palette.surface
            border.color: page.line
            ColumnLayout {
                id: details
                x: 14; y: 14
                width: parent.width - 28
                spacing: 5
                Tag {
                    text: card.launch ? "LAUNCH SCHEDULE  /  LOCAL VISIBILITY UNCONFIRMED" : card.row.badge
                    color: card.launch ? page.muted : card.row.local ? page.accent : page.amber
                }
                Copy {
                    text: card.launch ? card.row.name : card.event.name
                    font.pixelSize: 23
                    font.weight: Font.DemiBold
                }
                Copy {
                    text: card.launch ? page.launchTime(card.row) + (page.launchCountdown(card.row) ? " · " + page.launchCountdown(card.row) : "")
                        : page.interval(card.view?.start.time || card.event.start,
                          card.view?.end.time || card.event.end) + " local · " +
                          (card.view ? "Viewing window" : "Geometric pass")
                    color: page.accent
                }
                Copy {
                    text: card.launch ? card.row.status + " · " + card.row.provider + " · " + card.row.rocket
                        : card.view ? "Look " + card.view.start.direction + " · " + Math.round(card.view.start.el) +
                            "° above horizon · Viewing peak " + Math.round(card.view.peak.el) + "°"
                        : "Geometric peak " + Math.round(card.event.culmination.el) + "°"
                }
                Copy {
                    text: card.launch ? card.row.site + (card.row.region ? " · " + card.row.region : "") : card.row.reason
                    color: page.muted
                }
                Copy {
                    visible: card.launch
                    text: !card.launch ? "" :
                        (card.row.windowStart && card.row.windowEnd && card.row.windowStart !== card.row.windowEnd &&
                         ["SEC", "MIN", "HR"].includes(card.row.precision)
                            ? "Launch window " + page.when(card.row.windowStart, false) + " to " + page.when(card.row.windowEnd, false) + " local. "
                            : "") + "Viewing direction and visibility are unknown without trajectory data."
                    color: page.muted
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    LinkButton { visible: !card.launch; text: "Inspect in Sky View"; onClicked: page.inspect(card.event.id) }
                    LinkButton {
                        visible: card.launch && !page.launchFeed?.fixture
                        text: "Launch source ↗"
                        onClicked: Qt.openUrlExternally(card.row.source)
                    }
                    LinkButton {
                        visible: card.launch && !page.launchFeed?.fixture && !!card.row.stream
                        text: "Watch online ↗"
                        onClicked: Qt.openUrlExternally(card.row.stream)
                    }
                }
            }
        }
    }
    Item { implicitHeight: page.gutter }
}
