import "../../qml/Omanova" as App
import "../../qml/Omanova/Framing.js" as Framing
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
Item {
    id:root
    readonly property string state:Quickshell.env("OMANOVA_EQUIPMENT_STATE")
    readonly property string runtime:Quickshell.env("OMANOVA_EQUIPMENT_RUNTIME")
    readonly property bool deployed:Quickshell.env("OMANOVA_EQUIPMENT_DEPLOYED")==="1"
    readonly property color backgroundColour:App.Palette.background
    Component.onCompleted:if(deployed)request("tick")
    property int section: 0
    property bool editorOpen:false
    property bool manualOpen:false
    readonly property var sections: [
        ["Equipment & sky","Gear and observing conditions"],
        ["Saved setups","Telescope, eyepiece and camera frames"],
        ["Suggestions","Matches for your observing profile"]
    ]
    readonly property string overlayName: activeSetup?.name || (savedField ? "Manual field" : "No overlay set")
    readonly property string overlaySize: activeSetup ? labelField(activeSetup) : savedField ? formatAngle(savedField) : ""
    property bool capabilitiesOpen:false
    property bool calculatorOpen:false
    property bool cameraOpen:false
    property string fieldNotice:""
    readonly property var scopeSpec: dataSet?.profile?.telescopeOptics?.telescopeMm ?? null
    readonly property var ocularSpec: dataSet?.profile?.telescopeOptics?.eyepieceMm ?? null
    readonly property var apparentSpec: dataSet?.profile?.telescopeOptics?.apparentDeg ?? null
    readonly property var savedField: dataSet?.profile?.fieldOfViewDeg ?? null
    readonly property var estimate: Framing.estimate(Framing.decimal(telescope.text),
                                                     Framing.decimal(eyepiece.text),
                                                     Framing.decimal(apparent.text))
    readonly property var setups: dataSet?.profile?.opticalSetups || []
    readonly property var activeSetup: setups.find(setup => setup.name === dataSet?.profile?.activeOpticalSetup)
    readonly property string setupName: nameInput.text.trim()
    readonly property var telescopeNameMatch: setups.find(setup => setup.name === setupName)
    readonly property bool existingName: !!telescopeNameMatch && !telescopeNameMatch.camera
    readonly property string photoName: cameraName.text.trim()
    readonly property var photoNameMatch: setups.find(setup => setup.name === photoName)
    readonly property bool knownCamera: !!photoNameMatch?.camera
    readonly property var cameraEstimate: Framing.cameraField(Framing.decimal(sensorWidth.text),
                                                             Framing.decimal(sensorHeight.text),
                                                             Framing.decimal(cameraFocal.text))
    readonly property bool canSaveCamera: !!dataSet && !helper.running && !!cameraEstimate && !!photoName &&
        (knownCamera || (!photoNameMatch && setups.length < 12))

    function opticsFromFields() {
        return {telescopeMm: Framing.decimal(telescope.text), eyepieceMm: Framing.decimal(eyepiece.text),
                apparentDeg: Framing.decimal(apparent.text)}
    }
    function saveEstimate() {
        if (!root.estimate) return
        root.request("save_field", {fieldOfViewDeg: root.estimate.field, telescopeOptics: opticsFromFields()},
                     "Estimated field saved.")
    }
    function saveNamedSetup() {
        if (!root.estimate || !root.setupName ||
                (!root.existingName && (root.telescopeNameMatch || root.setups.length >= 12))) return false
        root.request("save_setup", {name: root.setupName, optics: opticsFromFields()}, "Setup saved and selected.")
        return helper.running
    }
    function editSetup(setup) {
        nameInput.text = setup.name
        telescope.text = setup.optics.telescopeMm.toString()
        eyepiece.text = setup.optics.eyepieceMm.toString()
        apparent.text = setup.optics.apparentDeg.toString()
    }
    function saveCameraSetup() {
        if (!canSaveCamera) return false
        root.request("save_setup", {name: root.photoName, camera: {
            sensorWidthMm: Framing.decimal(sensorWidth.text), sensorHeightMm: Framing.decimal(sensorHeight.text),
            focalLengthMm: Framing.decimal(cameraFocal.text)}}, "Camera setup saved and selected.")
        return helper.running
    }
    function editCamera(setup) {
        cameraName.text = setup.name
        sensorWidth.text = setup.camera.sensorWidthMm.toString()
        sensorHeight.text = setup.camera.sensorHeightMm.toString()
        cameraFocal.text = setup.camera.focalLengthMm.toString()
    }
    function labelField(setup) {
        return setup.camera ? formatAngle(setup.widthDeg)+" × "+formatAngle(setup.heightDeg) : formatAngle(setup.fieldDeg)
    }
    function saveManualField() {
        const value=manualField.text.trim() ? Framing.decimal(manualField.text) : null
        if (value!==null && !Framing.fieldIsValid(value)) {
            root.fieldNotice="Enter a field of view from 0.01° to 180°, or leave it blank to clear it."
            return
        }
        root.request("save_field", {fieldOfViewDeg: value}, value===null?"Overlay field cleared.":"Manual field saved.")
    }
    function formatAngle(value) {return Number(value.toPrecision(4)).toString()+"°"}
    property var dataSet:null
    property string action:"tick"
    property string pending:""
    property string result:""
    property string fieldConfirmation:""
    function request(a,p,confirmation) {
        if(helper.running)return
        fieldConfirmation=confirmation||""
        if(fieldConfirmation)fieldNotice="Saving field…"
        action=a;pending=JSON.stringify(p||({}))+"\n";result="Updating…"
        helper.stdinEnabled=true;helper.running=true
    }
    function preference(k,v) {request("patch",{[k]:v})}
    function gear(k,on) {let g=dataSet.profile.gear.filter(v=>v!==k);if(on)g.push(k);preference("gear",g)}
    function when(t) {return t?Qt.formatDateTime(new Date(t),"ddd d MMM · HH:mm")+" local":"Unknown"}
    FileView {
        id:view;path:root.state+"/view.json";watchChanges:true;printErrors:false
        onFileChanged:reload()
        onLoaded:{try{root.dataSet=JSON.parse(text())}catch(e){root.result="Preview data unavailable."}}
    }
    Process {
        id:helper
        command:[root.runtime+"/.venv/bin/python",root.runtime+"/observatory/equipment/equipment.py","--state",root.state,root.action]
        environment:({"OPENBLAS_NUM_THREADS":"1"});stdinEnabled:true
        onStarted:{write(root.pending);root.pending="";stdinEnabled=false}
        stderr:StdioCollector {id:errors}
        onExited:function(code){if(root.fieldConfirmation)root.fieldNotice=code===0?root.fieldConfirmation:"Field could not be saved.";if(code===0)view.reload();else root.dataSet=null;root.result=code===0?(root.action==="tick"?"":root.deployed?"Profile updated locally.":"Saved in this preview only."):(errors.text.trim()||"Update unavailable. Try again.")}
    }
    Timer {interval:30000;repeat:true;running:!!root.dataSet&&!helper.running&&root.dataSet.source==="live";onTriggered:root.request("tick")}
        Rectangle {
            id:ui;anchors.fill:parent;color:App.Palette.background
            component Copy:Text {Layout.fillWidth:true;wrapMode:Text.Wrap;textFormat:Text.PlainText;color:App.Palette.ink;font.pixelSize:14}
            component Heading:Copy {font.pixelSize:26;font.bold:true}
            component Action:Button {
                id:b;implicitHeight:40;leftPadding:14;rightPadding:14
                contentItem:Text {text:b.text;textFormat:Text.PlainText;color:b.enabled?App.Palette.ink:App.Palette.muted;font.pixelSize:14;verticalAlignment:Text.AlignVCenter}
                background:Rectangle {radius:6;color:b.hovered?App.Palette.hover:App.Palette.button;border.color:b.activeFocus?App.Palette.accent:App.Palette.border}
            }
            component SpecField:Column {
                property alias text: input.text
                required property string label
                property bool numeric: true
                property int maximumLength: 20
                spacing:4
                Text { text:parent.label;color:App.Palette.ink;font.pixelSize:14 }
                TextField {
                    id:input;width:parent.width;height:40
                    color:App.Palette.ink;selectByMouse:true;maximumLength:parent.maximumLength
                    inputMethodHints:parent.numeric?Qt.ImhFormattedNumbersOnly:Qt.ImhNone
                    Accessible.name:parent.label
                    background:Rectangle {radius:5;color:App.Palette.field;border.color:input.activeFocus?App.Palette.accent:App.Palette.border}
                }
            }
            component Toggle:CheckBox {
                id:t;enabled:!!root.dataSet&&!helper.running
                padding:8;spacing:9
                contentItem:Text {text:t.text;textFormat:Text.PlainText;color:t.enabled?App.Palette.ink:App.Palette.muted;font.pixelSize:14;leftPadding:t.indicator.width+t.spacing;verticalAlignment:Text.AlignVCenter}
                indicator:Rectangle {x:t.leftPadding;y:(t.height-height)/2;implicitWidth:21;implicitHeight:21;radius:4;color:App.Palette.field;border.color:t.activeFocus?App.Palette.accent:App.Palette.border
                    Text {anchors.centerIn:parent;text:t.checked?"✓":"";color:App.Palette.accent;font.pixelSize:18}}
            }
            ScrollView {
                id:scroll;anchors.fill:parent;clip:true;contentWidth:availableWidth
                ColumnLayout {
                    width:scroll.availableWidth;spacing:12
                    Heading {Layout.margins:18;Layout.bottomMargin:0;text:"My Equipment and Sky"}
                    GridLayout {
                        id:panes
                        Layout.fillWidth:true;Layout.margins:16
                        columns:width>=720?2:1;rowSpacing:10;columnSpacing:12
                        App.ViewPanel {
                            appearance:"mission";Layout.fillWidth:true;Layout.preferredWidth:270
                            Layout.alignment:Qt.AlignTop;implicitHeight:nav.implicitHeight+28
                            ColumnLayout {
                                id:nav;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:14;spacing:8
                                ComboBox {
                                    visible:panes.columns===1;Layout.fillWidth:true
                                    model:root.sections.map(s=>s[0]);currentIndex:root.section
                                    Accessible.name:"Equipment section"
                                    palette.button:App.Palette.button;palette.buttonText:App.Palette.ink
                                    palette.base:App.Palette.field;palette.text:App.Palette.ink
                                    onActivated:index=>root.section=index
                                }
                                Repeater {
                                    model:root.sections
                                    Button {
                                        id:navButton
                                        required property var modelData
                                        required property int index
                                        visible:panes.columns===2
                                        Layout.fillWidth:true;implicitHeight:65;leftPadding:12;rightPadding:8
                                        Accessible.name:modelData[0];Accessible.selected:root.section===index
                                        onClicked:root.section=index
                                        background:Rectangle {
                                            radius:5;color:root.section===navButton.index?App.Palette.hover:navButton.hovered?App.Palette.field:"transparent"
                                            border.color:root.section===navButton.index||navButton.activeFocus?App.Palette.accent:"transparent"
                                        }
                                        contentItem:ColumnLayout {
                                            spacing:3
                                            Copy {text:navButton.modelData[0];font.bold:true;color:root.section===navButton.index?App.Palette.accent:App.Palette.ink}
                                            Copy {text:navButton.modelData[1];font.pixelSize:12;color:App.Palette.muted}
                                        }
                                    }
                                }
                                Rectangle {Layout.fillWidth:true;implicitHeight:1;color:App.Palette.line}
                                Copy {text:"Active overlay";color:App.Palette.muted}
                                Copy {text:root.overlayName;font.pixelSize:18;font.bold:true}
                                Copy {text:root.overlaySize;visible:!!text;color:App.Palette.accent}
                            }
                        }
                        App.ViewPanel {
                            appearance:"mission";Layout.fillWidth:true;Layout.preferredWidth:675;Layout.minimumWidth:0
                            Layout.alignment:Qt.AlignTop;implicitHeight:body.implicitHeight+34
                            ColumnLayout {
                                id:body;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:17;spacing:12
                                RowLayout {
                                    Layout.fillWidth:true
                                    Heading {text:root.sections[root.section][0]}
                                    Action {visible:root.section===1;text:root.editorOpen?"Close editor":"Add or edit setup"
                                        onClicked:{
                                            root.editorOpen=!root.editorOpen
                                            if(root.editorOpen && root.activeSetup){
                                                root.cameraOpen=!!root.activeSetup.camera;root.calculatorOpen=!root.cameraOpen
                                                if(root.cameraOpen)root.editCamera(root.activeSetup);else root.editSetup(root.activeSetup)
                                            }
                                        }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth:true;spacing:12;visible:root.section===0
                                    Copy {text:"My equipment · choose one or more";font.bold:true}
                                    GridLayout {
                                        Layout.fillWidth:true;columns:2;columnSpacing:24;rowSpacing:6
                                        Repeater {
                                            model:[{key:"eye",label:"Naked eye"},{key:"binoculars",label:"Binoculars"},{key:"telescope",label:"Telescope"},{key:"camera",label:"Camera"}]
                                            Toggle {required property var modelData;text:modelData.label;checked:root.dataSet?.profile?.gear?.includes(modelData.key)||false;onClicked:root.gear(modelData.key,checked)}
                                        }
                                    }
                                    Copy {text:"Equipment choices filter suggestions. A saved frame estimates the sky your camera covers. Exposure, tracking and faint-target detail still depend on your setup.";color:App.Palette.muted}

                                    Copy {text:"My sky";font.bold:true}
                                    Flow {
                                        Layout.fillWidth:true;spacing:8
                                        Repeater {
                                            model:[{key:"unknown",label:"Not sure"},{key:"bright",label:"Bright / urban"},{key:"moderate",label:"Moderate / suburban"},{key:"dark",label:"Dark / rural"}]
                                            Action {required property var modelData;text:(root.dataSet?.profile?.sky===modelData.key?"● ":"")+modelData.label;enabled:!helper.running&&!!root.dataSet;onClicked:root.preference("sky",modelData.key)}
                                        }
                                    }
                                    Copy {text:"Your description is a planning preference, not a measured darkness rating. Cloud, Moon, glare and your horizon can still limit a sighting.";color:App.Palette.muted}

                                    Action {text:root.capabilitiesOpen?"Hide equipment details":"Optional equipment details";onClicked:root.capabilitiesOpen=!root.capabilitiesOpen}
                                    ColumnLayout {visible:root.capabilitiesOpen;Layout.fillWidth:true;spacing:8
                                        Copy {text:"Aperture (20–600 mm), binocular power (2–30×). Leave unknown values blank.";color:App.Palette.muted}
                                        Flow {Layout.fillWidth:true;spacing:8
                                            TextField {id:aperture;width:145;placeholderText:"Aperture mm";text:root.dataSet?.profile?.apertureMm??"";color:App.Palette.ink;placeholderTextColor:App.Palette.muted;selectByMouse:true;background:Rectangle {color:App.Palette.field;border.color:App.Palette.border;radius:5}}
                                            TextField {id:power;width:145;placeholderText:"Binocular ×";text:root.dataSet?.profile?.binocularMagnification??"";color:App.Palette.ink;placeholderTextColor:App.Palette.muted;selectByMouse:true;background:Rectangle {color:App.Palette.field;border.color:App.Palette.border;radius:5}}
                                            Action {text:"Save details";enabled:!!root.dataSet&&!helper.running;onClicked:{let p={};p.apertureMm=aperture.text.trim()?Number(aperture.text):null;p.binocularMagnification=power.text.trim()?Number(power.text):null;if([p.apertureMm,p.binocularMagnification].some(v=>v!==null&&!Number.isFinite(v))){root.result="Enter numbers or leave unknown values blank.";return}root.request("patch",p)}}
                                        }
                                        Flow {Layout.fillWidth:true;spacing:8
                                            Repeater {model:["unknown","widefield","tracked"];Action {required property string modelData;text:(root.dataSet?.profile?.cameraMode===modelData?"● ":"")+"Camera: "+modelData;enabled:!!root.dataSet&&!helper.running;onClicked:root.preference("cameraMode",modelData)}}
                                        }
                                        Copy {text:"Sky Finder compares your field of view with target size. Aperture/power/camera mode are recorded as context, not a promise of limiting magnitude, exposure or resolved detail. Equipment preferences also filter Overview and new calendar/offline selections; saved guides retain their original snapshot.";color:App.Palette.muted}
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth:true;spacing:12;visible:root.section===1
                                    Flow {
                                        Layout.fillWidth:true;spacing:7
                                        Repeater {
                                            model:root.setups
                                            Action {
                                                required property var modelData
                                                width:Math.min(implicitWidth,parent.width)
                                                text:(root.activeSetup?.name===modelData.name?"● ":"")+modelData.name
                                                Accessible.name:modelData.name
                                                enabled:!helper.running
                                                onClicked:{
                                                    root.request("select_setup",{name:modelData.name},"Setup selected.")
                                                    if(root.editorOpen) {
                                                        root.cameraOpen=!!modelData.camera;root.calculatorOpen=!root.cameraOpen
                                                        if(root.cameraOpen)root.editCamera(modelData);else root.editSetup(modelData)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    Copy {text:root.overlayName;font.pixelSize:22;font.bold:true}
                                    GridLayout {
                                        visible:!!root.overlaySize;Layout.fillWidth:true;columns:width>=400?2:1;columnSpacing:15
                                        ColumnLayout {
                                            Layout.fillWidth:true
                                            Copy {text:root.activeSetup?.camera?"Camera frame":root.activeSetup?"Telescope and eyepiece":"Manual field";font.bold:true}
                                            Repeater {
                                                model:root.activeSetup?.camera ?
                                                    ["Sensor width    "+root.activeSetup.camera.sensorWidthMm+" mm","Sensor height    "+root.activeSetup.camera.sensorHeightMm+" mm","Focal length    "+root.activeSetup.camera.focalLengthMm+" mm"] :
                                                    root.activeSetup?.optics ? ["Telescope    "+root.activeSetup.optics.telescopeMm+" mm","Eyepiece    "+root.activeSetup.optics.eyepieceMm+" mm","Apparent field    "+root.activeSetup.optics.apparentDeg+"°"] : []
                                                Copy {required property string modelData;text:modelData;color:App.Palette.muted}
                                            }
                                        }
                                        Rectangle {
                                            Layout.fillWidth:true;Layout.preferredWidth:200;implicitHeight:145
                                            color:App.Palette.field;border.color:App.Palette.line;radius:5
                                            Item {
                                                anchors {fill:parent;margins:13;bottomMargin:40}
                                                Rectangle {
                                                    readonly property real ratio:root.activeSetup?.camera ? root.activeSetup.camera.sensorWidthMm/root.activeSetup.camera.sensorHeightMm : 1
                                                    anchors.centerIn:parent;width:Math.min(parent.width,parent.height*ratio);height:width/ratio
                                                    radius:root.activeSetup?.camera?0:width/2
                                                    color:App.Palette.shade;border.color:App.Palette.accent
                                                    Text {anchors.centerIn:parent;text:"+";color:App.Palette.muted}
                                                }
                                            }
                                            Text {anchors.horizontalCenter:parent.horizontalCenter;anchors.bottom:parent.bottom;anchors.bottomMargin:10;text:root.overlaySize;color:App.Palette.accent;font.bold:true}
                                        }
                                    }
                                    Copy {visible:!root.overlaySize;text:"Add a telescope or camera setup, or enter a manual field of view.";color:App.Palette.muted}

                                    ColumnLayout {
                                        Layout.fillWidth:true;spacing:12;visible:root.editorOpen
                                        Action {
                                            text:root.calculatorOpen?"Hide telescope calculator":"Calculate from telescope and eyepiece"
                                            onClicked:{root.calculatorOpen=!root.calculatorOpen;if(root.calculatorOpen)root.cameraOpen=false}
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth:true;visible:root.calculatorOpen;spacing:7
                                            Copy {text:"Use the effective telescope focal length if you use a Barlow or focal reducer. Use the eyepiece’s apparent field for the third value.";color:App.Palette.muted}
                                            Flow {
                                                Layout.fillWidth:true;spacing:8
                                                SpecField {id:telescope;width:200;label:"Telescope focal length (mm)";text:root.scopeSpec??""}
                                                SpecField {id:eyepiece;width:200;label:"Eyepiece focal length (mm)";text:root.ocularSpec??""}
                                                SpecField {id:apparent;width:215;label:"Eyepiece apparent field (°)";text:root.apparentSpec??""}
                                            }
                                            Copy {
                                                text:root.estimate?"Estimated true field: "+root.formatAngle(root.estimate.field)+" · "+
                                                    Number(root.estimate.magnification.toPrecision(3))+"× magnification":
                                                    "Enter all three specs for an estimate (supported field: 0.01° to 180°)."
                                                color:root.estimate?App.Palette.accent:App.Palette.muted
                                            }
                                            Action {text:"Use estimated field without naming it";enabled:!!root.dataSet&&!helper.running&&!!root.estimate;onClicked:root.saveEstimate()}
                                            SpecField {id:nameInput;width:240;label:"Setup name";numeric:false;maximumLength:48}
                                            Flow {
                                                Layout.fillWidth:true;spacing:8
                                                Action {
                                                    text:root.existingName?"Update and use setup":"Save and use setup"
                                                    enabled:!!root.dataSet&&!helper.running&&!!root.estimate&&!!root.setupName&&
                                                        (root.existingName||(!root.telescopeNameMatch&&root.setups.length<12))
                                                    onClicked:root.saveNamedSetup()
                                                }
                                                Action {
                                                    visible:root.existingName
                                                    text:"Remove named setup"
                                                    enabled:!helper.running
                                                    onClicked:root.request("remove_setup",{name:root.setupName},"Setup removed.")
                                                }
                                            }
                                            Copy {
                                                visible:text!==""
                                                text:root.telescopeNameMatch?.camera ? "This name is used by a camera setup." :
                                                    root.setups.length>=12 ? "All 12 setup slots are in use. Edit or remove a saved setup." : ""
                                                color:App.Palette.muted
                                            }
                                            Flow {
                                                Layout.fillWidth:true;spacing:8
                                                Repeater {
                                                    model:root.setups.filter(setup=>!setup.camera)
                                                    Action {
                                                        required property var modelData
                                                        text:modelData.name
                                                        enabled:!helper.running
                                                        onClicked:root.editSetup(modelData)
                                                    }
                                                }
                                            }
                                        }
                                        Action {
                                            text:root.cameraOpen?"Hide camera calculator":"Calculate camera frame"
                                            onClicked:{root.cameraOpen=!root.cameraOpen;if(root.cameraOpen)root.calculatorOpen=false}
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth:true;visible:root.cameraOpen;spacing:8
                                            Copy {
                                                text:"Use the sensor’s active width and height in millimetres and the actual focal length of the lens or telescope."
                                                color:App.Palette.muted
                                            }
                                            Flow {
                                                Layout.fillWidth:true;spacing:8
                                                SpecField {id:sensorWidth;width:205;label:"Sensor width (mm)"}
                                                SpecField {id:sensorHeight;width:205;label:"Sensor height (mm)"}
                                                SpecField {id:cameraFocal;width:205;label:"Focal length (mm)"}
                                            }
                                            Copy {
                                                text:root.cameraEstimate ? "Estimated camera frame: "+root.formatAngle(root.cameraEstimate.width)+
                                                    " wide × "+root.formatAngle(root.cameraEstimate.height)+" high" :
                                                    "Enter positive dimensions and focal length to calculate the frame."
                                                color:root.cameraEstimate?App.Palette.accent:App.Palette.muted
                                            }
                                            SpecField {id:cameraName;width:240;label:"Camera setup name";numeric:false;maximumLength:48}
                                            Flow {
                                                Layout.fillWidth:true;spacing:8
                                                Action {
                                                    text:root.knownCamera?"Update and use camera setup":"Save and use camera setup"
                                                    enabled:root.canSaveCamera
                                                    onClicked:root.saveCameraSetup()
                                                }
                                                Action {
                                                    visible:root.knownCamera
                                                    text:"Remove camera setup"
                                                    enabled:!helper.running
                                                    onClicked:root.request("remove_setup",{name:root.photoName},"Camera setup removed.")
                                                }
                                            }
                                            Copy {
                                                visible:text!==""
                                                text:root.photoNameMatch&&!root.knownCamera ? "This name is used by a telescope setup." :
                                                    root.setups.length>=12 ? "All 12 setup slots are in use. Edit or remove a saved setup." : ""
                                                color:App.Palette.muted
                                            }
                                            Flow {
                                                Layout.fillWidth:true;spacing:8
                                                Repeater {
                                                    model:root.setups.filter(setup=>!!setup.camera)
                                                    Action {
                                                        required property var modelData
                                                        text:modelData.name
                                                        enabled:!helper.running
                                                        onClicked:root.editCamera(modelData)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    Action {text:root.manualOpen?"Hide manual field":"Manual field of view";onClicked:root.manualOpen=!root.manualOpen}
                                    Flow {
                                        visible:root.manualOpen
                                        Layout.fillWidth:true;spacing:8
                                        SpecField {id:manualField;width:200;label:"Manual true field (°)";text:root.savedField??""}
                                        Action {text:"Save manual field";enabled:!!root.dataSet&&!helper.running;onClicked:root.saveManualField()}
                                    }

                                    Copy {visible:!!root.fieldNotice;text:root.fieldNotice;color:App.Palette.accent}
                                }
                                ColumnLayout {
                                    Layout.fillWidth:true;spacing:12;visible:root.section===2
                                    Flow {
                                        Layout.fillWidth:true;spacing:10;visible:!root.deployed
                                        Action {text:root.dataSet?.source==="sample"?"● Public examples":"Public examples";enabled:!helper.running;onClicked:root.request("source",{source:"sample"})}
                                        Action {text:root.dataSet?.source==="live"?"● Live suggestions · read-only":"Live suggestions · read-only";enabled:!helper.running;onClicked:root.request("source",{source:"live"})}
                                    }
                                    Copy {text:root.dataSet?.source==="live"?"READ-ONLY LIVE SNAPSHOT · Rechecks local planner data every 30 seconds. No new downloads, alerts or live setting changes.":"SIMULATED EXAMPLES · Fixed sample clock: "+root.when(root.dataSet?.clock)+". These are filter exercises, not tonight’s predictions.";color:App.Palette.warning}

                                    Flow {
                                        Layout.fillWidth:true;spacing:10
                                        Toggle {text:"Filter suggestions";checked:root.dataSet?.profile?.filter===true;onClicked:root.preference("filter",checked)}
                                        Toggle {text:"Include uncertain matches";checked:root.dataSet?.profile?.uncertain===true;onClicked:root.preference("uncertain",checked)}
                                        Toggle {text:"Inspect filtered-out entries";checked:root.dataSet?.profile?.showExcluded===true;onClicked:root.preference("showExcluded",checked)}
                                    }
                                    Copy {text:(root.dataSet?.counts?.shown||0)+" shown / "+(root.dataSet?.counts?.total||0)+" total · "+(root.dataSet?.counts?.eligible||0)+" eligible after profile · "+(root.dataSet?.counts?.uncertain||0)+" uncertain · "+(root.dataSet?.counts?.excluded||0)+" filtered";color:App.Palette.accent}

                                    Repeater {
                                        model:root.dataSet?.rows||[]
                                        Rectangle {
                                            id:card;required property var modelData
                                            Layout.fillWidth:true;Layout.minimumWidth:0
                                            implicitHeight:body.implicitHeight+32;radius:10;color:App.Palette.surface;border.color:modelData.excluded?App.Palette.line:App.Palette.border
                                            ColumnLayout {
                                                id:body;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:16;spacing:8
                                                Copy {text:card.modelData.kind.toUpperCase()+" · "+card.modelData.profileBadge;color:card.modelData.eligible?App.Palette.good:App.Palette.warning;font.pixelSize:12;font.bold:true}
                                                Heading {text:card.modelData.name;font.pixelSize:22}
                                                Copy {text:root.when(card.modelData.start)+" – "+Qt.formatDateTime(new Date(card.modelData.end),"HH:mm")+" · "+(card.modelData.look.direction||"Direction unknown")+" · "+(card.modelData.look.el===null?"altitude unknown":Math.round(card.modelData.look.el)+"° up")}
                                                Copy {text:"Source visibility: "+card.modelData.visibility+" · Weather: "+card.modelData.conditions.label+" · "+(card.modelData.eligible?"Eligible after profile checks":"Inspect only / not an eligible suggestion");color:App.Palette.muted}
                                                Copy {text:card.modelData.notes.join("\n");color:App.Palette.muted}
                                                Copy {visible:!!card.modelData.safety;text:card.modelData.safety;color:App.Palette.warning}
                                                Action {visible:!!card.modelData.source;text:card.modelData.restricted?"Read solar safety guidance":"Open source guidance";onClicked:Qt.openUrlExternally(card.modelData.source)}
                                            }
                                        }
                                    }
                                    Copy {visible:!root.dataSet?.rows?.length;text:"No suggestions match these choices. Try another equipment choice or inspect filtered-out entries."}
                                    Copy {text:root.dataSet?.limits||"";color:App.Palette.muted}
                                }
                                Copy {visible:!!root.result;text:root.result;color:App.Palette.muted}
                                Copy {visible:!!root.dataSet?.error;text:root.dataSet?.error||"";color:App.Palette.warning}
                            }
                        }
                    }
                }
            }
        }
        IpcHandler {
            target:"omanova-equipment"
            function summary():string {return JSON.stringify({source:root.dataSet?.source,profile:root.dataSet?.profile,counts:root.dataSet?.counts,busy:helper.running,error:root.dataSet?.error})}
            function sampleProfile(value:string):void {if(root.dataSet?.source==="sample")root.request("save",JSON.parse(value))}
            function sampleField(scope:string,ocular:string,afov:string,manual:string):bool {
                if(root.deployed || root.dataSet?.source!=="sample" || helper.running)return false
                if(manual!=="estimate") {
                    manualField.text=manual
                    root.saveManualField()
                    return helper.running
                }
                root.calculatorOpen=true
                telescope.text=scope;eyepiece.text=ocular;apparent.text=afov
                root.saveEstimate()
                return helper.running
            }
            function sampleSaveSetup(name:string, scope:string, ocular:string, afov:string):bool {
            if(root.deployed || root.dataSet?.source!=="sample" || helper.running)return false
            root.calculatorOpen=true
            nameInput.text=name;telescope.text=scope;eyepiece.text=ocular;apparent.text=afov
            return root.saveNamedSetup()
        }
        function sampleSaveCamera(name:string, wide:string, high:string, focal:string):bool {
            if(root.deployed || root.dataSet?.source!=="sample" || helper.running)return false
            root.cameraOpen=true;root.calculatorOpen=false
            cameraName.text=name;sensorWidth.text=wide;sensorHeight.text=high;cameraFocal.text=focal
            return root.saveCameraSetup()
        }
        function capture():void {if(root.dataSet?.source==="sample")ui.grabToImage(r=>r.saveToFile(root.state+"/sample.png"))}
        }
}
