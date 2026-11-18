import "." as App
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "Framing.js" as Framing

Rectangle {
    id: panel
    required property var skyModel
    readonly property var profile: skyModel && !skyModel.equipmentInvalid ? skyModel.equipmentProfile : null
    readonly property var choices: [{name: null, label: "Manual / last estimate"}].concat(
        (profile?.opticalSetups || []).map(setup => ({name: setup.name, label: setup.name})))
    readonly property string activeName: profile?.activeOpticalSetup || ""
    readonly property var activeSetup: profile?.opticalSetups?.find(setup => setup.name === activeName)
    readonly property var fieldDeg: activeSetup ? activeSetup.fieldDeg : profile?.fieldOfViewDeg
    required property var extentDeg
    signal openEquipment()
    readonly property var comparison: Framing.compare(fieldDeg,extentDeg)
    readonly property bool available: comparison.ratio !== undefined
    readonly property string title: comparison.status === "fits" ? "Fits the saved field" :
        comparison.status === "edge" ? "Close to the field edge" :
        comparison.status === "wide" ? "Target is wider than the saved field" :
        comparison.status === "missing-field" ? "No valid field of view saved" : "Target size unavailable"

    Layout.fillWidth:true
    implicitHeight:content.implicitHeight+24
    color:App.Palette.background
    border.color:App.Palette.line
    radius:8

    function selectSetup(name) {
        return skyModel?.selectEquipmentSetup(name) ?? false
    }

    function angle(deg) {
        return deg < 0.1 ? (deg*60).toFixed(1)+"′" :
            Number(deg.toFixed(3)).toString()+"°"
    }

    component Copy: Text {
        Layout.fillWidth:true
        wrapMode:Text.Wrap
        textFormat:Text.PlainText
        font.pixelSize:14
        color:App.Palette.ink
    }
    ColumnLayout {
        id:content
        anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top
        anchors.margins:12
        spacing:7
        ComboBox {
            id: selector
            visible: panel.choices.length > 1
            enabled: !!panel.skyModel?.equipmentRuntime && !panel.skyModel?.changingSetup
            Layout.fillWidth: true
            Layout.maximumWidth: 360
            implicitHeight: 42
            model: panel.choices
            textRole: "label"
            currentIndex: Math.max(0, panel.choices.findIndex(choice => choice.name === panel.activeName))
            onActivated: index => {
                panel.selectSetup(panel.choices[index].name)
                // The saved profile confirms the switch and updates the binding.
                currentIndex = Qt.binding(() => Math.max(0, panel.choices.findIndex(choice => choice.name === panel.activeName)))
            }
            Accessible.name: "Observing setup"
            palette.base: App.Palette.field
            palette.button: App.Palette.button
            palette.window: App.Palette.surface
            palette.text: App.Palette.ink
            palette.buttonText: App.Palette.ink
            palette.windowText: App.Palette.ink
            palette.highlight: App.Palette.hover
            palette.highlightedText: App.Palette.ink
            background: Rectangle { radius: 6; color: App.Palette.button; border.color: selector.activeFocus ? App.Palette.accent : App.Palette.border }
            contentItem: Text {
                text: selector.displayText
                textFormat: Text.PlainText
                color: App.Palette.ink
                leftPadding: 12
                rightPadding: 28
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
            delegate: ItemDelegate {
                required property int index
                required property var modelData
                width: selector.width
                highlighted: selector.highlightedIndex === index
                contentItem: Text {
                    text: modelData.label
                    textFormat: Text.PlainText
                    color: App.Palette.ink
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }
        }
        Copy {
            visible: text !== ""
            text: panel.skyModel?.changingSetup ? "Switching setup…" : panel.skyModel?.setupError || ""
            color: App.Palette.warning
        }
        Copy {text:panel.title;font.bold:true;color:panel.comparison.status==="fits"?App.Palette.accent:App.Palette.warning}
        Copy {
            visible:panel.available
            text:panel.available?"Saved field "+panel.angle(panel.fieldDeg)+" · approximate target width "+panel.angle(panel.extentDeg):""
        }
        Canvas {
            id:plot
            Layout.fillWidth:true
            Layout.preferredHeight:142
            visible:panel.available
            readonly property color fieldInk:App.Palette.accent
            readonly property color targetInk:App.Palette.warning
            readonly property var model:panel.comparison
            onFieldInkChanged:requestPaint()
            onTargetInkChanged:requestPaint()
            onModelChanged:requestPaint()
            onWidthChanged:requestPaint()
            onHeightChanged:requestPaint()
            Accessible.role:Accessible.Graphic
            Accessible.name:"Centred angular size comparison. "+panel.title
            onPaint:{
                const c=getContext("2d")
                c.reset()
                if(!panel.available)return
                const r=Math.min(width,height)/2-10
                if(r<=0)return
                const cx=width/2, cy=height/2
                const fr=r*model.fieldFraction,tr=r*model.targetFraction
                if(fr>=2) {
                    c.globalAlpha=.10;c.fillStyle=fieldInk
                    c.beginPath();c.arc(cx,cy,fr,0,Math.PI*2);c.fill()
                    c.globalAlpha=1;c.strokeStyle=fieldInk;c.lineWidth=2
                    c.beginPath();c.arc(cx,cy,fr,0,Math.PI*2);c.stroke()
                }
                c.strokeStyle=targetInk;c.fillStyle=targetInk;c.lineWidth=1.6
                if(tr>=2) {
                    c.setLineDash([4,4]);c.beginPath();c.arc(cx,cy,tr,0,Math.PI*2);c.stroke()
                } else {
                    c.beginPath();c.arc(cx,cy,2,0,Math.PI*2);c.fill()
                }
                if(fr<2) {
                    c.setLineDash([]);c.fillStyle=fieldInk
                    c.beginPath();c.arc(cx,cy,2,0,Math.PI*2);c.fill()
                }
            }
        }
        Copy {
            visible:panel.available
            text:"Solid circle: saved field. Dashed circle: approximate target width. A very small circle appears as a dot."
            color:App.Palette.muted
        }
        Copy {
            visible:panel.available
            text:"Both are centred and shown at the same angular scale. This compares sizes only. Brightness, detail and rectangular camera framing can differ."
            color:App.Palette.muted
        }
        Copy {
            visible:!panel.available
            text:panel.comparison.status==="missing-field"?
                "Calculate the field from your telescope and eyepiece, or enter your true field of view in My Equipment and Sky.":
                "This object has no catalogue width for a size comparison."
            color:App.Palette.muted
        }
        App.ActionButton {text:panel.available?"Equipment settings":"Set field of view";onClicked:panel.openEquipment()}
    }
}
