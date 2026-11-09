import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
    FloatingWindow {
        title: qsTr("Omasky Observatory · Bright satellite watchlist preview")
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
            WatchlistPage { id: page; width: scroll.availableWidth }
        }
        Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
        IpcHandler {
            target: "omasky-watchlist-preview"
            function summary(): string {
                return JSON.stringify({ fixture: page.catalog?.fixture, usable: page.catalog?.targets.filter(t => t.usable).length,
                    windows: page.visibleWindows.length, error: page.catalog?.error })
            }
        }
    }
}
