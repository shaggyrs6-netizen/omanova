import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MissionControl 1.0

ApplicationWindow {
 id: win
 property bool wallpaperMode: false
 visible: !wallpaperMode
 width: 1440; height: 940
 minimumWidth: wallpaperMode?0:760; minimumHeight: wallpaperMode?0:740
 title: scene.live?qsTr("OMANOVA · Mission Control — live data preview"):qsTr("OMANOVA · Mission Control — separate sample preview")
 color: "#020811"
 property color ink: "#edf5fa"
 property color muted: "#9cb3c7"
 property color accent: "#5de7ef"
 property bool compact: width<1050
 property bool help: false
 component Copy: Text { color: win.ink; textFormat: Text.PlainText; font.family: "DejaVu Sans"; font.pixelSize: 14 }
 component Action: Button {
  id: control
  property bool active: false
  implicitHeight: 42
  implicitWidth: Math.max(100,contentItem.implicitWidth+28)
  Accessible.name: text
  contentItem: Copy {text: control.text; color: control.active?"#061724":win.ink; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.pixelSize: 14}
  background: InstrumentFrame {topFill:control.active?win.accent:(control.hovered?"#16394a":"#0b1e2e");bottomFill:control.active?"#69cbd3":"#06121f";edge:control.visualFocus?"#ffffff":(control.active?win.accent:"#285267");accent:control.visualFocus?"#ffffff":win.accent;emphasis:control.visualFocus}
 }
 Shortcut { sequence: "Space"; onActivated: scene.paused=!scene.paused }
 Shortcut { sequence: "R"; onActivated: scene.reduced=!scene.reduced }
 Shortcut { sequence: "T"; onActivated: scene.trails=!scene.trails }
 Shortcut { sequence: "1"; onActivated: scene.selection=0 }
 Shortcut { sequence: "2"; onActivated: scene.selection=1 }
 Shortcut { sequence: "F11"; onActivated: win.visibility=win.visibility===Window.FullScreen?Window.Windowed:Window.FullScreen }
 Shortcut { sequence: "Escape"; onActivated: {if(win.visibility===Window.FullScreen)win.showNormal();else win.help=false} }
 Shortcut { sequence: "Q"; onActivated: win.close() }
 Shortcut { sequence: "?"; onActivated: win.help=!win.help }
 ColumnLayout {
  anchors.fill: parent; anchors.margins: win.width<1000?18:24; anchors.topMargin:win.wallpaperMode?48:(win.width<1000?18:24);anchors.bottomMargin:win.wallpaperMode?34:(win.width<1000?18:24); spacing: 12
  RowLayout {
   Layout.fillWidth: true
   ColumnLayout { spacing: 2
    Copy { text: "OMANOVA"; font.pixelSize: win.width<1000?29:40; font.letterSpacing: 3; font.bold: true
     Canvas {anchors.left:parent.right;anchors.leftMargin:12;anchors.verticalCenter:parent.verticalCenter;width:58;height:34;onPaint:{let c=getContext("2d");c.clearRect(0,0,width,height);c.strokeStyle=win.accent;c.lineWidth=1.5;c.beginPath();c.moveTo(2,23);c.bezierCurveTo(45,-2,73,7,37,32);c.stroke();c.fillStyle=win.accent;c.beginPath();c.moveTo(28,1);c.lineTo(32,9);c.lineTo(40,13);c.lineTo(32,17);c.lineTo(28,25);c.lineTo(24,17);c.lineTo(16,13);c.lineTo(24,9);c.closePath();c.fill();}}
    }
    Copy { text: qsTr("M I S S I O N   C O N T R O L"); color: win.accent; font.pixelSize: 12 }
   }
   Item { Layout.fillWidth: true }
   ColumnLayout { spacing: 6
    Copy { Layout.alignment: Qt.AlignRight; text: scene.live?(scene.liveData.testFixture?qsTr("LIVE-PATH TEST / PUBLIC FIXTURE"):qsTr("LIVE OMANOVA / READ-ONLY PREVIEW")):qsTr("ANIMATED PREVIEW / SAMPLE DATA"); color: win.accent; font.pixelSize: 12; font.letterSpacing: 1 }
    Copy { Layout.alignment: Qt.AlignRight; text: scene.live?qsTr("Local calculations · no new downloads"):qsTr("Offline · no live desktop changes"); color: win.muted; font.pixelSize: 12 }
   }
  }
  Item {Layout.fillWidth:true;implicitHeight:5
   Rectangle {anchors.left:parent.left;anchors.right:parent.right;height:1;color:"#21495c"}
   Rectangle {width:parent.width*.18;height:2;color:win.accent}
   Row {anchors.right:parent.right;spacing:5;Repeater {model:9;Rectangle {width:10;height:2;color:index<3?win.accent:"#21495c"}}}
  }
  RowLayout {
   visible:!win.wallpaperMode
   Layout.fillWidth: true; spacing: 8
   Action { objectName:"selectISS"; text: "ISS"; active: scene.selection===0; onClicked: scene.selection=0 }
   Action { objectName:"selectTiangong"; text: "Tiangong"; active: scene.selection===1; onClicked: scene.selection=1 }
   Item {Layout.fillWidth:true}
   Action {text: qsTr("Sky + Orbit"); active:scene.view===0; onClicked:scene.view=0}
   Action {text:qsTr("Sky"); active:scene.view===1; onClicked:scene.view=1; implicitWidth:65}
   Action {objectName:"orbitView";text:qsTr("Orbit"); active:scene.view===2; onClicked:scene.view=2; implicitWidth:65}
  }
  InstrumentFrame {
   Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: win.width<1050?200:290
   edge:"#2e6073";topFill:"#04101e";bottomFill:"#020710";clip: true;emphasis:true
   MissionScene { id: scene; objectName: "missionScene"; anchors.fill:parent; anchors.topMargin:42; anchors.bottomMargin:52 }
   InstrumentFrame {anchors.top:parent.top;anchors.horizontalCenter:parent.horizontalCenter;anchors.topMargin:10;width:172;height:30;visible:win.width>1050;topFill:"#092534";edge:win.accent
    Copy {anchors.centerIn:parent;text:(scene.selection===0?"ISS":"TIANGONG")+qsTr(" SELECTED");font.pixelSize:12;font.letterSpacing:1;color:win.accent}
   }
   Row { anchors.top: parent.top; anchors.left: parent.left; anchors.margins:16; spacing:10
    Rectangle {width:5;height:12;color:win.accent; anchors.verticalCenter:parent.verticalCenter}
    Copy {text:scene.view===2?qsTr("ORBITAL VIEW"):qsTr("LOCAL SKY"); font.pixelSize:14; font.letterSpacing:2}
   }
   Copy { anchors.top:parent.top; anchors.right:parent.right; anchors.margins:16; text:scene.view===0?qsTr("ORBITAL VIEW"):(scene.live?qsTr("CALCULATED POSITIONS"):qsTr("ILLUSTRATIVE GEOMETRY")); font.pixelSize:13; color:win.ink; font.letterSpacing:1 }
   Rectangle {anchors.bottom:parent.bottom;anchors.left:parent.left;anchors.right:parent.right;anchors.margins:1;height:46;color:"#071928";opacity:.95
    Rectangle {anchors.top:parent.top;width:parent.width;height:1;color:"#254b5e"}
   }
   Copy { anchors.bottom:parent.bottom; anchors.left:parent.left;anchors.right:parent.right;anchors.leftMargin:12;anchors.rightMargin:12;anchors.bottomMargin:8;horizontalAlignment:Text.AlignHCenter;wrapMode:Text.WordWrap;text:scene.detail; font.pixelSize:12; color:win.accent }
  }
  GridLayout {
   Layout.fillWidth:true; columns:win.width<1050?2:4; columnSpacing:12; rowSpacing:12
   Repeater {
    model: scene.live ? [
     {heading:qsTr("GEOMETRIC PASS"),value:scene.feedFresh?(scene.liveData.cards?.passes?.[scene.selection===0?"25544":"48274"]?.value||"Unavailable"):"Unavailable",detail:scene.feedFresh?(scene.liveData.cards?.passes?.[scene.selection===0?"25544":"48274"]?.detail||"Predictions unavailable"):qsTr("Live data unavailable · see status below")},
     {heading:qsTr("MOON"),value:scene.feedFresh?Math.round((scene.liveData.moon?.fraction||0)*100)+"% illuminated":"Unavailable",detail:scene.feedFresh?"Calculated now · not a visibility forecast":qsTr("Live data unavailable · see status below")},
     {heading:qsTr("LAUNCH WATCH"),value:scene.feedFresh?(scene.liveData.cards?.launch?.value||"Unavailable"):"Unavailable",detail:scene.feedFresh?(scene.liveData.cards?.launch?.detail||"No cached launch data"):qsTr("Live data unavailable · see status below")},
     {heading:qsTr("OBSERVING"),value:scene.feedFresh?(scene.liveData.cards?.weather?.value||"Unavailable"):"Unavailable",detail:scene.feedFresh?(scene.liveData.cards?.weather?.detail||"Forecast unavailable"):qsTr("Live data unavailable · see status below")}
    ] : [{heading:qsTr("NEXT PASS"),value:scene.selection===0?"ISS · 18:42":"Tiangong · 19:16",detail:qsTr("Sample local time · look NW")},
     {heading:qsTr("MOON"),value:qsTr("68% illuminated"),detail:qsTr("Illustrative phase and conditions")},
     {heading:qsTr("LAUNCH WATCH"),value:qsTr("Schedule unconfirmed"),detail:qsTr("Demonstration · no feed connected")},
     {heading:qsTr("OBSERVING"),value:qsTr("Cloud 24%"),detail:qsTr("Sample only · visibility uncertain")}]

    InstrumentFrame {
     required property var modelData
     required property int index
     Layout.fillWidth:true; implicitHeight:scene.live?138:116
     edge:"#2a6071";topFill:"#0b2231";bottomFill:"#030c17"
     InstrumentIcon {visible:index!==1;width:win.compact?36:44;height:width;anchors.left:parent.left;anchors.leftMargin:14;anchors.verticalCenter:parent.verticalCenter;kind:index;ink:index===2?"#edbc75":win.accent}
     HoverHandler {id:cardHover}
     ToolTip {id:cardTip;visible:!win.wallpaperMode && cardHover.hovered;delay:700;text:modelData.value+"\n"+modelData.detail;contentItem:Copy{text:cardTip.text;wrapMode:Text.WordWrap;font.pixelSize:14} background:Rectangle{color:"#0a2130";border.color:win.accent} width:Math.min(380,win.width-48)}
     Rectangle {visible:!win.compact && index!==1;anchors.left:parent.left;anchors.leftMargin:68;anchors.top:parent.top;anchors.bottom:parent.bottom;anchors.topMargin:18;anchors.bottomMargin:18;width:1;color:"#25576a"}
     ColumnLayout {anchors.fill:parent;anchors.margins:16;anchors.leftMargin:index===1?16:(win.compact?60:80);spacing:5
      Copy {text:modelData.heading; Layout.fillWidth:true;wrapMode:Text.WordWrap;font.pixelSize:11;color:win.accent;font.letterSpacing:1}
      Copy {text:modelData.value; Layout.rightMargin:index===1?50:0; font.pixelSize:win.width<1200?16:19;font.bold:true;Layout.fillWidth:true;wrapMode:Text.WordWrap;maximumLineCount:2;elide:Text.ElideRight}
      Copy {text:modelData.detail;font.pixelSize:12;color:win.muted;Layout.fillWidth:true;wrapMode:Text.WordWrap;maximumLineCount:3;elide:Text.ElideRight}
     }
     Canvas {
      antialiasing:false;visible:index===1 && (!scene.live || scene.feedFresh); width:42;height:42;anchors.right:parent.right;anchors.rightMargin:16;anchors.verticalCenter:parent.verticalCenter
      property real lit:scene.live?(scene.liveData.moon?.fraction||0):0.68
      property bool waxing:!scene.live || (scene.liveData.moon?.angle||0)<180
      onLitChanged:requestPaint();onWaxingChanged:requestPaint()
      onPaint:{let c=getContext("2d");c.clearRect(0,0,width,height);let sz=2*lit-1;let sx=Math.sqrt(Math.max(0,1-sz*sz))*(waxing?1:-1);for(let y=0;y<42;y++)for(let x=0;x<42;x++){let a=(x-20.5)/19,b=(y-20.5)/19,q=a*a+b*b;if(q>1)continue;let z=Math.sqrt(1-q);c.fillStyle=(a*sx+z*sz>0)?"#d1e0e9":"#1e3448";c.fillRect(x,y,1,1);}}
     }
    }
   }
  }
  Flow {
   visible:!win.wallpaperMode
   Layout.fillWidth: true; spacing:8; Layout.preferredHeight:childrenRect.height
   Action {objectName:"pauseButton";text:scene.paused?qsTr("Resume motion"):qsTr("Pause motion");active:scene.paused;onClicked:scene.paused=!scene.paused}
   Action {objectName:"reducedButton";text:scene.reduced?qsTr("Motion: reduced"):qsTr("Motion: subtle");active:scene.reduced;onClicked:scene.reduced=!scene.reduced}
   Action {objectName:"trailsButton";text:scene.trails?qsTr("Trails: on"):qsTr("Trails: off");active:scene.trails;onClicked:scene.trails=!scene.trails}
   Action {text:scene.live?qsTr("Reset view"):qsTr("Reset demo");onClicked:scene.reset()}
   Action {text:qsTr("Full screen");onClicked:win.visibility=win.visibility===Window.FullScreen?Window.Windowed:Window.FullScreen}
   Action {text:qsTr("Keys / help");onClicked:win.help=!win.help}
  }
  Copy {Layout.fillWidth:true;text:win.help?qsTr("Space: pause · R: reduced motion · T: trails · 1/2: satellite · F11: full screen · Esc: leave full screen · Q: close. Select satellite diamonds in either view."):(scene.live?scene.feedStatus+" · "+(scene.liveData.localClock||"—")+" "+(scene.liveData.zone||"local")+" / "+(scene.liveData.utcClock||"—")+" UTC · Calculated, not telemetry. Visibility uncertain.":qsTr("ILLUSTRATIVE DATA — NOT OBSERVING ADVICE. Accelerated demo paths; not current satellite predictions."));font.pixelSize:12;color:win.muted;wrapMode:Text.WordWrap}
 }
}
