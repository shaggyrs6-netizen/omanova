import "./qml/Omanova" as App
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
    FloatingWindow {
        id: window
        title: "OMANOVA · Notification preview"
        implicitWidth: 640
        implicitHeight: 570
        minimumSize: Qt.size(360, 390)
        color: App.Palette.background
        onVisibleChanged: if (!visible) Qt.quit()

        Item {
            id: ui
            anchors.fill: parent
            readonly property string tool: Quickshell.env("OMASKY_ALERT_TOOL")
            readonly property string state: Quickshell.env("OMASKY_ALERT_STATE")
            readonly property var stationIds: [25544, 48274]
            readonly property var scenarios: ["favourable", "poor", "missing", "stale", "ended"]
            readonly property color ink: App.Palette.ink
            readonly property color muted: App.Palette.muted
            readonly property color accent: App.Palette.accent
            readonly property int margin: width < 480 ? 16 : 28
            property string result: "Preview alerts are off."

            function attempt() {
                if (runner.running || !consent.checked) return
                result = "Checking this simulated pass…"
                runner.command = [tool + "/.venv/bin/python", tool + "/observatory/notifications/preview.py",
                    state, "attempt", String(stationIds[station.currentIndex]),
                    scenarios[scenario.currentIndex], "on"]
                runner.running = true
            }

            Process {
                id: runner
                environment: ({ "OPENBLAS_NUM_THREADS": "1" })
                stdout: StdioCollector { id: output }
                onExited: function(code) {
                    ui.result = code === 0 ? output.text.trim() : "Preview helper could not complete the check."
                }
            }

            component Copy: Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: ui.ink
                font.family: "sans-serif"
                font.pixelSize: 15
            }
            component LabelledChoice: ComboBox {
                Layout.fillWidth: true
                palette.button: App.Palette.surface
                palette.buttonText: ui.ink
                palette.base: App.Palette.surface
                palette.text: ui.ink
                palette.highlight: ui.accent
            }

            ScrollView {
                id: scroll
                anchors.fill: parent
                clip: true
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    width: scroll.availableWidth
                    spacing: 14
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.margins: ui.margin
                        spacing: 8
                        Copy { text: "OMANOVA  /  OFFLINE FIXTURE"; color: ui.accent; font.pixelSize: 11; font.letterSpacing: 1.2 }
                        Copy { text: "Station alerts"; font.pixelSize: 36; font.weight: Font.DemiBold }
                        Copy { text: "Simulate a pass to try a real desktop notification. Sample alerts use a 15-minute lead and a favourable forecast."; color: ui.muted }
                    }
                    CheckBox {
                        id: consent
                        Layout.leftMargin: ui.margin
                        Layout.rightMargin: ui.margin
                        text: "Allow desktop alerts in this preview"
                        palette.text: ui.ink
                        palette.highlight: ui.accent
                        onToggled: ui.result = checked ? "Preview alerts enabled. Choose a scenario to simulate." : "Preview alerts are off."
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: ui.margin; Layout.rightMargin: ui.margin
                        spacing: 8
                        Copy { text: "Station fixture"; color: ui.muted }
                        LabelledChoice { id: station; model: ["ISS · Nashville", "Tiangong · Sydney"]; Accessible.name: "Station fixture" }
                        Copy { text: "Viewing scenario"; color: ui.muted }
                        LabelledChoice {
                            id: scenario
                            model: ["Favourable forecast", "Poor forecast", "Forecast missing", "Stale orbital elements", "Viewing window ended"]
                            Accessible.name: "Viewing scenario"
                        }
                    }
                    Button {
                        Layout.leftMargin: ui.margin
                        text: "Simulate pass"
                        enabled: consent.checked && !runner.running
                        palette.button: App.Palette.surface
                        palette.buttonText: ui.ink
                        focusPolicy: Qt.StrongFocus
                        onClicked: ui.attempt()
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.leftMargin: ui.margin; Layout.rightMargin: ui.margin; Layout.bottomMargin: ui.margin
                        implicitHeight: feedback.implicitHeight + 24
                        radius: 8
                        color: App.Palette.surface
                        border.color: App.Palette.line
                        Copy {
                            id: feedback
                            x: 12; y: 12
                            width: parent.width - 24
                            text: ui.result
                            Accessible.name: "Simulation result. " + text
                        }
                    }
                }
            }
        }
        IpcHandler {
            target: "omasky-notification-preview"
            function summary(): string { return JSON.stringify({ optedIn: consent.checked, result: ui.result }) }
            function close(): void { Qt.quit() }
        }
    }
}
