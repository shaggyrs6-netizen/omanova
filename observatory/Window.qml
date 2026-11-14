import "./qml/Omanova" as App
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
    id: shell
    property SkyState stateModel: SkyState { id: sky }
    readonly property bool settingsTrial: Quickshell.env("OMASKY_SETTINGS_PREVIEW") === "1" && stateModel.fixture
    property bool compactOpen: false

    LazyLoader {
        active: shell.settingsTrial && shell.compactOpen
        FloatingWindow {
            title: qsTr("OMANOVA · Compact panel preview")
            color: App.Palette.background
            implicitWidth: 610
            implicitHeight: 490
            minimumSize: Qt.size(360, 360)
            onVisibleChanged: if (!visible) shell.compactOpen = false
            Shortcut { sequence: "Escape"; onActivated: shell.compactOpen = false }
            SkyPanel {
                id: compact
                anchors.fill: parent
                anchors.margins: 16
                sky: shell.stateModel
            }
            IpcHandler {
                target: "omasky-settings-compact-preview"
                function tab(index: int): void { compact.tabIndex = index }
                function capture():void {if(shell.settingsTrial)compact.grabToImage(r=>r.saveToFile(shell.stateModel.directory+"/compact-theme.png"))}
            }
        }
    }

    FloatingWindow {
        id: window
        title: "OMANOVA Observatory · " + (shell.settingsTrial ? (Quickshell.env("OMANOVA_THEME_TRIAL")==="1" ? "Theme preview" : "Settings preview") : sky.fixture ? "Fixture preview" : "Live data test")
        color: App.Palette.background
        implicitWidth: 1050
        implicitHeight: 700
        minimumSize: Qt.size(360, 400)
        onVisibleChanged: if (!visible) Qt.quit()

        Rectangle {
            id: ui
            anchors.fill: parent
            color: window.color
            readonly property var skyModel: sky
            readonly property color surface: App.Palette.surface
            readonly property color ink: App.Palette.ink
            readonly property color muted: App.Palette.muted
            readonly property color line: App.Palette.line
            readonly property color accent: App.Palette.accent
            readonly property color violet: App.Palette.violet
            readonly property color amber: App.Palette.warning
            readonly property string uiFont: "sans-serif"
            property string selectedEventId: ""
            readonly property var event: sky.events.find(row => row.id === selectedEventId) || sky.featured || null
            readonly property bool staleOrbit: event?.confidence === "Stale orbit"
            readonly property var viewing: sky.bestWindow(event)
            readonly property var forecast: viewing ? viewing.conditions : null
            readonly property var hours: forecast ? forecast.hours : []
            readonly property string verdict: !forecast ? "UNKNOWN" :
                forecast.label === "Favourable" ? "GO" : forecast.label === "Poor" ? "NO GO" :
                forecast.label === "Mixed" ? "CAUTION" : "UNKNOWN"
            readonly property color verdictColor: verdict === "GO" ? App.Palette.good : verdict === "UNKNOWN" ? muted : amber
            readonly property int gutter: width < 620 ? 16 : 30
            readonly property real contentHeight: scroll.contentHeight
            readonly property var screenItem: screenLoader.item
            readonly property var tabs: ["Overview", "Sky View", "Conditions", "Events", "Orbit", "Moon", qsTr("Meteor Showers"), qsTr("Planets"), qsTr("Comets"), qsTr("Eclipses"), qsTr("Launch Plumes"), qsTr("Watchlist"), qsTr("Starlink Trains"), qsTr("Aurora"), qsTr("Dark-Sky Sites"), qsTr("Observing Log")].concat(!sky.fixture || shell.settingsTrial ? [qsTr("Settings"), qsTr("Trip Planner"), qsTr("Launch Following"), qsTr("My Equipment and Sky")] : [])
            property int screenIndex: shell.settingsTrial ? 16 : 0
            readonly property bool showingPlanets: screenIndex === 7
            property real scrub: -1
            readonly property real riseTime: event ? Date.parse(event.start) : 0
            readonly property real passSeconds: event ? (Date.parse(event.end) - riseTime) / 1000 : 0
            readonly property real firstLook: viewing ? (Date.parse(viewing.start.time) - riseTime) / 1000 : 0
            readonly property real scrubTime: riseTime + (scrub < 0 ? firstLook : scrub) * 1000
            readonly property var predicted: screenIndex === 1 ? positionAt(scrubTime) : null
            readonly property string eventId: event ? event.id : ""
            readonly property bool snapshotStale: sky.snapshotStale
            onEventIdChanged: scrub = -1

            function clock(time, seconds) {
                return time ? Qt.formatDateTime(new Date(time), seconds ? "HH:mm:ss" : "HH:mm") : "—"
            }
            function peakText() {
                return viewing ? Math.round(viewing.peak.el) + "° " + viewing.peak.direction : "—"
            }
            function positionAt(time) {
                if (!event || !event.path.length) return null
                const path = event.path
                const index = path.findIndex(point => Date.parse(point.time) >= time)
                if (index <= 0) return index === 0 ? path[0] : path[path.length - 1]
                const a = path[index - 1], b = path[index]
                const start = Date.parse(a.time), end = Date.parse(b.time)
                const part = end === start ? 0 : (time - start) / (end - start)
                const turn = ((b.az - a.az + 540) % 360) - 180
                return { az: (a.az + part * turn + 360) % 360, el: a.el + part * (b.el - a.el) }
            }
            function aggregate(key, minimum) {
                if (!hours.length || hours.some(row => typeof row[key] !== "number")) return null
                const values = hours.map(row => row[key])
                return minimum ? Math.min(...values) : Math.max(...values)
            }
            function metric(value, suffix) {
                return value === null ? "Unavailable" : value + suffix
            }
            function changeScreen(index) {
                if (index >= 0 && index < tabs.length && index !== screenIndex) {
                    screenIndex = index
                    scroll.contentItem.contentY = 0
                }
            }
            function bearingName(direction) {
                return ({N:"north", NNE:"north-northeast", NE:"northeast", ENE:"east-northeast",
                    E:"east", ESE:"east-southeast", SE:"southeast", SSE:"south-southeast",
                    S:"south", SSW:"south-southwest", SW:"southwest", WSW:"west-southwest",
                    W:"west", WNW:"west-northwest", NW:"northwest", NNW:"north-northwest"})[direction] || direction
            }

            component Copy: Text {
                color: ui.ink
                font.family: ui.uiFont
                font.pixelSize: 15
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
            }
            component Tag: Copy {
                color: ui.muted
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.letterSpacing: 1.1
            }
            component Title: Copy {
                font.pixelSize: ui.width < 620 ? 30 : 43
                font.weight: Font.DemiBold
            }
            component Rule: Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: ui.line
            }
            component Action: Button {
                id: action
                hoverEnabled: true
                focusPolicy: Qt.StrongFocus
                implicitHeight: 42
                leftPadding: 13
                rightPadding: 13
                contentItem: Copy {
                    text: action.text
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: 14
                }
                background: Rectangle {
                    radius: 6
                    color: action.down ? App.Palette.surface : action.hovered ? App.Palette.surface : ui.surface
                    border.color: action.visualFocus ? ui.accent : ui.line
                }
            }
            component Readout: ColumnLayout {
                property string caption
                property string value
                property color tint: ui.ink
                spacing: 3
                Tag { Layout.fillWidth: true; text: parent.caption }
                Copy { Layout.fillWidth: true; text: parent.value; color: parent.tint; font.pixelSize: 19; font.weight: Font.DemiBold }
            }
            component Fact: RowLayout {
                property string caption
                property string value
                spacing: 12
                Copy { Layout.fillWidth: true; text: parent.caption; color: ui.muted; font.pixelSize: 14 }
                Copy { text: parent.value; font.pixelSize: 14; font.weight: Font.DemiBold }
            }
            component CloudLayer: RowLayout {
                id: layer
                property string caption
                property var amount: null
                spacing: 8
                Copy { Layout.preferredWidth: 42; text: layer.caption; font.pixelSize: 14 }
                ProgressBar {
                    id: meter
                    Layout.fillWidth: true
                    from: 0; to: 100
                    value: layer.amount ?? 0
                    Accessible.name: layer.caption + " cloud cover"
                    Accessible.description: layer.amount === null ? "Unavailable" : layer.amount + " percent"
                    background: Rectangle { implicitHeight: 7; radius: 3; color: App.Palette.line }
                    contentItem: Item {
                        Rectangle {
                            width: meter.visualPosition * parent.width
                            height: parent.height
                            radius: 3
                            color: ui.violet
                        }
                    }
                }
                Copy { text: layer.amount === null ? "—" : layer.amount + "%"; Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight }
            }
            component Scope: Rectangle {
                id: scope
                property string label
                property var marker: null
                radius: 12
                color: ui.surface
                border.color: ui.line
                gradient: Gradient {
                    GradientStop { position: 0; color: App.Palette.surface }
                    GradientStop { position: 1; color: App.Palette.background }
                }
                implicitHeight: ui.width < 620 ? 320 : 395
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        Tag { Layout.fillWidth: true; text: scope.label }
                        Tag { text: "TRUE NORTH UP" }
                    }
                    InstrumentPlot {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        path: ui.event ? ui.event.path : []
                        viewing: ui.viewing
                        position: scope.marker
                        accent: ui.accent
                        violet: ui.violet
                    }
                    Copy {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        color: ui.muted
                        text: "Solid · potential viewing window     Dashed · geometric path"
                        font.pixelSize: 12
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: ui.gutter
                    Layout.rightMargin: ui.gutter
                    Layout.topMargin: 14
                    Layout.bottomMargin: 12
                    spacing: 12
                    Rectangle {
                        implicitWidth: 29; implicitHeight: 29; radius: 15
                        color: "transparent"; border.color: ui.accent
                        Rectangle { anchors.centerIn: parent; width: 7; height: 7; radius: 4; color: ui.accent }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Copy { text: "OMANOVA"; font.letterSpacing: 3; font.weight: Font.DemiBold }
                        Tag { text: "LOCAL OBSERVATORY" }
                    }
                    Item { Layout.fillWidth: true }
                    Tag {
                        text: sky.fixture ? "OFFLINE FIXTURE" : !sky.data ? "WAITING FOR DATA" :
                            ui.snapshotStale ? "SNAPSHOT STALE" : "LIVE DATA TEST"
                        color: ui.snapshotStale ? ui.amber : ui.accent
                    }
                }
                Rule {}
                Flow {
                    Layout.fillWidth: true
                    Layout.leftMargin: ui.gutter
                    Layout.rightMargin: ui.gutter
                    spacing: 0
                    Repeater {
                        model: ui.tabs
                        delegate: Button {
                            id: tab
                            required property string modelData
                            required property int index
                            text: modelData
                            readonly property bool selected: index === ui.screenIndex
                            Accessible.description: selected ? "Current screen" : ""
                            onClicked: ui.changeScreen(index)
                            focusPolicy: Qt.StrongFocus
                            hoverEnabled: true
                            leftPadding: ui.width < 500 ? 5 : 12
                            rightPadding: ui.width < 500 ? 5 : 12
                            implicitHeight: 43
                            contentItem: Copy {
                                text: tab.text
                                color: tab.selected ? ui.ink : ui.muted
                                font.pixelSize: 14
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                color: tab.selected ? App.Palette.button : tab.hovered ? ui.surface : "transparent"
                                border.color: tab.visualFocus ? ui.accent : "transparent"
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width; height: 2
                                    color: tab.selected ? ui.accent : "transparent"
                                }
                            }
                        }
                    }
                }
                Rule {}
                ScrollView {
                    id: scroll
                    visible: !ui.showingPlanets && ui.screenIndex !== 17 && ui.screenIndex !== 18 && ui.screenIndex !== 19
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: availableWidth
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    Loader {
                        id: screenLoader
                        width: scroll.availableWidth
                        sourceComponent: ui.showingPlanets || ui.screenIndex === 17 || ui.screenIndex === 18 || ui.screenIndex === 19 ? null : [overview, skyView, conditions, eventsView, orbitView, moonView, meteorView, null, cometView, eclipseView, plumeView, watchlistView, trainView, auroraView, darkSitesView, logView, settingsView][ui.screenIndex]
                    }
                }
                Loader {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: ui.screenIndex === 17
                    active: visible
                    sourceComponent: Component { TripPage {} }
                }
                Loader {
                    id: followingLoader
                    Layout.fillWidth:true;Layout.fillHeight:true
                    visible:ui.screenIndex===18
                    // Retain monitoring when another Observatory tab is selected.
                    active: !sky.fixture || ui.screenIndex===18 || !!item
                    sourceComponent:Component { FollowPage {} }
                }
                Loader {
                    id: equipmentLoader
                    Layout.fillWidth:true;Layout.fillHeight:true
                    visible:ui.screenIndex===19;active:visible
                    sourceComponent:Component {EquipmentPage {}}
                }
                Loader {
                    id: planetLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: ui.showingPlanets
                    active: visible
                    sourceComponent: Component { PlanetPage {} }
                }
            }

            Component {
                id: logView
                ObservingLogPage {}
            }

            Component {
                id: darkSitesView
                DarkSitesPage { formatDistance: sky.formatDistance }
            }

            Component {
                id: auroraView
                AuroraPage {}
            }

            Component {
                id: trainView
                TrainPage {}
            }

            Component {
                id: watchlistView
                WatchlistPage {}
            }

            Component {
                id: plumeView
                PlumePage {}
            }

            Component {
                id: settingsView
                SettingsPage {
                    sky: shell.stateModel
                    onOpenCompact: shell.compactOpen = true
                }
            }

            Component {
                id: eclipseView
                EclipsePage {}
            }

            Component {
                id: cometView
                CometPage {}
            }

            Component {
                id: meteorView
                MeteorPage {}
            }

            Component {
                id: moonView
                MoonPage { formatDistance: sky.formatDistance }
            }

            Component {
                id: orbitView
                OrbitPage { formatDistance: sky.formatDistance }
            }

            Component {
                id: eventsView
                UnifiedEventsPage {
                    sky: ui.skyModel
                    onInspect: function(selected) {
                        if (selected.station_id) ui.selectedEventId = selected.station_id
                        ui.changeScreen(selected.kind === "launch" ? 10 : selected.page)
                    }
                }
            }

            Component {
                id: overview
                ColumnLayout {
                    spacing: 19
                    readonly property bool narrow: width < 650
                    OpportunityCard {
                        visible: !!sky.nextOpportunity
                        Layout.margins: ui.gutter
                        event: sky.nextOpportunity || ({kind:"", name:"", start:"", end:"", look:{}, conditions:{}, score_parts:{}})
                        sky: ui.skyModel; hero: true
                        onInspect: function(selected) {
                            if (selected.station_id) ui.selectedEventId = selected.station_id
                            ui.changeScreen(selected.page)
                        }
                    }
                    GridLayout {
                        visible: !sky.nextOpportunity
                        columns: parent.narrow ? 1 : 2
                        Layout.fillWidth: true
                        Layout.margins: ui.gutter
                        Layout.bottomMargin: 0
                        rowSpacing: 20; columnSpacing: 24
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 340
                            spacing: 10
                            Tag { Layout.fillWidth: true; text: "●  NEXT VIEWING OPPORTUNITY"; color: ui.accent }
                            Title { Layout.fillWidth: true; text: !ui.event ? "No viewing opportunity" :
                                    ui.event.name === "ISS" ? "International Space Station" : ui.event.name }
                            Copy {
                                Layout.fillWidth: true
                                text: ui.viewing ? sky.countdown(ui.viewing.start.time) : "—"
                                color: ui.accent
                                font.pixelSize: ui.width < 620 ? 44 : 67
                                font.weight: Font.DemiBold
                            }
                            Copy { Layout.fillWidth: true; text: ui.viewing
                                    ? ui.clock(ui.viewing.start.time) + "–" + ui.clock(ui.viewing.end.time) + "  ·  Local time"
                                    : "No suitable pass in the current snapshot"; color: ui.muted }
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: bearing.implicitHeight + 20
                                color: ui.surface
                                Rectangle { width: 2; height: parent.height; color: ui.accent }
                                ColumnLayout {
                                    id: bearing
                                    width: parent.width - 24
                                    x: 12; y: 10
                                    spacing: 2
                                    Copy {
                                        Layout.fillWidth: true
                                        text: ui.viewing ? "Look " + ui.bearingName(ui.viewing.start.direction)
                                            : "Viewing direction unavailable"
                                        font.weight: Font.DemiBold
                                    }
                                    Copy { Layout.fillWidth: true; color: ui.muted; font.pixelSize: 13; text: ui.viewing
                                        ? Math.round(ui.viewing.start.az) + "° true · " + Math.round(ui.viewing.start.el) + "° above the horizon" : "—" }
                                }
                            }
                            Action { text: "Explore the pass  ↗"; enabled: !!ui.event; onClicked: ui.changeScreen(1) }
                        }
                        Scope { Layout.fillWidth: true; Layout.preferredWidth: 460; label: "01 / LOCAL SKY" }
                    }
                    Rule { Layout.leftMargin: ui.gutter; Layout.rightMargin: ui.gutter }
                    GridLayout {
                        visible: !sky.nextOpportunity || sky.nextOpportunity.kind === "station"
                        columns: width < 480 ? 1 : 3
                        Layout.fillWidth: true
                        Layout.leftMargin: ui.gutter; Layout.rightMargin: ui.gutter; Layout.bottomMargin: ui.gutter
                        rowSpacing: 12; columnSpacing: 15
                        Readout { Layout.fillWidth: true; caption: "STATION VIEWING PEAK"; value: ui.peakText() }
                        Readout { Layout.fillWidth: true; caption: "FORECAST"; value: ui.forecast ? ui.forecast.label : "Unavailable"; tint: ui.verdictColor }
                        Readout { Layout.fillWidth: true; caption: "ORBIT DATA"; value: ui.event
                                ? ui.event.confidence + " · " + Math.round(ui.event.epoch_hours) + "h from epoch" : "Unavailable" }
                    }
                }
            }

            Component {
                id: skyView
                ColumnLayout {
                    spacing: 15
                    Tag { Layout.fillWidth: true; Layout.leftMargin: ui.gutter; Layout.topMargin: ui.gutter; text: "02 / OBSERVER GEOMETRY" }
                    Title { Layout.fillWidth: true; Layout.leftMargin: ui.gutter; text: "Sky View" }
                    GridLayout {
                        columns: width < 600 ? 1 : 2
                        Layout.fillWidth: true
                        Layout.leftMargin: ui.gutter; Layout.rightMargin: ui.gutter
                        rowSpacing: 18; columnSpacing: 25
                        Scope { Layout.fillWidth: true; Layout.preferredWidth: 470; label: "HORIZON → ZENITH"; marker: ui.predicted }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 290
                            spacing: 9
                            Tag { Layout.fillWidth: true; text: "PREDICTED POSITION" }
                            Copy { Layout.fillWidth: true; text: ui.event ? ui.clock(ui.scrubTime, true) : "—"; font.pixelSize: 36; color: ui.accent }
                            Copy { Layout.fillWidth: true; text: ui.predicted
                                    ? (Math.round(ui.predicted.az) % 360) + "° true · " + Math.round(ui.predicted.el) + "° elevation" : "No track available" }
                            Copy { Layout.fillWidth: true; color: ui.muted; text: ui.snapshotStale ? "Data stale · Geometric path only" :
                                    ui.staleOrbit ? "Stale orbital elements · Geometric path only" :
                                    !ui.viewing ? "Viewing window unavailable" :
                                    ui.scrubTime >= Date.parse(ui.viewing.start.time) && ui.scrubTime <= Date.parse(ui.viewing.end.time)
                                    ? "Inside potential viewing window" : "Outside potential viewing window" }
                            Repeater {
                                model: ui.viewing ? [ui.viewing.start, ui.viewing.peak, ui.viewing.end] : []
                                delegate: ColumnLayout {
                                    id: milestone
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Rule {}
                                    Fact { Layout.fillWidth: true; caption: ["01 · First look", "02 · Viewing peak", "03 · Last look"][milestone.index]
                                        value: ui.clock(milestone.modelData.time, true) + " · " + milestone.modelData.direction }
                                }
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: ui.gutter; Layout.rightMargin: ui.gutter; Layout.bottomMargin: ui.gutter
                        Copy { text: "Scrub predicted pass" }
                        Slider {
                            Layout.fillWidth: true
                            from: 0; to: Math.max(1, ui.passSeconds)
                            value: ui.scrub < 0 ? ui.firstLook : ui.scrub
                            stepSize: 1
                            enabled: !!ui.event
                            onMoved: ui.scrub = value
                            Accessible.name: "Scrub predicted pass"
                            palette.highlight: ui.accent
                        }
                        Fact { Layout.fillWidth: true; caption: ui.event ? ui.clock(ui.event.start) + " rise" : "—"
                            value: ui.event ? ui.clock(ui.event.end) + " set" : "—" }
                    }
                }
            }

            Component {
                id: conditions
                ColumnLayout {
                    spacing: 18
                    Tag { Layout.fillWidth: true; Layout.leftMargin: ui.gutter; Layout.topMargin: ui.gutter; text: "03 / OBSERVING CONDITIONS" }
                    Title { Layout.fillWidth: true; Layout.leftMargin: ui.gutter; text: "Conditions" }
                    ColumnLayout {
                        visible: !sky.fixture
                        Layout.fillWidth: true
                        Layout.leftMargin: ui.gutter; Layout.rightMargin: ui.gutter
                        spacing: 5
                        Tag { text: "OBSERVING ALERTS" }
                        Copy {
                            Layout.fillWidth: true
                            color: ui.muted
                            text: "Opt-in alerts use your event types, lead time, quiet hours and weather threshold in Settings. The worker must be running; uncertain local visibility never triggers an alert."
                        }
                        Action {
                            enabled: !!sky.data
                            text: sky.data?.settings?.alerts === true ? "Turn observing alerts off" : "Enable observing alerts"
                            onClicked: sky.run(["alerts", sky.data?.settings?.alerts === true ? "off" : "on"])
                        }
                        Copy {
                            Layout.fillWidth: true
                            visible: !!sky.message
                            text: sky.message
                            color: ui.muted
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.leftMargin: ui.gutter; Layout.rightMargin: ui.gutter
                        implicitHeight: verdictText.implicitHeight + 28
                        radius: 8
                        color: ui.surface
                        Rectangle { width: 2; height: parent.height; color: ui.verdictColor }
                        ColumnLayout {
                            id: verdictText
                            width: parent.width - 30
                            x: 15; y: 14
                            spacing: 6
                            Tag { Layout.fillWidth: true; text: "●  " + ui.verdict + (sky.fixture ? " · SAMPLE FORECAST" : " · VIEWING CONDITIONS"); color: ui.verdictColor }
                            Copy { Layout.fillWidth: true; text: ui.snapshotStale ? "Data stale · Refresh or check the worker."
                                : ui.staleOrbit ? "Orbital elements are too old for a viewing recommendation."
                                : ui.forecast ? ui.forecast.reason : "No forecast for a viewing window";
                                font.pixelSize: 22; font.weight: Font.DemiBold }
                            Copy { Layout.fillWidth: true; color: ui.muted; text: ui.viewing
                                ? ui.clock(ui.viewing.start.time) + "–" + ui.clock(ui.viewing.end.time) + " local"
                                    + (ui.forecast?.fetched ? (sky.fixture ? " · Sample forecast " : " · Forecast fetched ") + ui.clock(ui.forecast.fetched) : "")
                                : "Forecast unavailable" }
                        }
                    }
                    GridLayout {
                        columns: width < 580 ? 1 : 2
                        Layout.fillWidth: true
                        Layout.leftMargin: ui.gutter; Layout.rightMargin: ui.gutter
                        rowSpacing: 22; columnSpacing: 26
                        ColumnLayout {
                            Layout.fillWidth: true; Layout.preferredWidth: 1
                            spacing: 9
                            Tag { Layout.fillWidth: true; text: "CLOUD PROFILE · HIGHEST FORECAST VALUES" }
                            Copy { Layout.fillWidth: true; text: ui.metric(ui.aggregate("cloud_cover", false), "% total");
                                font.pixelSize: 28; font.weight: Font.DemiBold }
                            CloudLayer { Layout.fillWidth: true; caption: "High"; amount: ui.aggregate("cloud_cover_high", false) }
                            CloudLayer { Layout.fillWidth: true; caption: "Mid"; amount: ui.aggregate("cloud_cover_mid", false) }
                            CloudLayer { Layout.fillWidth: true; caption: "Low"; amount: ui.aggregate("cloud_cover_low", false) }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; Layout.preferredWidth: 1
                            spacing: 10
                            Fact { Layout.fillWidth: true; caption: "Sky darkness"; value: !ui.viewing ? "Unavailable" : ui.viewing.peak.sky_dark ? "Dark enough" : "Too bright" }
                            Rule {}
                            Fact { Layout.fillWidth: true; caption: "Visibility · lowest"; value: {
                                const metres = ui.aggregate("visibility", true)
                                return metres === null ? "Unavailable" : sky.formatDistance(metres / 1000, 1)
                            } }
                            Rule {}
                            Fact { Layout.fillWidth: true; caption: "Precipitation · highest"; value: ui.metric(ui.aggregate("precipitation", false), " mm") }
                            Rule {}
                            Fact { Layout.fillWidth: true; caption: "Wind · highest"; value: ui.metric(ui.aggregate("wind_speed_10m", false), " km/h") }
                        }
                    }
                    Copy { Layout.fillWidth: true; Layout.leftMargin: ui.gutter; Layout.rightMargin: ui.gutter; Layout.bottomMargin: ui.gutter;
                        text: (sky.fixture ? "Sample area forecast." : "Area forecast.") + " Local cloud and obstructions may differ."; color: ui.muted; font.pixelSize: 13 }
                }
            }
        }

        IpcHandler {
            target: "omasky-observatory-preview"
            function theme(mode: string): string {
                if(!shell.settingsTrial || Quickshell.env("OMANOVA_THEME_TRIAL")!=="1")return ""
                if(["light","dark","desktop","file"].includes(mode))App.Palette.sample(mode)
                if(mode==="toggle")App.Palette.toggle()
                return JSON.stringify({follow:App.Palette.follow,themed:App.Palette.themed,missing:App.Palette.missing,background:String(App.Palette.background),ink:String(App.Palette.ink),error:App.Palette.error})
            }
            function screen(index: int): void { ui.changeScreen(index) }
            function planets(section: int): string {
                ui.changeScreen(7)
                const page = planetLoader.item
                if (!page) return ""
                if (section === 0 || section === 1) page.section = section
                return JSON.stringify({ planets: page.dataSet?.highlights.length ?? 0,
                    pairings: page.dataSet?.pairings.length ?? 0, fixture: page.dataSet?.fixture,
                    section: page.section, width: page.width, height: page.height })
            }
            function settings(): string {
                if (ui.tabs.length <= 16) return ""
                ui.changeScreen(16)
                return JSON.stringify({ place: sky.data?.place?.name, online: sky.data?.settings?.online,
                    weather: sky.data?.settings?.weather, profileCount: sky.data?.settings?.profiles.length,
                    distanceUnit: sky.useMiles ? "mi" : "km",
                    busy: sky.settingsWorker.running, message: sky.message })
            }
            function compactPreview(show: bool): void {
                if (shell.settingsTrial) shell.compactOpen = show
            }
            function observingLog(): string {
                ui.changeScreen(15)
                const page = ui.screenItem
                return JSON.stringify({ ready: page?.ready, count: page?.entries.length, failed: page?.failed })
            }
            function darkSites(dropIn: bool): string {
                ui.changeScreen(14)
                const page = ui.screenItem
                if (!page) return ""
                page.dropInOnly = dropIn
                return JSON.stringify({ count: page.visibleSites.length, checked: page.catalog?.checked })
            }
            function aurora(): string {
                ui.changeScreen(13)
                const page = ui.screenItem
                return JSON.stringify({ fixture: page?.catalog?.fixture, verdict: page?.verdict,
                    valid: page?.current?.valid, nights: page?.catalog?.nights.length, error: page?.loadError })
            }
            function trains(): string {
                ui.changeScreen(12)
                const page = ui.screenItem
                return JSON.stringify({ fixture: page?.catalog?.fixture, recent: page?.catalog?.recentAvailable,
                    batches: page?.catalog?.batches.map(item => ({ name: item.name, members: item.members,
                        windows: page.activeWindows(item).length })) })
            }
            function watchlist(): string {
                ui.changeScreen(11)
                const page = ui.screenItem
                return JSON.stringify({ fixture: page?.catalog?.fixture, usable: page?.catalog?.targets.filter(t => t.usable).length,
                    windows: page?.visibleWindows.length, error: page?.catalog?.error })
            }
            function plumes(): string {
                ui.changeScreen(10)
                const page = ui.screenItem
                return JSON.stringify({ fixture: page?.catalog?.fixture, fresh: page?.fresh,
                    count: page?.catalog?.launches.length, candidates: page?.candidates })
            }
            function eclipses(): string {
                ui.changeScreen(9)
                const catalog = ui.screenItem?.catalog
                return JSON.stringify({ solar: catalog?.solar.length, lunar: catalog?.lunar.length,
                    fixture: catalog?.fixture })
            }
            function comets(): string {
                ui.changeScreen(8)
                const catalog = ui.screenItem?.catalog
                return JSON.stringify({ available: ui.screenItem?.available, fixture: catalog?.fixture,
                    until: catalog?.until, windows: catalog?.targets.map(target => target.windows.length) })
            }
            function meteors(): string {
                ui.changeScreen(6)
                return JSON.stringify(ui.screenItem?.catalog?.showers.map(
                    shower => ({ name: shower.name, windows: shower.windows.length })) ?? [])
            }
            function moon(): string {
                ui.changeScreen(5)
                return ui.screenItem ? JSON.stringify(ui.screenItem.summary()) : ""
            }
            function orbit(index: int, sample: int): string {
                ui.changeScreen(4)
                const page = ui.screenItem
                if (!page || index < 0 || index > 1) return ""
                page.stationIndex = index
                if (sample >= 0 && page.selected)
                    page.sampleIndex = Math.min(sample, page.selected.pass.length - 1)
                return JSON.stringify({ name: page.station?.name, points: page.selected?.track.length,
                    sample: page.sample?.time, status: page.status() })
            }
            function list(mode: int): string {
                ui.changeScreen(3)
                const page = ui.screenItem
                if (!page || mode < 0 || mode > 2) return ""
                page.stationDetail = true
                page.mode = mode
                return page.summary()
            }
            function scrub(seconds: int): void { ui.scrub = Math.max(0, Math.min(ui.passSeconds, seconds)) }
            function summary(): string {
                return JSON.stringify({ planned: sky.plannedEvents.length, next: sky.nextOpportunity?.name, plannerStale: sky.plannerStale, screen: ui.screenIndex, event: ui.event?.name, verdict: ui.verdict,
                    alerts: sky.data?.settings?.alerts === true, fixture: sky.fixture, generated: sky.data?.generated, stale: ui.snapshotStale,
                    width: ui.width, height: ui.height, contentHeight: ui.contentHeight, time: ui.clock(ui.scrubTime, true), position: ui.predicted })
            }
            function capture(name: string): void {
                if (sky.fixture && ["overview", "sky", "conditions", "events", "settings"].includes(name))
                    ui.grabToImage(result => result.saveToFile(sky.directory + "/" + name + ".png"))
            }
            function close(): void { Qt.quit() }
        }
    }
}
