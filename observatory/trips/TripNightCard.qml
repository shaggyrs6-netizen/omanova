import "./qml/Omanova" as App
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Rectangle {
    id: card
    required property var site
    required property var night
    required property string side
    property string targetFilter: "All targets"
    readonly property string other: side === "home" ? "destination" : "home"
    Layout.fillWidth: true
    implicitHeight: body.implicitHeight+32
    color:App.Palette.surface;border.color:App.Palette.line;radius:12
    component Copy: Text { Layout.fillWidth:true;wrapMode:Text.Wrap;textFormat:Text.PlainText;color:App.Palette.ink;font.pixelSize:14 }
    ColumnLayout {
        id:body;anchors.fill:parent;anchors.margins:16;spacing:10
        Copy { text: card.side === "home" ? qsTr("HOME") : qsTr("DESTINATION");color:App.Palette.accent;font.pixelSize:12 }
        Copy { text: card.site.name;font.pixelSize:24;font.bold:true }
        Copy { text: card.site.timezone;color:App.Palette.muted }
        Copy { text: qsTr("%1 h astronomical darkness · %2 h dark and Moon below the natural horizon").arg(card.night.darkHours).arg(card.night.moonFreeHours) }
        Copy { text: qsTr("Moon %1% lit around the middle of this local night").arg(card.night.moonPercent);color:App.Palette.muted }
        Copy { text: card.site.weatherNote;color:App.Palette.muted }
        Repeater {
            model: card.night.targets.filter(t => card.targetFilter === "All targets" || t.name === card.targetFilter)
            ColumnLayout {
                required property var modelData
                Layout.fillWidth:true;spacing:7
                Rectangle { Layout.fillWidth:true;implicitHeight:1;color:App.Palette.line }
                Copy { text:modelData.name;font.pixelSize:20;font.bold:true }
                Copy { text:modelData.status;color:modelData.status === "Blocked by your horizon" ? App.Palette.warning : App.Palette.muted }
                Copy { visible:modelData.blockedMinutes>0;text:qsTr("About %1 minutes of this target's window removed by your skyline.").arg(modelData.blockedMinutes);color:App.Palette.warning }
                Repeater {
                    model:modelData.windows
                    ColumnLayout {
                        required property var modelData
                        Layout.fillWidth:true;spacing:5
                        Copy { text:qsTr("This place: %1 → %2").arg(modelData.start[card.side]).arg(modelData.end[card.side]);color:App.Palette.accent }
                        Copy { text:(card.other === "home" ? qsTr("Home clock: ") : qsTr("Destination clock: ")) + modelData.start[card.other] + " → " + modelData.end[card.other];color:App.Palette.muted;font.pixelSize:12 }
                        Copy { text:qsTr("Suggested look · %1 · %2° true · %3° up").arg(modelData.direction).arg(modelData.bearing).arg(modelData.altitude) }
                        Copy { text:modelData.look[card.side] + "\n" + (card.other === "home" ? qsTr("Home: ") : qsTr("Destination: ")) + modelData.look[card.other];color:App.Palette.muted;font.pixelSize:12 }
                        Copy { text:modelData.conditions.label + " · " + modelData.conditions.reason;color:modelData.conditions.label === "Poor" ? App.Palette.warning : App.Palette.muted }
                    }
                }
            }
        }
    }
}
