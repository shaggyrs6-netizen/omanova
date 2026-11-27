import "../qml/Omanova" as App
import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

Popup {
    id: share
    property string titleText
    property string detailText
    property string timingText
    property string dewText
    property string feedback: ""
    property bool sample: false
    property bool saving: false
    property var pendingImage: null
    modal: true
    closePolicy: Popup.CloseOnEscape
    focus: true
    width: Math.min(parent.width - 20, 610)
    height: Math.min(parent.height - 20, body.implicitHeight + 30)
    anchors.centerIn: parent
    padding: 12
    onOpened: feedback = ""
    background: Rectangle { color: App.Palette.surface; border.color: App.Palette.border; radius: 9 }
    function chooseFile() {
        if (saving) return
        saving = true
        if (!card.grabToImage(result => {
            pendingImage = result
            const folder = StandardPaths.writableLocation(StandardPaths.PicturesLocation)
            save.currentFolder = folder
            save.selectedFile = folder.toString().replace(/\/$/, "") + "/omanova-tonight.png"
            save.open()
        }, Qt.size(Math.round(card.width * 2), Math.round(card.height * 2)))) {
            feedback = qsTr("Could not render the observing card.")
            saving = false
        }
    }
    function saveImage(path) {
        feedback = pendingImage?.saveToFile(path) ? qsTr("PNG saved locally.") : qsTr("Could not save the PNG.")
        pendingImage = null
        saving = false
    }
    FileDialog {
        id: save
        title: qsTr("Save observing card")
        fileMode: FileDialog.SaveFile
        options: FileDialog.DontUseNativeDialog
        defaultSuffix: "png"
        nameFilters: [qsTr("PNG image (*.png)")]
        onAccepted: share.saveImage(decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, "")))
        onRejected: {
            share.pendingImage = null
            share.saving = false
        }
    }
    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true
        ColumnLayout {
            id: body
            width: parent.width
            spacing: 12
            component Line: Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                color: App.Palette.ink
                font.pixelSize: 16
            }
            Rectangle {
                id: card
                Layout.fillWidth: true
                implicitHeight: contents.implicitHeight + 42
                color: App.Palette.background
                radius: 8
                border.color: App.Palette.border
                ColumnLayout {
                    id: contents
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 21
                    spacing: 9
                    Line { text: "OMANOVA · " + (share.sample ? "SAMPLE NIGHT" : "TONIGHT"); color: App.Palette.accent; font.bold: true }
                    Line { text: share.titleText; font.pixelSize: 27; font.bold: true }
                    Line { text: share.detailText; visible: !!text }
                    Line { text: share.timingText; visible: !!text }
                    Line { text: share.dewText; visible: !!text }
                }
            }
            Text {
                Layout.fillWidth: true
                text: share.feedback || qsTr("Preview omits the saved location name and coordinates. Save a copy locally.")
                color: App.Palette.ink
                wrapMode: Text.Wrap
            }
            RowLayout {
                Layout.fillWidth: true
                App.ActionButton { text: qsTr("Save PNG…"); enabled: !share.saving; onClicked: share.chooseFile() }
                App.ActionButton { text: qsTr("Close preview"); onClicked: share.close() }
            }
        }
    }
}
