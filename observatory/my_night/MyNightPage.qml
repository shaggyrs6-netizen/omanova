import "../../qml/Omanova" as App
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: page
    required property var sky
    signal recordObservation(var selected)
    signal openEquipment()
    property string framingId:""
    property var result: null
    property string problem: ""
    property string notice: ""
    property string guide: ""
    property bool configureOpen: false
    property bool catalogueOpen: false
    readonly property var pick: result?.rows?.find(r => r.id === selected) || null
    function timeOf(stamp) { return stamp?.match(/· (\d{2}:\d{2})/)?.[1] || "—" }
    function dayOf(stamp) { return stamp ? stamp.split(" · ")[0] : "" }
    property string selected: ""
    property string pending: ""
    property string action: ""
    property bool editing: false
    property bool requestPending: false
    readonly property bool busy: requestPending || helper.running
    readonly property var sources: [
        {id:"active",label:"Active location"},
        {id:"trip-home",label:"Trip Home"},
        {id:"trip-destination",label:"Trip destination"}
    ]
    readonly property string state: Quickshell.env("OMANOVA_MY_NIGHT_STATE")
    readonly property string runtime: Quickshell.env("OMANOVA_FIELD_RUNTIME")
    readonly property bool ready: !!result && !problem && !editing && !busy
    readonly property string activePlace: JSON.stringify(sky.data?.place || {})
    onActivePlaceChanged: if (visible && result && !editing) request("view")
    function request(verb, args) {
        if (busy || !state) return false
        action=verb
        problem=""
        notice=""
        pending=JSON.stringify(Object.assign({action:verb,selected:selected},args||{}))+"\n"
        requestPending=true
        helper.stdinEnabled=true
        helper.running=true
        return true
    }
    function add(kind, key) {
        if (busy) {
            notice="My Night is updating. Try adding this pick again in a moment."
            return false
        }
        return request("add",{kind:kind,key:key})
    }
    function showPick(id) { if (!busy) {selected=id;request("view")} }
    onVisibleChanged: if (visible && !busy) request("view")
    Component.onCompleted: if (visible && !busy && !result) request("view")
    Timer {interval:60000;repeat:true;running:page.visible;onTriggered:if(!page.editing)page.request("view")}
    Process {
        id: helper
        command:[page.runtime+"/.venv/bin/python","-B",page.runtime+"/observatory/my_night/plan.py",
                 "--state",page.state,"--data",page.sky.directory,"--offline",Quickshell.env("OMANOVA_OFFLINE_STATE")].concat(page.sky.fixture?["--fixture"]:[])
        environment:({"OPENBLAS_NUM_THREADS":"1"})
        stdout:StdioCollector {id:response}
        onStarted:{write(page.pending);stdinEnabled=false}
        onExited: function(code) {
            page.requestPending=false
            try {
                const data=JSON.parse(response.text)
                if (code!==0 || data.failure) {
                    page.problem=data.failure || "Could not update My Night."
                    return
                }
                page.result=data
                page.selected=data.selected || ""
                if (!page.editing || page.action==="configure") {
                    dateField.text=data.plan.night
                    placeList.currentIndex=page.sources.findIndex(s=>s.id===data.plan.source)
                    page.editing=false
                }
                if (data.guide) {
                    page.guide=data.guide
                    page.notice="Saved "+data.savedCount+" cards to Offline Cards."
                        +(data.savedCount<data.rows.length?" Picks without a usable window or excluded by your equipment settings were skipped.":"")
                } else if (page.action==="add") {
                    page.notice="Pick saved. Timing follows the night and location shown below."
                }
            } catch (e) {
                page.problem="Could not read My Night. Saved picks remain on disk."
            }
        }
    }

    component Copy: Text {
        Layout.fillWidth:true
        color:App.Palette.ink
        font.pixelSize:14
        textFormat:Text.PlainText
        wrapMode:Text.Wrap
    }
    component Choice: ComboBox {
        implicitHeight:42
        palette.base:App.Palette.field
        palette.button:App.Palette.button
        palette.window:App.Palette.surface
        palette.text:App.Palette.ink
        palette.buttonText:App.Palette.ink
        palette.windowText:App.Palette.ink
        palette.highlight:App.Palette.hover
        palette.highlightedText:App.Palette.ink
        background:Rectangle {radius:6;color:App.Palette.button;border.color:parent.activeFocus?App.Palette.accent:App.Palette.border}
    }
    ScrollView {
        id:scroll
        anchors.fill:parent
        contentWidth:availableWidth
        clip:true
        ColumnLayout {
            width:scroll.availableWidth
            spacing:12
            ColumnLayout {
                Layout.fillWidth:true
                Layout.margins:22
                spacing:10
                RowLayout {
                    Layout.fillWidth:true
                    Copy {text:"My Night";font.bold:true;font.pixelSize:30}
                    App.ActionButton {text:page.configureOpen?"Hide settings":"Night & location";onClicked:page.configureOpen=!page.configureOpen}
                }
                Copy {text:[page.result?.place,page.result?.plan?.night,page.result?.zone].filter(Boolean).join("   ·   ");color:App.Palette.muted}
                Flow {
                    visible:page.configureOpen;Layout.fillWidth:true;spacing:8
                    Choice {
                        id:placeList;width:180;model:page.sources;textRole:"label"
                        Accessible.name:"Observing location"
                        onActivated:page.editing=true
                    }
                    TextField {
                        id:dateField;width:140;implicitHeight:42;maximumLength:10
                        placeholderText:"YYYY-MM-DD";placeholderTextColor:App.Palette.muted;color:App.Palette.ink
                        Accessible.name:"Night date, year month day"
                        selectByMouse:true
                        background:Rectangle {radius:6;color:App.Palette.field;border.color:dateField.activeFocus?App.Palette.accent:App.Palette.border}
                        onTextEdited:page.editing=true
                        onAccepted:if (!page.busy) saveNight.clicked()
                    }
                    App.ActionButton {
                        id:saveNight;text:"Set night";enabled:!page.busy&&dateField.text.length===10
                        onClicked:page.request("configure",{night:dateField.text,source:page.sources[placeList.currentIndex]?.id})
                    }
                    App.ActionButton {text:"Recalculate";enabled:!page.busy&&!page.editing;onClicked:page.request("view")}
                }
                Copy {visible:page.configureOpen&&!!page.result?.period&&!page.editing;text:(page.result?.place||"")+" · "+(page.result?.zone||"")+"\n"+(page.result?.period||"")+" · Checked "+(page.result?.checked||"");color:App.Palette.accent}
                Copy {visible:page.editing;text:"Press Set night to apply these changes.";color:App.Palette.warning}
                Copy {
                    visible:text.length>0
                    text:page.problem||page.result?.error||page.notice||(page.busy?"Calculating locally…":"")
                    color:page.problem||page.result?.error ? App.Palette.warning : App.Palette.accent
                }
            }
            GridLayout {
                id: grid
                Layout.fillWidth:true;Layout.leftMargin:18;Layout.rightMargin:18
                columns:width>=750?2:1;columnSpacing:12;rowSpacing:12
                App.ViewPanel {
                    appearance:"mission";Layout.fillWidth:true;Layout.preferredWidth:285
                    Layout.fillHeight:grid.columns===2;Layout.alignment:Qt.AlignTop;implicitHeight:listBody.implicitHeight+28
                    ColumnLayout {
                        id:listBody;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:14;spacing:9
                        RowLayout {
                            Layout.fillWidth:true
                            Copy {text:"Observing list";font.bold:true;font.pixelSize:21}
                            Copy {Layout.fillWidth:false;text:(page.result?.rows?.length||0)+" picks";color:App.Palette.muted}
                        }
                        Copy {visible:!page.result?.rows?.length;text:"Add a target here or save a pick from the Star Chart.";color:App.Palette.muted}
                        ListView {
                            id:list
                            Layout.fillWidth:true;Layout.preferredHeight:Math.min(contentHeight,grid.columns===1?185:340)
                            clip:true;spacing:5;model:page.result?.rows||[]
                            ScrollBar.vertical:ScrollBar {}
                            delegate:Button {
                                id:pickButton
                                required property var modelData
                                width:list.width;height:65;hoverEnabled:true
                                readonly property bool chosen:modelData.id===page.selected
                                Accessible.name:modelData.name
                                enabled:!page.busy&&!page.editing
                                onClicked:page.showPick(modelData.id)
                                background:Rectangle {
                                    color:pickButton.chosen?App.Palette.hover:pickButton.hovered?App.Palette.field:"transparent"
                                    radius:5;border.color:pickButton.activeFocus||pickButton.chosen?App.Palette.accent:App.Palette.line
                                }
                                contentItem:RowLayout {
                                    spacing:10
                                    Canvas {
                                        Layout.preferredWidth:31;Layout.preferredHeight:31
                                        property color ink:pickButton.chosen?App.Palette.accent:App.Palette.muted
                                        property string kind:pickButton.modelData.category || ""
                                        onInkChanged:requestPaint()
                                        onKindChanged:requestPaint()
                                        onPaint:{
                                            const c=getContext("2d")
                                            c.reset();c.translate(width/2,height/2)
                                            c.fillStyle=ink;c.strokeStyle=ink;c.lineWidth=1.6
                                            if(kind==="planet" || kind==="moon") {
                                                c.beginPath();c.arc(0,0,7,0,2*Math.PI);c.fill()
                                                if(pickButton.modelData.id==="t:Saturn"){c.rotate(-.42);c.beginPath();c.ellipse(-14,-3,28,6);c.stroke()}
                                            } else if(kind==="deep-sky") {
                                                for(const p of [[-9,1],[0,-5],[7,5],[9,-5],[-4,8]]){c.beginPath();c.arc(p[0],p[1],1.7,0,2*Math.PI);c.fill()}
                                            } else {
                                                c.beginPath();c.moveTo(0,-11);c.lineTo(2,-2);c.lineTo(10,0);c.lineTo(2,2);c.lineTo(0,11);c.lineTo(-2,2);c.lineTo(-10,0);c.lineTo(-2,-2);c.closePath();c.fill()
                                            }
                                        }
                                    }
                                    Column {Layout.fillWidth:true;spacing:4
                                    Text {width:parent.width-16;elide:Text.ElideRight;text:pickButton.modelData.name;color:App.Palette.ink;font.bold:true;font.pixelSize:17}
                                    Text {width:parent.width-16;elide:Text.ElideRight;text:pickButton.modelData.best?"Best "+page.timeOf(pickButton.modelData.best)+" · "+page.dayOf(pickButton.modelData.best):pickButton.modelData.kind==="reference"?"Reference pick":"No best time";color:App.Palette.muted;font.pixelSize:13}
                                    }
                                }
                            }
                        }
                        App.ActionButton {text:page.catalogueOpen?"Hide catalogue":"Add target";onClicked:page.catalogueOpen=!page.catalogueOpen}
                Flow {
                    visible:page.catalogueOpen;Layout.fillWidth:true;spacing:8
                    Choice {
                        id:target;width:Math.min(255,parent.width);model:page.result?.catalogue||[];textRole:"name"
                        Accessible.name:"Catalogue target"
                    }
                    App.ActionButton {
                        text:"Add target";enabled:!page.busy&&target.currentIndex>=0
                        onClicked:page.add("target",target.model[target.currentIndex].id)
                    }
                }
                    }
                }
                App.ViewPanel {
                    appearance:"mission";Layout.fillWidth:true;Layout.preferredWidth:670
                    Layout.alignment:Qt.AlignTop;implicitHeight:body.implicitHeight+30
                    ColumnLayout {
                        id:body;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:15;spacing:9
                        RowLayout {
                            Layout.fillWidth:true
                            Copy {text:page.pick?.name || "Timing chart";font.pixelSize:27;font.bold:true}
                            App.ActionButton {
                                visible:!!page.pick?.logPlace;text:"I saw it";enabled:page.ready
                                onClicked:page.recordObservation({name:page.pick.name,place:page.pick.logPlace,assessment:"From My Night"})
                            }
                        }
                        Copy {visible:!page.pick;text:"Select a saved pick to see its timing.";color:App.Palette.muted}
                        RowLayout {
                            visible:!!page.pick?.begin && !page.editing && !page.problem;Layout.fillWidth:true
                            Repeater {
                                model:[["Begin",page.pick?.begin],["Best time",page.pick?.best],["End",page.pick?.end]]
                                ColumnLayout {
                                    required property var modelData;Layout.fillWidth:true;Layout.preferredWidth:1
                                    Copy {text:modelData[0];color:App.Palette.muted}
                                    Copy {text:page.timeOf(modelData[1]);font.pixelSize:25;font.bold:true;color:modelData[0]==="Best time"?App.Palette.accent:App.Palette.ink}
                                    Copy {text:page.dayOf(modelData[1]);font.pixelSize:12;color:App.Palette.muted}
                                }
                            }
                        }
                        Copy {visible:!!page.pick?.direction&&!page.editing&&!page.problem;text:"At best time · "+(page.pick?.direction||"");color:App.Palette.accent}
                        Copy {visible:timing.visible;text:"Altitude through the night";font.bold:true;font.pixelSize:17}
                        NightTimingChart {
                            id:timing;Layout.fillWidth:true;Layout.preferredHeight:165
                            visible:!!page.result?.chart && page.result.chart.id===page.selected&&!page.editing&&!page.problem
                            data:visible?page.result.chart:null
                        }
                        Copy {visible:timing.visible;text:"Solid: altitude   ·   Dashed: saved horizon   ·   Shading: darkness and viewing window";font.pixelSize:12;color:App.Palette.muted}
                        Copy {visible:!!page.pick && !page.editing;text:[page.pick?.weather,page.pick?.note].filter(Boolean).join("  ");font.pixelSize:13;color:App.Palette.muted}
                        Flow {
                            visible:!!page.pick;Layout.fillWidth:true;spacing:6
                            App.ActionButton {visible:!!page.pick?.extent;text:page.framingId===page.selected?"Hide field of view":"Show field of view";onClicked:page.framingId=page.framingId===page.selected?"":page.selected}
                            App.ActionButton {text:"Remove";enabled:!page.busy&&!page.editing;Accessible.name:"Remove "+(page.pick?.name||"");onClicked:page.request("remove",{selected:page.selected})}
                        }
                        Loader {
                            id:framingLoader;Layout.fillWidth:true;visible:!!page.pick?.extent && page.selected===page.framingId;active:visible
                            sourceComponent:Component {App.FieldOfView {skyModel:page.sky;extentDeg:page.pick?.extent || 0;onOpenEquipment:page.openEquipment()}}
                        }
                    }
                }
            }
                Flow {
                    Layout.leftMargin:18;Layout.fillWidth:true;spacing:8
                    App.ActionButton {
                        text:"Save offline guide ("+(page.result?.exportable||0)+")"
                        enabled:page.ready&&(page.result?.exportable||0)>0
                        onClicked:page.request("export",{display:App.Palette.observingMode})
                    }
                    App.ActionButton {
                        text:"Open last saved guide";visible:!!page.guide
                        onClicked:Qt.openUrlExternally("file://"+page.guide.split("/").map(encodeURIComponent).join("/"))
                    }
                }
            Item {Layout.preferredHeight:24}
        }
    }
    IpcHandler {
        target:"omanova-my-night"
        function summary():string {
            return JSON.stringify({busy:page.busy,picks:page.result?.rows?.length??0,
                points:page.result?.chart?.points?.length??0,exportable:page.result?.exportable??0,
                saved:!!page.guide,error:page.problem||page.result?.error||""})
        }
        function fixtureAction(verb:string, key:string):bool {
            if (!page.sky.fixture) return false
            if(verb==="target"||verb==="event")return page.add(verb,key)
            if(verb==="configure")return page.request(verb,{night:key,source:"active"})
            if(verb==="framing"){page.showPick(key);page.framingId=key;return true}
            if(verb==="remove")return page.request(verb,{selected:key})
            if(verb==="export")return page.request(verb)
            return false
        }
        function fixtureFraming(name:string, switchSetup:bool):string {
            if (!page.sky.fixture) return ""
            const panel=framingLoader.item
            if (!panel) return ""
            if (switchSetup) return JSON.stringify(panel.selectSetup(name || null))
            return JSON.stringify({status:panel.comparison.status, field:panel.fieldDeg, setup:panel.activeName,
                                   width:panel.activeSetup?.widthDeg, height:panel.activeSetup?.heightDeg})
        }
        function fixtureCapture():void {
            if(page.sky.fixture)page.grabToImage(r=>r.saveToFile(page.state+"/my-night.png"))
        }
    }
}
