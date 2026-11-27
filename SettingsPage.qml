import "./qml/Omanova" as App
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: page
    required property var sky
    property bool compact: false
    property bool updateDraftBlocked:false
    property var wallpaper: null
    readonly property bool trial: Quickshell.env("OMASKY_SETTINGS_PREVIEW") === "1" && sky.fixture
    readonly property var preferences: sky.data?.settings ?? ({ profiles: [], online: false, weather: false })
    readonly property bool busy: sky.settingsWorker.running
    readonly property int gutter: compact ? 0 : 22
    property int sectionIndex: 1
    readonly property var sections: [
        [qsTr("Location & units"), qsTr("Saved places · distance units")],
        [qsTr("Downloads"), qsTr("Orbit, weather, launches & aurora")],
        [qsTr("Observing preferences"), qsTr("Interests, alerts & watchlist")],
        [qsTr("Appearance"), qsTr("Desktop theme · dim and red modes")],
        [qsTr("Mission Control wallpaper"), qsTr("Wallpaper, startup & power")],
        [qsTr("Updates & runtime"), qsTr("App updates · worker status")]
    ]
    function shows(index) { return compact || sectionIndex === index }
    property var lookupRows: []
    property string lookupMessage: ""
    property string lookupInput: ""
    property bool lookupCooling: false
    Timer { interval: 5000; running: page.lookupCooling; onTriggered: page.lookupCooling = false }
    Process {
        id: lookup
        stdinEnabled: true
        command: [page.sky.runtime + "/.venv/bin/python", page.sky.runtime + "/place_lookup.py"]
        environment: ({ "OPENBLAS_NUM_THREADS": "1" })
        onStarted: { write(page.lookupInput); page.lookupInput = ""; stdinEnabled = false }
        stdout: StdioCollector { id: lookupOutput }
        onExited: function(code) {
            if (code === 0) {
                try { page.lookupRows = JSON.parse(lookupOutput.text); page.lookupMessage = page.lookupRows.length ? "Select a result to fill the fields, then save or use temporarily." : "No places found." }
                catch (e) { page.lookupMessage = "Lookup unavailable." }
            } else page.lookupMessage = "Lookup unavailable. Use manual coordinates or try again later."
        }
    }
    signal openCompact()
    spacing: 12

    component Copy: Text {
        Layout.fillWidth: true
        color: App.Palette.ink
        font.pixelSize: 14
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }
    component Heading: Copy {
        font.pixelSize: 21
        font.bold: true
    }
    component Action: Button {
        id: action
        enabled: !page.busy
        implicitHeight: 37
        leftPadding: 12
        rightPadding: 12
        contentItem: Text {
            text: action.text
            textFormat: Text.PlainText
            color: action.enabled ? App.Palette.ink : App.Palette.muted
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 6
            color: action.down ? App.Palette.button : action.hovered ? App.Palette.hover : App.Palette.button
            border.color: action.visualFocus ? App.Palette.accent : App.Palette.border
        }
    }
    component Field: TextField {
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        color: App.Palette.ink
        placeholderTextColor: App.Palette.muted
        selectionColor: App.Palette.button
        selectedTextColor: App.Palette.ink
        implicitHeight: 37
        Accessible.name: placeholderText
        background: Rectangle {
            color: App.Palette.field
            radius: 5
            border.color: parent.activeFocus ? App.Palette.accent : App.Palette.border
        }
    }
    component Card: App.ViewPanel {
        appearance:"mission"
        Layout.fillWidth: true

    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: page.gutter
        Layout.rightMargin: page.gutter
        Layout.topMargin: page.compact ? 4 : 20
        visible: !page.compact
        spacing: 7
        App.PageHeader {eyebrow:"SETTINGS";title:qsTr("Settings")}
        Copy {
            visible: page.trial
            text: qsTr("Offline preview. These controls use sample data and save changes only in this trial.")
            color: App.Palette.muted
        }
        Action {
            visible: page.trial
            text: qsTr("Show compact panel preview")
            onClicked: page.openCompact()
        }
    }

    GridLayout {
        id:settingsGrid
        Layout.fillWidth:true;Layout.leftMargin:page.gutter;Layout.rightMargin:page.gutter
        columns:page.compact || width<720 ? 1 : 2
        columnSpacing:12;rowSpacing:12
        App.ViewPanel {
            visible:!page.compact;appearance:"mission"
            Layout.preferredWidth:270;Layout.fillWidth:true;Layout.alignment:Qt.AlignTop
            implicitHeight:sectionList.implicitHeight+20
            ColumnLayout {
                id:sectionList
                anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:10
                spacing:4
                ComboBox {
                    visible:settingsGrid.columns===1;Layout.fillWidth:true
                    model:page.sections.map(s=>s[0]);currentIndex:page.sectionIndex
                    Accessible.name:qsTr("Settings section")
                    palette.button:App.Palette.button;palette.buttonText:App.Palette.ink
                    palette.base:App.Palette.field;palette.text:App.Palette.ink
                    onActivated:index=>page.sectionIndex=index
                }
                Repeater {
                    model:page.sections
                    Button {
                        id:sectionButton
                        required property int index
                        required property var modelData
                        visible:settingsGrid.columns===2
                        Layout.fillWidth:true;implicitHeight:65;leftPadding:12;rightPadding:8
                        Accessible.name:modelData[0];Accessible.selected:current
                        readonly property bool current:page.sectionIndex===index
                        onClicked:page.sectionIndex=index
                        background:Rectangle {
                            radius:5;color:sectionButton.current?App.Palette.hover:sectionButton.hovered?App.Palette.field:"transparent"
                            border.color:sectionButton.current||sectionButton.activeFocus?App.Palette.accent:"transparent"
                        }
                        contentItem:ColumnLayout {
                            spacing:2
                            Copy {text:sectionButton.modelData[0];font.bold:true;color:sectionButton.current?App.Palette.accent:App.Palette.ink}
                            Copy {text:sectionButton.modelData[1];font.pixelSize:12;color:App.Palette.muted}
                        }
                    }
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth:true;Layout.preferredWidth:660;Layout.minimumWidth:0;Layout.alignment:Qt.AlignTop
            spacing:12
            App.CometExpiry { runtime: page.sky.runtime; visible: !page.compact && page.shows(5) && Number.isFinite(expiry) && expiry - now <= 14 * 86400000 }
            UpdateCard {sky:page.sky;draftBlocked:page.updateDraftBlocked;visible:!page.compact && page.shows(5);Layout.fillWidth:true;}

            App.RuntimeStatus {
                visible:page.shows(5)
                sky: page.sky

            }

            Card {
                visible: page.shows(3)
                implicitHeight: appearanceBody.implicitHeight+32
                ColumnLayout {
                    anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:16
                    id:appearanceBody

                    spacing: 6
                    Heading { text: qsTr("Appearance") }
                    CheckBox {
                        text: qsTr("Follow desktop theme")
                        checked: App.Palette.follow
                        enabled: !App.Palette.save.running
                        palette.windowText: App.Palette.ink; palette.text: App.Palette.ink
                        palette.buttonText: App.Palette.ink; palette.highlight: App.Palette.accent
                        onClicked: App.Palette.toggle()
                    }
                    Copy { text: App.Palette.follow ? qsTr("Follows Omarchy's current colours, including theme changes. Text and status colours retain readable contrast.") : qsTr("Using the original Observatory colours."); color: App.Palette.muted }
                    Flow {Layout.fillWidth:true;spacing:8
                        Repeater {model:["normal","dim","red"]
                            Action {required property string modelData;text:(App.Palette.observingMode===modelData?"● ":"")+modelData+" display";enabled:!App.Palette.save.running;onClicked:App.Palette.setObserving(modelData)}}
                    }
                    Copy {text:"Ctrl+D cycles normal, dim and red. Dim/red mode affects OMANOVA only. Readable contrast is retained; lower your screen brightness separately if needed. Normal restores your chosen desktop/Observatory theme.";color:App.Palette.muted}
                    Copy { visible: App.Palette.missing; text: qsTr("Desktop colours unavailable or incomplete. Using Observatory colours until they return."); color: App.Palette.warning }
                    Copy { visible: App.Palette.error.length>0; text: App.Palette.error; color: App.Palette.warning }
                    RowLayout {
                        visible: page.trial && Quickshell.env("OMANOVA_THEME_TRIAL")==="1"
                        Action {text: qsTr("Your desktop theme");enabled:App.Palette.follow;onClicked:App.Palette.sample("desktop")}
                        Action {text: qsTr("Sample light");enabled:App.Palette.follow;onClicked:App.Palette.sample("light")}
                        Action {text: qsTr("Sample dark");enabled:App.Palette.follow;onClicked:App.Palette.sample("dark")}
                    }
                    Copy { visible: App.Palette.previewTheme.length>0; text: qsTr("Previewing sample colours. Your desktop theme has not changed.");color:App.Palette.warning }

                }
            }

            Card {
                visible: !page.compact && page.shows(4) && !!page.wallpaper
                implicitHeight: wallpaperSection.implicitHeight+32
                ColumnLayout {
                    anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:16
                    id: wallpaperSection

                    spacing: 6
                    readonly property var state: page.wallpaper?.state
                    readonly property bool waiting: page.wallpaper?.busy ?? false
                    Component.onCompleted: if (visible) page.wallpaper.request("status")
                    onVisibleChanged: if (visible && page.wallpaper) page.wallpaper.request("status")
                    Timer {
                        interval: 3500
                        repeat: true
                        running: wallpaperSection.visible && (page.wallpaper?.configured ?? false)
                        onTriggered: page.wallpaper.request("status")
                    }
                    Heading { text: qsTr("Mission Control wallpaper") }
                    GridLayout {
                        Layout.fillWidth:true;columns:width>=460?2:1;columnSpacing:14;rowSpacing:8
                        Image {
                            source:wallpaperSection.visible?"mission-control/assets/preview-polished.png":""
                            Layout.preferredWidth:Math.min(215,wallpaperSection.width)
                            Layout.preferredHeight:Math.min(215,wallpaperSection.width)*0.6
                            fillMode:Image.PreserveAspectFit;asynchronous:true
                            Accessible.name:qsTr("Mission Control wallpaper preview")
                        }
                        ColumnLayout {
                            Layout.fillWidth:true
                            RowLayout {
                                Layout.fillWidth:true
                                Copy {text:qsTr("Live wallpaper");font.bold:true}
                                App.StateSwitch {
                                    Accessible.name:qsTr("Live wallpaper")
                                    current:wallpaperSection.state?.running===true
                                    enabled:!wallpaperSection.waiting && !!page.wallpaper?.configured &&
                                        (wallpaperSection.state?.available===true || current)
                                    onRequestChange:page.wallpaper.request(current?"normal":"start")
                                }
                            }
                            RowLayout {
                                Layout.fillWidth:true
                                Copy {text:qsTr("Start at login")}
                                App.StateSwitch {
                                    Accessible.name:qsTr("Start at login")
                                    current:wallpaperSection.state?.autostart===true
                                    enabled:!wallpaperSection.waiting && wallpaperSection.state?.startupAvailable===true
                                    onRequestChange:page.wallpaper.request(current?"login-off":"login-on")
                                }
                            }
                        }
                    }
                    Copy {
                        text:wallpaperSection.waiting && page.wallpaper?.action==="setup"?qsTr("Building Mission Control…"):
                            page.wallpaper?.settling?qsTr("Changing wallpaper…"):wallpaperSection.state?.message || ""
                        visible:text.length>0;color:App.Palette.muted
                    }
                    Copy {
                        visible: page.wallpaper?.needsUpgrade === true
                        text: wallpaperSection.state?.running
                            ? qsTr("Use Restore desktop in Mission Control before updating it.")
                            : qsTr("Update Mission Control to get the new frame-rate controls.")
                        color: App.Palette.muted
                    }
                    Copy {
                        visible: wallpaperSection.state?.frameRate !== undefined
                        text: qsTr("Wallpaper frame rate")
                    }
                    ComboBox {
                        id: wallpaperRate
                        implicitContentWidthPolicy: ComboBox.WidestText
                        implicitWidth: Math.max(190, implicitContentWidth + leftPadding + rightPadding)
                        visible: wallpaperSection.state?.frameRate !== undefined
                        enabled: !wallpaperSection.waiting
                        Accessible.name: qsTr("Wallpaper frame rate")
                        palette.base: App.Palette.surface
                        palette.button: App.Palette.button
                        palette.text: App.Palette.ink
                        palette.buttonText: App.Palette.ink
                        palette.window: App.Palette.surface
                        palette.windowText: App.Palette.ink
                        palette.highlight: App.Palette.button
                        model: [qsTr("Smooth · 30 fps"), qsTr("Balanced · 15 fps"), qsTr("Battery saver · 5 fps"), qsTr("Still")]
                        readonly property var rates: [30, 15, 5, 0]
                        currentIndex: Math.max(0, rates.indexOf(wallpaperSection.state?.frameRate ?? 30))
                        onActivated: index => page.wallpaper.setPower("frameRate", rates[index])
                    }
                    Copy {
                        visible: wallpaperSection.state?.batteryRate !== undefined
                        text: qsTr("On battery")
                    }
                    ComboBox {
                        id: batteryRate
                        implicitContentWidthPolicy: ComboBox.WidestText
                        implicitWidth: Math.max(190, implicitContentWidth + leftPadding + rightPadding)
                        visible: wallpaperSection.state?.batteryRate !== undefined
                        enabled: !wallpaperSection.waiting
                        Accessible.name: qsTr("Wallpaper frame rate on battery")
                        palette.base: App.Palette.surface
                        palette.button: App.Palette.button
                        palette.text: App.Palette.ink
                        palette.buttonText: App.Palette.ink
                        palette.window: App.Palette.surface
                        palette.windowText: App.Palette.ink
                        palette.highlight: App.Palette.button
                        model: [qsTr("Use my usual setting"), qsTr("Battery saver · 5 fps"), qsTr("Still")]
                        readonly property var rates: [-1, 5, 0]
                        currentIndex: Math.max(0, rates.indexOf(wallpaperSection.state?.batteryRate ?? 5))
                        onActivated: index => page.wallpaper.setPower("batteryRate", rates[index])
                    }
                    Copy {
                        visible: wallpaperSection.state?.frameRate !== undefined
                        text: qsTr("Still stops continuous animation. The sky data still refreshes.")
                        color: App.Palette.muted
                    }
                    Copy {
                        text: qsTr("Turning it off restores your normal wallpaper and disables Mission Control login startup.")
                        color: App.Palette.muted
                    }
                    Action {
                        visible:page.wallpaper?.canSetup===true
                        text:page.wallpaper?.configured?qsTr("Update Mission Control"):qsTr("Set up Mission Control")
                        enabled:!wallpaperSection.waiting
                        onClicked:page.wallpaper.request("setup")
                    }
                    Copy {
                        visible: !!page.wallpaper?.error
                        text: page.wallpaper?.error || ""
                        color: App.Palette.warning
                    }
                }
            }

            Card {
                visible:page.shows(0)
                implicitHeight: placeForm.implicitHeight + 32
                ColumnLayout {
                    id: placeForm
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10
                    Heading { text: qsTr("Observing location") }
                    Copy {
                        text: page.sky.data?.place
                            ? (page.preferences.temporary ? qsTr("Temporary · %1") : qsTr("Active · %1"))
                                .arg(page.sky.data.place.name)
                            : qsTr("No active location")
                        color: App.Palette.accent
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        ComboBox {
                            id: saved
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            model: page.preferences.profiles
                            textRole: "name"
                            Accessible.name: qsTr("Saved locations")
                            palette.base: App.Palette.surface
                            palette.button: App.Palette.button
                            palette.text: App.Palette.ink
                            palette.buttonText: App.Palette.ink
                            palette.window: App.Palette.surface
                            palette.windowText: App.Palette.ink
                            palette.highlight: App.Palette.button
                        }
                        Action {
                            text: qsTr("Use saved")
                            enabled: !page.busy && saved.currentIndex >= 0
                            onClicked: page.sky.run(["use", page.preferences.profiles[saved.currentIndex].id])
                        }
                    }
                    Copy { text: qsTr("Optional city or postcode lookup sends only the text you enter to Open-Meteo/GeoNames when you press Search. It does not read your current coordinates. Place data: GeoNames."); color: App.Palette.muted }
                    RowLayout {
                        Field { id: lookupQuery; placeholderText: qsTr("City or postcode, optionally country"); maximumLength: 120 }
                        Action {
                            text: qsTr("Search online"); enabled: !lookup.running && !page.lookupCooling && !page.sky.fixture && lookupQuery.text.trim().length >= 2
                            onClicked: { page.lookupInput = JSON.stringify(lookupQuery.text.trim()) + "\n"; page.lookupRows = []; page.lookupMessage = "Searching…"; page.lookupCooling = true; lookup.stdinEnabled = true; lookup.running = true }
                        }
                    }
                    Copy { text: page.lookupMessage; visible: text.length > 0 }
                    Repeater {
                        model: page.lookupRows
                        Action {
                            required property var modelData
                            text: modelData.label
                            onClicked: { placeName.text = modelData.name; latitude.text = String(modelData.lat); longitude.text = String(modelData.lon); elevation.text = String(modelData.elevation); page.lookupRows = [] }
                        }
                    }
                    Field { id: placeName; maximumLength: 48; placeholderText: qsTr("Place name") }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: width < 330 ? 1 : 3
                        Field { id: latitude; maximumLength: 18; placeholderText: qsTr("Latitude") }
                        Field { id: longitude; maximumLength: 18; placeholderText: qsTr("Longitude") }
                        Field { id: elevation; maximumLength: 18; placeholderText: qsTr("Elevation m (optional)") }
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 8
                        Action {
                            text: qsTr("Save & use")
                            enabled: !page.busy && page.sky.supports("save-stdin")
                            onClicked: page.sky.run(["save-stdin"], [placeName.text, latitude.text, longitude.text, elevation.text])
                        }
                        Action {
                            text: qsTr("Use temporarily")
                            enabled: !page.busy && page.sky.supports("temporary-stdin")
                            onClicked: page.sky.run(["temporary-stdin"], [placeName.text, latitude.text, longitude.text, elevation.text])
                        }
                    }
                    Copy {
                        visible: !page.sky.supports("save-stdin") || !page.sky.supports("temporary-stdin")
                        text: qsTr("Update the runtime checkout and rerun ./setup-runtime to enter locations privately.")
                        color: App.Palette.warning
                    }
                }
            }

            Card {
                visible:page.shows(0)
                implicitHeight: units.implicitHeight + 32
                ColumnLayout {
                    id: units
                    anchors.fill: parent
                    anchors.margins: 16
                    Heading { text: qsTr("Distance units") }
                    Copy { text: page.sky.useMiles ? qsTr("Showing miles") : qsTr("Showing kilometres"); color: App.Palette.accent }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 8
                        Action {
                            text: qsTr("Kilometres")
                            enabled: !page.busy && page.sky.useMiles && page.sky.supports("distance-unit")
                            onClicked: page.sky.run(["distance-unit", "km"])
                        }
                        Action {
                            text: qsTr("Miles")
                            enabled: !page.busy && !page.sky.useMiles && page.sky.supports("distance-unit")
                            onClicked: page.sky.run(["distance-unit", "mi"])
                        }
                    }
                    Copy {
                        visible: !page.sky.supports("distance-unit")
                        text: qsTr("Update the runtime checkout and rerun ./setup-runtime, then reopen OMANOVA.")
                        color: App.Palette.warning
                    }
                }
            }

            Card {
                visible:page.shows(1)
                implicitHeight: downloads.implicitHeight + 32
                ColumnLayout {
                    id: downloads
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 9
                    RowLayout {
                        Layout.fillWidth:true
                        Heading {text:qsTr("Downloads")}
                        Action {text:qsTr("Refresh now");onClicked:page.sky.run(["refresh"])}
                    }
                    Copy {text:qsTr("Choose which sources can fetch new data.");color:App.Palette.muted}
                    Repeater {
                        model:[
                            {key:"online",label:qsTr("Orbital elements"),detail:qsTr("CelesTrak receives no observing coordinates.")},
                            {key:"weather",label:qsTr("Weather forecast"),detail:qsTr("Open-Meteo receives coordinates rounded to two decimal places.")},
                            {key:"launches",label:qsTr("Launch schedules"),detail:qsTr("Launch schedules and changes. Reopen the Observatory after changing this option.")},
                            {key:"aurora",label:qsTr("Aurora guidance"),detail:qsTr("NOAA forecasts. Reopen the Aurora tab after changing this option.")}
                        ]
                        ColumnLayout {
                            id:sourceRow
                            required property var modelData
                            Layout.fillWidth:true;spacing:12
                            Rectangle {Layout.fillWidth:true;implicitHeight:1;color:App.Palette.line}
                            RowLayout {
                                Layout.fillWidth:true;spacing:10
                                ColumnLayout {
                                    Layout.fillWidth:true;spacing:6
                                    Copy {text:sourceRow.modelData.label;font.bold:true;font.pixelSize:17}
                                    Copy {text:sourceRow.modelData.detail;color:App.Palette.muted}
                                    Copy {
                                        visible:sourceRow.modelData.key==="weather" && !!page.preferences.weather && !page.preferences.online
                                        text:qsTr("Opted in · downloads paused");color:App.Palette.warning
                                    }
                                }
                                App.StateSwitch {
                                    Accessible.name:sourceRow.modelData.label
                                    current:!!page.preferences[sourceRow.modelData.key]
                                    enabled:!page.busy && (!page.sky.fixture || page.trial) &&
                                        (["online","weather"].includes(sourceRow.modelData.key) || page.sky.supports(sourceRow.modelData.key))
                                    onRequestChange:page.sky.run([sourceRow.modelData.key,current?"off":"on"])
                                }
                            }
                            Item {implicitHeight:3}
                        }
                    }
                }
            }
            Card {
                visible:page.shows(2)
                implicitHeight: observing.implicitHeight + 32
                ObservingPreferences { id: observing; anchors.fill: parent; anchors.margins: 16; sky: page.sky }
            }
        }
    }
    Copy {
        Layout.leftMargin: page.gutter
        Layout.rightMargin: page.gutter
        Layout.bottomMargin: 12
        visible: text.length > 0
        text: page.sky.message
        color: App.Palette.warning
        Accessible.role: Accessible.StaticText
    }
}
