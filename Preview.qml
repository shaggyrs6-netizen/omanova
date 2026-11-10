import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons

ShellRoot {
    FloatingWindow {
        id: preview
        title: "OMANOVA · Isolated fixture preview"
        implicitWidth: 610
        implicitHeight: 490
        color: Commons.Color.background
        onVisibleChanged: if (!visible) Qt.quit()

        QtObject {
            id: fixtureBar
            property bool vertical: false
            property string position: "top"
            property int barSize: Style.bar.sizeHorizontal
            property color barForeground: Commons.Color.foreground
            property color urgent: Commons.Color.urgent
            property string fontFamily: Style.font.family
            property bool foregroundAnimationEnabled: false
            property var activePopout: null
            function requestPopout(item) { activePopout = item }
            function releasePopout(item) { if (activePopout === item) activePopout = null }
            function showTooltip(item, text) {}
            function hideTooltip(item) {}
        }

        SkyState { id: state }
        Rectangle {
            id: frame
            anchors.centerIn: parent
            width: Math.min(640, parent.width)
            height: Math.min(480, parent.height)
            color: Commons.Color.background
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                BarWidget {
                    id: widget
                    moduleName: "local.omasky"
                    bar: fixtureBar
                    Layout.alignment: Qt.AlignRight
                }
                SkyPanel {
                    id: panel
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    sky: state
                }
            }
        }

        IpcHandler {
            target: "omasky-preview"
            function tab(index: int): void { panel.tabIndex = index }
            function station(): string { return panel.selected ? panel.selected.name : "none" }
            function label(): string { return widget.countdown }
            function popup(show: bool): bool {
                if (show) widget.open()
                else widget.close()
                return widget.opened
            }
            function temporary(): void { state.run(["temporary-stdin"], ["Fixture test", "-33.87", "151.21", "0"]) }
            function place(): string { return state.data && state.data.place ? state.data.place.name : "none" }
            function restore(): void { state.run(["use", state.data.settings.profiles[0].id]) }
            function capture(name: string): void {
                if (["overview", "compass"].includes(name))
                    frame.grabToImage(result => result.saveToFile(state.directory + "/" + name + ".png"))
            }
        }
    }
}
