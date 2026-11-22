import "." as App
import QtQuick
import QtQuick.Layouts

App.ViewPanel {
    id: panel
    appearance: "mission"
    Layout.fillWidth: true
    Layout.minimumWidth: 0
    Layout.preferredWidth: 1
    Layout.alignment: Qt.AlignTop
    implicitHeight: body.implicitHeight + 32
    default property alias contents: body.data
    property alias spacing: body.spacing
    property ColumnLayout bodyItem: ColumnLayout {
        id: body
        parent: panel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        spacing: 9
    }
}
