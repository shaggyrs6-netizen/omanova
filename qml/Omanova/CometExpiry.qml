import "." as App
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

Text {
    id: warning
    required property string runtime
    property double clock: Date.now()
    property double clockOverride: NaN
    readonly property double now: Number.isFinite(clockOverride) ? clockOverride : clock
    property double expiry: NaN
    readonly property bool expired: Number.isFinite(expiry) && now >= expiry
    visible: Number.isFinite(expiry) && expiry - now <= 14 * 86400000
    Layout.fillWidth: true
    color: App.Palette.warning
    font.pixelSize: 14
    wrapMode: Text.Wrap
    text: expired ? qsTr("Comet catalogue expired. Install an update with refreshed data.")
                  : qsTr("Comet catalogue expires %1. Check for a refreshed release.")
                    .arg(Qt.formatDateTime(new Date(expiry), "ddd d MMM yyyy · HH:mm"))
    Accessible.role: Accessible.StaticText
    Accessible.name: text

    Timer {
        interval: 60000
        running: warning.visible || Number.isFinite(warning.expiry)
        repeat: true
        onTriggered: warning.clock = Date.now()
    }
    FileView {
        path: warning.runtime ? warning.runtime + "/observatory/comets/catalog.json" : ""
        printErrors: false
        onLoaded: {
            try { warning.expiry = Date.parse(JSON.parse(text()).until) }
            catch (error) { warning.expiry = NaN }
        }
        onLoadFailed: warning.expiry = NaN
    }
}
