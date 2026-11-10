import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

Ui.BarWidget {
    id: root
    readonly property bool opened: popup.opened
    readonly property bool popoutSwitchClosing: popup.popoutSwitchClosing
    readonly property var poorPass: skyState.featured ? null : skyState.nextPoorIssPass()
    readonly property var station: skyState.featured || poorPass?.event || null
    readonly property var viewing: poorPass?.window || skyState.bestWindow(skyState.featured)
    readonly property string condition: viewing ? viewing.conditions.label : ""
    readonly property string glyph: condition === "Favourable" ? "●" : condition === "Mixed" ? "◐" : "◌"
    readonly property string countdown: viewing ? skyState.countdown(viewing.start.time) : ""
    implicitWidth: vertical ? barSize : label.implicitWidth + Style.space(14)
    implicitHeight: vertical && root.station && !skyState.snapshotStale ? Style.space(47) : barSize

    function openFallback() { skyState.reload(); popup.open() }
    function open() {
        if (skyState.fixture) {
            openFallback()
            return
        }
        popup.close()
        if (!launcher.running) launcher.running = true
    }
    function close() { popup.close() }
    function closeForPopoutSwitch() { popup.closeForPopoutSwitch() }

    SkyState { id: skyState }
    Process {
        id: launcher
        command: ["/usr/bin/bash", skyState.runtime + "/launch-observatory"]
        onExited: function(code) {
            if (code !== 0) root.openFallback()
        }
    }
    ShellIpc {
        target: "io.github.shaggyrs6-netizen.omanova"
        function compact(): bool {
            root.openFallback()
            return root.opened
        }
    }
    Ui.WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        labelVisible: false
        hasVisualContent: true
        tooltipText: (skyState.snapshotStale ? "OMANOVA · Data stale. Refresh or check the worker."
            : root.station ? ("OMANOVA · " + (root.station.source_id === 25544 ? "ISS" : "Tiangong") + " · " + (root.condition === "Favourable" ? "Favourable" : root.condition === "Mixed" ? "Mixed" : root.condition === "Poor" ? "Poor visibility" : "Weather uncertain"))
            : "OMANOVA") + " · Click for Observatory · Middle-click for compact panel"
        onPressed: function(mouseButton) {
            if (mouseButton === Qt.LeftButton) root.open()
            else if (mouseButton === Qt.MiddleButton)
                root.opened ? root.close() : root.openFallback()
        }

        Text {
            id: label
            anchors.centerIn: parent
            textFormat: Text.PlainText
            opacity: skyState.snapshotStale ? 0.65 : 1
            text: root.station && !skyState.snapshotStale
                ? (root.vertical ? (root.station.name === "ISS" ? "ISS" : "CSS") + "\n" + root.countdown
                        + (root.poorPass ? "\nPoor" : "")
                   : root.glyph + "  " + root.station.name + " " + root.countdown
                        + (root.poorPass ? " · Poor visibility" : ""))
                : root.glyph
            horizontalAlignment: Text.AlignHCenter
            color: root.bar ? root.bar.barForeground : Commons.Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
        }
    }

    Ui.Panel {
        id: popup
        moduleName: root.moduleName
        manageIpc: false
        Ui.KeyboardPanel {
            id: card
            anchorItem: button
            bar: root.bar
            owner: root
            open: popup.opened && root.bar !== null
            focusTarget: loadedContent
            contentWidth: fittedContentWidth(Style.space(610))
            contentHeight: fittedContentHeight(Style.space(440), Style.space(440))
            content: Ui.PanelKeyCatcher {
                onCloseRequested: root.close()
                SkyPanel {
                    anchors.fill: parent
                    sky: skyState
                }
            }
        }
    }
}
