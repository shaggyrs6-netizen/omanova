import "./qml/Omanova" as App
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: page
    required property var sky
    signal recordObservation(var selected)
    property var result: null
    property string problem: ""
    property string notice: ""
    property string guide: ""
    property string selected: ""
    property string pending: ""
    property string action: ""
    property bool editing: false
    readonly property bool busy: helper.running
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
            try {
                const data=JSON.parse(response.text)
                if (code!==0 || data.failure) {
                    page.problem=data.failure || "Could not update My Night."
                    return
                }
                page.result=data
                page.selected=data.chart?.id || ""
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
                App.PageHeader {eyebrow:"PLAN";title:"My Night"}
                Copy {text:"Pick targets for a night at home or away. Saved events keep their original place and time.";color:App.Palette.muted}
                Flow {
                    Layout.fillWidth:true;spacing:8
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
                Copy {visible:!!page.result?.period&&!page.editing;text:(page.result?.place||"")+" · "+(page.result?.zone||"")+"\n"+(page.result?.period||"")+" · Checked "+(page.result?.checked||"");color:App.Palette.accent}
                Copy {visible:page.editing;text:"Press Set night to apply these changes.";color:App.Palette.warning}
                Copy {
                    visible:text.length>0
                    text:page.problem||page.result?.error||page.notice||(page.busy?"Calculating locally…":"")
                    color:page.problem||page.result?.error ? App.Palette.warning : App.Palette.accent
                }
                Flow {
                    Layout.fillWidth:true;spacing:8
                    Choice {
                        id:target;width:Math.min(310,scroll.availableWidth-45);model:page.result?.catalogue||[];textRole:"name"
                        Accessible.name:"Catalogue target"
                    }
                    App.ActionButton {
                        text:"Add target";enabled:!page.busy&&target.currentIndex>=0
                        onClicked:page.add("target",target.model[target.currentIndex].id)
                    }
                }
                Flow {
                    Layout.fillWidth:true;spacing:8
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
                Copy {visible:!page.result?.rows?.length;text:"Nothing saved yet. Add a target above or use Add to My Night on Tonight, Events or Sky Finder.";color:App.Palette.muted}
            }
            Repeater {
                model:page.result?.rows||[]
                delegate:Rectangle {
                    id:card
                    required property var modelData
                    readonly property bool expanded:page.result?.chart?.id===modelData.id && !page.editing
                    Layout.fillWidth:true;Layout.leftMargin:22;Layout.rightMargin:22
                    implicitHeight:body.implicitHeight+28
                    radius:10;color:App.Palette.surface;border.color:expanded?App.Palette.accent:App.Palette.line
                    ColumnLayout {
                        id:body;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:14;spacing:8
                        Copy {text:card.modelData.name;font.pixelSize:21;font.bold:true}
                        Copy {text:card.modelData.note||"Timing unavailable.";color:App.Palette.muted}
                        Copy {
                            visible:!!card.modelData.begin&&!page.editing&&!page.problem
                            text:"Begin  "+card.modelData.begin+"\nBest  "+(card.modelData.best||"Not established")+
                                 (card.modelData.direction?" · "+card.modelData.direction:"")+"\nEnd  "+card.modelData.end
                        }
                        Copy {visible:!!card.modelData.best&&!page.editing&&!page.problem;text:card.modelData.weather||"";color:App.Palette.muted}
                        Flow {
                            Layout.fillWidth:true;spacing:8
                            App.ActionButton {text:card.expanded?"Refresh timing chart":"Show timing chart";enabled:!page.busy&&!page.editing;onClicked:page.showPick(card.modelData.id)}
                            App.ActionButton {
                                text:"I saw it";enabled:!page.busy&&!page.editing&&!!card.modelData.logPlace
                                onClicked:page.recordObservation({name:card.modelData.name,place:card.modelData.logPlace,assessment:"From My Night"})
                            }
                            App.ActionButton {text:"Remove";enabled:!page.busy;Accessible.name:"Remove "+card.modelData.name;onClicked:page.request("remove",{selected:card.modelData.id})}
                        }
                        NightTimingChart {
                            Layout.fillWidth:true;Layout.preferredHeight:185
                            visible:card.expanded&&!page.problem
                            data:visible?page.result.chart:null
                        }
                        Copy {
                            visible:card.expanded&&!page.problem
                            text:page.result.chart.from+" to "+page.result.chart.to
                            color:App.Palette.muted
                        }
                        Copy {
                            visible:card.expanded&&!page.problem
                            text:(page.result.chart.points.length?"Solid: altitude. Dashed: saved horizon. ":"")
                                +"Faint shading: astronomical darkness. Bright shading: selected window. Dotted marker: best time. Cloud bars show cached hourly cover where available. "
                                +page.result.chart.note
                            color:App.Palette.muted
                        }
                    }
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
            if(verb==="remove")return page.request(verb,{selected:key})
            if(verb==="export")return page.request(verb)
            return false
        }
        function fixtureCapture():void {
            if(page.sky.fixture)page.grabToImage(r=>r.saveToFile(page.state+"/my-night.png"))
        }
    }
}
