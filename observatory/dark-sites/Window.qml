import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

ShellRoot {
    FloatingWindow {
        title: qsTr("Omasky Observatory · Dark-sky sites preview")
        color: "#070d1b"
        implicitWidth: 860
        implicitHeight: 740
        minimumSize: Qt.size(380, 420)
        onVisibleChanged: if (!visible) Qt.quit()

        ScrollView {
            id: scroll
            anchors.fill: parent
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            clip: true
            DarkSitesPage { id: page; width: scroll.availableWidth }
        }
        Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
        IpcHandler {
            target: "omasky-dark-sites-preview"
            function filter(dropIn: bool): void { page.dropInOnly = dropIn }
            function summary(): string {
                return JSON.stringify({ sites: page.visibleSites.map(site => site.name),
                    dropIn: page.dropInOnly, checked: page.catalog?.checked })
            }
        }
    }
}
