import "../qml/Omanova" as App
import "../qml/Omanova/Navigation.js" as Navigation
import "../qml/Omanova/ObservationDraft.js" as ObservationDraft
import ".." as Core
import "./trips" as TripsPages
import "./observing-log" as LogPages
import "./follow" as FollowPages
import "./equipment" as EquipmentPages
import "./calendar" as CalendarPages
import "./offline" as OfflinePages
import "./my_night" as MyNightPages
import "./field" as FinderPages
import "./final_sky" as FinalSkyPages
import "./planets" as PlanetsPages
import "./dark-sites" as SitesPages
import "./aurora" as AuroraPages
import "./trains" as TrainsPages
import "./satellites" as SatellitesPages
import "./plumes" as PlumesPages
import "./eclipses" as EclipsesPages
import "./comets" as CometsPages
import "./meteors" as MeteorsPages
import "./moon" as MoonPages
import "./orbit" as OrbitPages
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
    id: shell
    property Core.SkyState stateModel: Core.SkyState { id: sky;applyEquipmentProfile:true }
    readonly property bool settingsTrial: Quickshell.env("OMASKY_SETTINGS_PREVIEW") === "1" && stateModel.fixture
    property bool compactOpen: false
    property Core.MissionControlState wallpaper: Core.MissionControlState {}

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
            Core.SkyPanel {
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
        title: "OMANOVA Observatory · " + (shell.settingsTrial ? (Quickshell.env("OMANOVA_THEME_TRIAL")==="1" ? "Theme preview" : "Settings preview") : sky.fixture ? "Fixture preview" : "Live data")
        color: (ui.pageId === "overview" || ui.pageId === "orbit") && !App.Palette.themed ? "#060e19" : App.Palette.background
        implicitWidth: 1050
        implicitHeight: 700
        minimumSize: Qt.size(360, 400)
        onVisibleChanged: if (!visible) Qt.quit()
        Shortcut {
            sequence: "Ctrl+D"
            onActivated: if(!App.Palette.save.running) {
                const modes = ["normal", "dim", "red"]
                App.Palette.setObserving(modes[(modes.indexOf(App.Palette.observingMode)+1)%3])
            }
        }

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
            property var logDraftRequest: null
            property int logDraftSequence: 0
            readonly property var event: sky.events.find(row => row.id === selectedEventId) || sky.featured ||
                (pageId === "conditions" ? sky.events.find(row => !!sky.bestWindow(row)) : null)
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
            readonly property bool extendedPages: !sky.fixture || shell.settingsTrial
            readonly property var tabs: Navigation.available(extendedPages).sort((a,b) => a.legacy-b.legacy).map(p => p.label)
            property string pageId: shell.settingsTrial ? "settings" : "overview"
            readonly property int screenIndex: Navigation.page(pageId)?.legacy ?? 0
            readonly property string sectionId: Navigation.section(pageId)
            readonly property var sectionPages: Navigation.sectionPages(sectionId, extendedPages)
            readonly property bool showingPlanets: pageId === "planets"
            readonly property bool ownScroll: ["planets", "trips", "following", "equipment", "calendar", "offline", "my-night", "sites", "sky-finder", "log", "star-chart", "live-orbit", "polar", "transits"].includes(pageId)
            NightContext { id: nightModel; skyModel: sky }
            property var orbitTarget: null
            property real scrub: -1
            readonly property real riseTime: event ? Date.parse(event.start) : 0
            readonly property real passSeconds: event ? (Date.parse(event.end) - riseTime) / 1000 : 0
            readonly property real firstLook: viewing ? (Date.parse(viewing.start.time) - riseTime) / 1000 : 0
            readonly property real scrubTime: riseTime + (scrub < 0 ? firstLook : scrub) * 1000
            readonly property var predicted: pageId === "sky-view" ? positionAt(scrubTime) : null
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
            function navigate(id) {
                if (!Navigation.available(extendedPages).some(p => p.id === id)) return false
                if (pageId !== id) {
                    pageId = id
                    scroll.contentItem.contentY = 0
                }
                return true
            }
            function changeScreen(index) { return navigate(Navigation.fromLegacy(index)) }
            function addToNight(kind,key) {
                if (!myNightLoader.item) return
                myNightLoader.item.add(kind,key)
                navigate("my-night")
            }
            function startObservation(selected) {
                const draft = ObservationDraft.make(selected, selected?.place ?? sky.data?.place?.name ?? "", new Date(), ++logDraftSequence)
                if (!draft) return false
                logDraftRequest = draft
                return navigate("log")
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
                font.pixelSize: ui.width < 500 ? 26 : 32
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
            component Scope: App.ViewPanel {
                appearance:"mission"
                id: scope
                property string label
                property var marker: null
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
                        text: "Solid · potential viewing window     Dashed · geometric path" +
                            (!App.Palette.themed && App.Palette.observingMode==="normal" ? "     Illustrative stars" : "")
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
                        text: ui.width < 500 ? (sky.fixture ? "SAMPLE" : !sky.data ? "WAITING" : sky.snapshotStale ? "STALE" : "CURRENT") : sky.fixture ? "OFFLINE FIXTURE" : sky.runtimeStatus.toUpperCase()
                        color: ui.snapshotStale ? ui.amber : ui.accent
                    }
                }
                Rule {}
                Flow {
                    Layout.fillWidth: true
                    Layout.leftMargin: ui.gutter; Layout.rightMargin: ui.gutter
                    spacing: 4
                    Repeater {
                        model: Navigation.groups.filter(g => Navigation.sectionPages(g.id, ui.extendedPages).length)
                        App.ActionButton {
                            required property var modelData
                            text: modelData.label
                            Accessible.description: ui.sectionId === modelData.id ? "Current section" : "Open section"
                            onClicked: if (ui.sectionId !== modelData.id) ui.navigate(Navigation.sectionPages(modelData.id, ui.extendedPages)[0].id)
                            background: Rectangle {
                                radius: 6
                                color: ui.sectionId === modelData.id ? App.Palette.button : "transparent"
                                border.color: parent.visualFocus ? ui.accent : ui.sectionId === modelData.id ? ui.line : "transparent"
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: ui.sectionId === modelData.id ? ui.accent : "transparent" }
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: ui.gutter; Layout.rightMargin: ui.gutter
                    Layout.topMargin: 6; Layout.bottomMargin: 10
                    Flow {
                        visible: ui.width >= 720
                        Layout.fillWidth: true
                        spacing: 5
                        Repeater {
                            model: ui.sectionPages
                            App.ActionButton {
                                required property var modelData
                                text: (ui.pageId === modelData.id ? "• " : "") + modelData.label
                                Accessible.description: ui.pageId === modelData.id ? "Current page" : "Open page"
                                onClicked: ui.navigate(modelData.id)
                                background: Rectangle { radius: 6; color: ui.pageId === parent.modelData.id ? App.Palette.button : "transparent"; border.color: parent.visualFocus ? ui.accent : ui.pageId === parent.modelData.id ? ui.line : "transparent" }
                            }
                        }
                    }
                    ComboBox {
                        id: pageChoice
                        visible: ui.width < 720
                        Layout.fillWidth: true
                        Layout.minimumWidth: 100
                        implicitHeight: 42
                        model: ui.sectionPages
                        textRole: "label"
                        currentIndex: ui.sectionPages.findIndex(p => p.id === ui.pageId)
                        Accessible.name: "Page in current section"
                        onActivated: ui.navigate(ui.sectionPages[currentIndex].id)
                        palette.base: App.Palette.field; palette.button: App.Palette.button
                        palette.text: App.Palette.ink; palette.buttonText: App.Palette.ink
                        palette.window: App.Palette.surface; palette.windowText: App.Palette.ink
                        palette.highlight: App.Palette.hover; palette.highlightedText: App.Palette.ink
                        background: Rectangle {radius:6;color:App.Palette.button;border.color:pageChoice.activeFocus?ui.accent:App.Palette.border}
                    }
                    App.ActionButton {
                        id: displayChoice
                        text: ui.width < 500 ? App.Palette.observingMode : qsTr("Display: %1").arg(App.Palette.observingMode)
                        Accessible.description: "Choose normal, dim or red. Shortcut Ctrl+D cycles display mode."
                        enabled: !App.Palette.save.running
                        onClicked: displayMenu.open()
                        Menu {
                            id: displayMenu
                            y: displayChoice.height
                            background: Rectangle { color: App.Palette.surface; border.color: App.Palette.border; radius: 6 }
                            Repeater {
                                model: ["normal", "dim", "red"]
                                MenuItem {
                                    required property string modelData
                                    text: modelData
                                    onTriggered: App.Palette.setObserving(modelData)
                                    contentItem: Copy { text: parent.text; padding: 10; color: App.Palette.ink }
                                    background: Rectangle { color: parent.highlighted ? App.Palette.hover : App.Palette.surface }
                                }
                            }
                        }
                    }
                }
                Rule {}
                ScrollView {
                    id: scroll
                    visible: !ui.ownScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: availableWidth
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    Loader {
                        id: screenLoader
                        onLoaded: Qt.callLater(() => { if (ui.pageId === "overview") scroll.contentItem.contentY = scroll.contentItem.originY })
                        width: scroll.availableWidth
                        sourceComponent: ui.ownScroll ? null : ({overview:overview, "sky-view":skyView, conditions:conditions, events:eventsView, orbit:orbitView, moon:moonView, meteors:meteorView, comets:cometView, eclipses:eclipseView, plumes:plumeView, watchlist:watchlistView, trains:trainView, aurora:auroraView, "regional-sites":darkSitesView, settings:settingsView})[ui.pageId] || null
                    }
                }
                Loader {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: ui.pageId === "trips"
                    active: visible
                    sourceComponent: Component { TripsPages.TripPage {} }
                }
                Loader {
                    id: logLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: ui.pageId === "log"
                    active: visible || !!item
                    sourceComponent: Component {
                        ScrollView {
                            id: logScroll
                            property alias logPage: observationLog
                            contentWidth: availableWidth
                            clip: true
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                            LogPages.ObservingLogPage {
                                id: observationLog
                                width: logScroll.availableWidth
                                draftRequest: ui.logDraftRequest
                            }
                        }
                    }
                }
                Loader {
                    id: followingLoader
                    Layout.fillWidth:true;Layout.fillHeight:true
                    visible:ui.pageId === "following"
                    // Retain monitoring when another Observatory tab is selected.
                    active: !sky.fixture || ui.pageId === "following" || !!item
                    sourceComponent:Component { FollowPages.FollowPage {} }
                }
                Loader {
                    id: equipmentLoader
                    Layout.fillWidth:true;Layout.fillHeight:true
                    visible:ui.pageId === "equipment";active:visible
                    sourceComponent:Component {EquipmentPages.EquipmentPage {}}
                }
                Loader {
                    id: calendarLoader
                    Layout.fillWidth:true;Layout.fillHeight:true
                    visible:ui.pageId === "calendar";active:visible
                    sourceComponent:Component {CalendarPages.CalendarPage {}}
                }
                Loader {
                    id: offlineLoader
                    Layout.fillWidth:true;Layout.fillHeight:true
                    visible:ui.pageId === "offline";active:visible
                    sourceComponent:Component {OfflinePages.OfflinePage {}}
                }
                Loader {
                    id: myNightLoader
                    Layout.fillWidth:true;Layout.fillHeight:true
                    visible:ui.pageId === "my-night";active:ui.extendedPages
                    sourceComponent:Component {MyNightPages.MyNightPage {sky:ui.skyModel;onOpenEquipment:ui.navigate("equipment");onRecordObservation:selected=>ui.startObservation(selected)}}
                }
                Loader {Layout.fillWidth:true;Layout.fillHeight:true;visible:ui.pageId === "sites";active:visible;sourceComponent:Component {FinderPages.FieldPage {section:"sites";skyModel:sky}}}
                Loader {Layout.fillWidth:true;Layout.fillHeight:true;visible:ui.pageId === "sky-finder";active:visible;sourceComponent:Component {FinderPages.FieldPage {section:"finder";skyModel:sky;canAddToNight:ui.extendedPages;onOpenEquipment:ui.navigate("equipment");onAddToNight:key=>ui.addToNight("target",key)}}}
                Loader {
                    id: finalSkyLoader
                    Layout.fillWidth:true;Layout.fillHeight:true
                    visible:["star-chart","live-orbit","polar","transits"].includes(ui.pageId);active:visible
                    sourceComponent:Component { FinalSkyPages.FinalSkyPage {skyModel:sky;nightEditor:myNightLoader.item;onOpenMyNight:ui.navigate("my-night");onOpenEquipment:ui.navigate("equipment");section:({"star-chart":"chart","live-orbit":"live",polar:"polar",transits:"transits"})[ui.pageId] || "chart"} }
                }
                Loader {
                    id: planetLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: ui.showingPlanets
                    active: visible
                    sourceComponent: Component { PlanetsPages.PlanetPage {} }
                }
            }

            Component {
                id: darkSitesView
                SitesPages.DarkSitesPage { formatDistance: sky.formatDistance }
            }

            Component {
                id: auroraView
                AuroraPages.AuroraPage {}
            }

            Component {
                id: trainView
                TrainsPages.TrainPage {}
            }

            Component {
                id: watchlistView
                SatellitesPages.WatchlistPage {}
            }

            Component {
                id: plumeView
                PlumesPages.PlumePage {}
            }

            Component {
                id: settingsView
                Core.SettingsPage {
                    sky: shell.stateModel
                    updateDraftBlocked:logLoader.item?.logPage?.dirty || false
                    wallpaper: shell.wallpaper
                    onOpenCompact: shell.compactOpen = true
                }
            }

            Component {
                id: eclipseView
                EclipsesPages.EclipsePage {}
            }

            Component {
                id: cometView
                CometsPages.CometPage {}
            }

            Component {
                id: meteorView
                MeteorsPages.MeteorPage {}
            }

            Component {
                id: moonView
                MoonPages.MoonPage { formatDistance: sky.formatDistance }
            }

            Component {
                id: orbitView
                OrbitPages.OrbitPage { formatDistance: sky.formatDistance; initialTarget: ui.orbitTarget; onTargetConsumed: ui.orbitTarget = null }
            }

            Component {
                id: eventsView
                Core.UnifiedEventsPage {
                    sky: ui.skyModel
                    canAddToNight:ui.extendedPages
                    onAddToNight:key=>ui.addToNight("event",key)
                    onRecordObservation: selected => ui.startObservation(selected)
                    onInspect: function(selected) {
                        if (selected.station_id) ui.selectedEventId = selected.station_id
                        ui.changeScreen(selected.kind === "launch" ? 10 : selected.page)
                    }
                }
            }

            Component {
                id: overview
                TonightPage {
                    sky: ui.skyModel
                    night: nightModel
                    canAddToNight:ui.extendedPages
                    onAddToNight:key=>ui.addToNight("event",key)
                    onRecordObservation: selected => ui.startObservation(selected)
                    onInspect: function(selected) {
                        if (selected.station_id) ui.selectedEventId = selected.station_id
                        ui.changeScreen(selected.page)
                    }
                    onOpenOrbit: target => { ui.orbitTarget = target; ui.navigate("orbit") }
                    onOpenEvents: ui.navigate("events")
                    onOpenSettings: ui.navigate("settings")
                }
            }

            Component {
                id: skyView
                ColumnLayout {
                    spacing: 15
                    App.PageHeader { Layout.leftMargin: ui.gutter; Layout.rightMargin: ui.gutter; Layout.topMargin: ui.gutter; eyebrow: "SKY"; title: "Sky View" }
                    GridLayout {
                        columns: width < 600 ? 1 : 2
                        Layout.fillWidth: true
                        Layout.leftMargin: ui.gutter; Layout.rightMargin: ui.gutter
                        rowSpacing: 18; columnSpacing: 25
                        Scope { Layout.fillWidth: true; Layout.preferredWidth: 470; label: ui.event?.name || "Local sky"; marker: ui.predicted }
                        App.InstrumentCard {
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
                    App.InstrumentCard {
                        Layout.fillWidth: true
                        Layout.leftMargin: ui.gutter; Layout.rightMargin: ui.gutter; Layout.bottomMargin: ui.gutter
                        Copy { text: "Scrub predicted pass" }
                        App.PassSlider {
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
                    App.PageHeader {Layout.leftMargin:ui.gutter;Layout.rightMargin:ui.gutter;Layout.topMargin:ui.gutter;eyebrow:"TONIGHT";title:"Conditions"}
                    App.ViewPanel {
                        appearance:"mission"
                        Layout.fillWidth: true
                        Layout.leftMargin: ui.gutter; Layout.rightMargin: ui.gutter
                        implicitHeight: verdictText.implicitHeight + 28
                        Rectangle { width: 2; height: parent.height; color: ui.verdictColor }
                        ColumnLayout {
                            id: verdictText
                            width: parent.width - 30
                            x: 15; y: 14
                            spacing: 6
                            Tag { Layout.fillWidth: true; text: (ui.event?.name ? ui.event.name+"  ·  " : "") + ui.verdict + (sky.fixture ? " · SAMPLE FORECAST" : " · VIEWING CONDITIONS"); color: ui.verdictColor }
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
                        rowSpacing: 12; columnSpacing: 12
                        App.InstrumentCard {
                            Layout.fillWidth: true; Layout.preferredWidth: 1
                            spacing: 9
                            Tag { Layout.fillWidth: true; text: "CLOUD PROFILE · HIGHEST FORECAST VALUES" }
                            Copy { Layout.fillWidth: true; text: ui.metric(ui.aggregate("cloud_cover", false), "% total");
                                font.pixelSize: 28; font.weight: Font.DemiBold }
                            CloudLayer { Layout.fillWidth: true; caption: "High"; amount: ui.aggregate("cloud_cover_high", false) }
                            CloudLayer { Layout.fillWidth: true; caption: "Mid"; amount: ui.aggregate("cloud_cover_mid", false) }
                            CloudLayer { Layout.fillWidth: true; caption: "Low"; amount: ui.aggregate("cloud_cover_low", false) }
                        }
                        App.InstrumentCard {
                            Layout.fillWidth: true; Layout.preferredWidth: 1
                            spacing: 10
                            Tag {text:"VIEWING WINDOW"}
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
                            Rule {}
                            Fact { Layout.fillWidth: true; caption: "Dew risk"; value: {
                                const age = sky.now - Date.parse(ui.forecast?.fetched)
                                return ui.snapshotStale || !(age >= 0 && age < 21600000) ? "Unknown" : ui.forecast?.dewRisk || "Unknown"
                            } }
                            Copy { Layout.fillWidth: true; color: ui.muted; text: "Estimated from forecast air temperature and dew point at 2 m. Optics may cool faster than the air." }
                        }
                    }
                    App.InstrumentCard {
                        Layout.leftMargin:ui.gutter;Layout.rightMargin:ui.gutter
                        visible:ui.hours.length>0
                        Tag {text:qsTr("FORECAST HOURS · LOCAL TIME")}
                        Flow {
                            Layout.fillWidth:true;spacing:12
                            Repeater {
                                model:ui.hours
                                Copy {required property var modelData
                                    text:ui.clock(modelData.time)+"  ·  "+(Number.isFinite(modelData.cloud_cover)?modelData.cloud_cover+"% cloud":qsTr("Cloud unknown"))
                                }
                            }
                        }
                    }
                    App.ActionButton {
                        Layout.leftMargin:ui.gutter
                        visible:ui.extendedPages&&!sky.fixture&&!ui.hours.length
                        text:qsTr("Weather download settings");onClicked:ui.navigate("settings")
                    }
                    App.InstrumentCard {
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
            function observingDisplay(mode:string):void {if(shell.settingsTrial)App.Palette.setObserving(mode)}
            function screen(index: int): void { ui.changeScreen(index) }
            function sampleObservation(): bool {
                if(!sky.fixture) return false
                return ui.startObservation({name:"SIMULATED · ISS observation",assessment:"Sample exercise only",kind:"station"})
            }
            function navigate(id: string): bool { return ui.navigate(id) }
            function freshness(): string {
                return JSON.stringify({stale:sky.snapshotStale, planningStale:sky.plannerStale, next:sky.nextOpportunity?.id||null, verdict:ui.verdict, picks:ui.pageId==="overview"?(ui.screenItem?.picks?.length??0):null, mismatch:sky.runtimeMismatch})
            }
            function navigation(): string { return JSON.stringify({page:ui.pageId, section:ui.sectionId, pages:Navigation.available(ui.extendedPages), status:sky.runtimeStatus, installed:sky.installedRuntime, running:sky.data?.runtime, nightReady:!!nightModel.dataSet, nightError:nightModel.error}) }
            function fixtureSize(width:int, height:int):void { if(sky.fixture){window.implicitWidth=Math.max(360,width);window.implicitHeight=Math.max(400,height)} }
            function planets(section: int): string {
                ui.changeScreen(7)
                const page = planetLoader.item
                if (!page) return ""
                if (section >= 0 && section <= 2) page.section = section
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
                const page = logLoader.item?.logPage
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
            function wallpaperStatus(): string {
                return JSON.stringify({busy:shell.wallpaper.busy,state:shell.wallpaper.state,
                                       error:shell.wallpaper.error})
            }
            function wallpaperFixture(action: string): string {
                if (!shell.settingsTrial) return ""
                if (action !== "read") shell.wallpaper.request(action)
                return wallpaperStatus()
            }
            function capture(name: string): void {
                if (sky.fixture && ["overview", "sky", "conditions", "events", "settings"].includes(name))
                    ui.grabToImage(result => result.saveToFile(sky.directory + "/" + name + ".png"))
            }
            function close(): void { Qt.quit() }
        }
    }
}
