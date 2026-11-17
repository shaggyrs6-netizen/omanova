import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MissionControl 1.0

ApplicationWindow {
 id: win
 visible: true
 width: 1440; height: 940
 minimumWidth: 760; minimumHeight: 740
 title: qsTr("OMANOVA · Mission Control — separate sample preview")
 color: "#040b16"
 property color ink: "#edf5fa"
 property color muted: "#9cb3c7"
 property color accent: "#5de7ef"
 property bool help: false
 component Copy: Text { color: win.ink; textFormat: Text.PlainText; font.family: "DejaVu Sans"; font.pixelSize: 14 }
 component Action: Button {
  id: control
  property bool active: false
  implicitHeight: 42
  implicitWidth: Math.max(100,contentItem.implicitWidth+28)
  Accessible.name: text
  contentItem: Copy {text: control.text; color: control.active?"#061724":win.ink; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.pixelSize: 14}
  background: Rectangle { radius: 3; color: control.active?win.accent:(control.hovered?"#143045":"#0a1929"); border.color: control.visualFocus?"#ffffff":(control.active?win.accent:"#285267"); border.width: control.visualFocus?2:1 }
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
  anchors.fill: parent; anchors.margins: win.width<1000?18:28; spacing: 16
  RowLayout {
   Layout.fillWidth: true
   ColumnLayout { spacing: 4
    Copy { text: "OMANOVA"; font.pixelSize: win.width<1000?29:38; font.letterSpacing: 4; font.bold: true }
    Copy { text: qsTr("M I S S I O N   C O N T R O L"); color: win.accent; font.pixelSize: 12 }
   }
   Item { Layout.fillWidth: true }
   ColumnLayout { spacing: 6
    Copy { Layout.alignment: Qt.AlignRight; text: qsTr("ANIMATED PREVIEW / SAMPLE DATA"); color: win.accent; font.pixelSize: 12; font.letterSpacing: 1 }
    Copy { Layout.alignment: Qt.AlignRight; text: qsTr("Offline · no live desktop changes"); color: win.muted; font.pixelSize: 12 }
   }
  }
  Rectangle { Layout.fillWidth: true; height: 1; color: "#27505e" }
  RowLayout {
   Layout.fillWidth: true; spacing: 8
   Action { objectName:"selectISS"; text: "ISS"; active: scene.selection===0; onClicked: scene.selection=0 }
   Action { objectName:"selectTiangong"; text: "Tiangong"; active: scene.selection===1; onClicked: scene.selection=1 }
   Item {Layout.fillWidth:true}
   Action {text: qsTr("Sky + Orbit"); active:scene.view===0; onClicked:scene.view=0}
   Action {text:qsTr("Sky"); active:scene.view===1; onClicked:scene.view=1; implicitWidth:65}
   Action {objectName:"orbitView";text:qsTr("Orbit"); active:scene.view===2; onClicked:scene.view=2; implicitWidth:65}
  }
  Rectangle {
   Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: win.width<1050?200:290
   color: "#061323"; border.color: "#203f52"; radius: 4; clip: true
   MissionScene { id: scene; objectName: "missionScene"; anchors.fill:parent; anchors.topMargin:32; anchors.bottomMargin:34 }
   Row { anchors.top: parent.top; anchors.left: parent.left; anchors.margins:16; spacing:10
    Rectangle {width:5;height:12;color:win.accent; anchors.verticalCenter:parent.verticalCenter}
    Copy {text:scene.view===2?qsTr("ORBITAL VIEW"):qsTr("LOCAL SKY"); font.pixelSize:12; font.letterSpacing:2}
   }
   Copy { anchors.top:parent.top; anchors.right:parent.right; anchors.margins:16; text:scene.view===0?qsTr("ORBITAL VIEW"):qsTr("ILLUSTRATIVE GEOMETRY"); font.pixelSize:12; color:win.muted; font.letterSpacing:1 }
   Copy { anchors.bottom:parent.bottom; anchors.horizontalCenter:parent.horizontalCenter; anchors.bottomMargin:13; text:scene.detail; font.pixelSize:12; color:win.accent }
  }
  GridLayout {
   Layout.fillWidth:true; columns:win.width<1050?2:4; columnSpacing:12; rowSpacing:12
   Repeater {
    model:[{heading:qsTr("NEXT PASS"),value:scene.selection===0?"ISS · 18:42":"Tiangong · 19:16",detail:qsTr("Sample local time · look NW"),mark:"↗"},
     {heading:qsTr("MOON"),value:qsTr("68% illuminated"),detail:qsTr("Illustrative phase and conditions"),mark:"◕"},
     {heading:qsTr("LAUNCH WATCH"),value:qsTr("Schedule unconfirmed"),detail:qsTr("Demonstration · no feed connected"),mark:"↑"},
     {heading:qsTr("OBSERVING"),value:qsTr("Cloud 24%"),detail:qsTr("Sample only · visibility uncertain"),mark:"≋"}]
    Rectangle {
     required property var modelData
     required property int index
     Layout.fillWidth:true; implicitHeight:110
     color:"#0a192a";border.color:"#244c5c";radius:3
     Rectangle {width:36;height:2;color:win.accent;anchors.top:parent.top;anchors.left:parent.left;anchors.leftMargin:16}
     ColumnLayout {anchors.fill:parent;anchors.margins:16;spacing:5
      Copy {text:modelData.heading; font.pixelSize:12;color:win.accent;font.letterSpacing:1.5}
      Copy {text:modelData.value; Layout.rightMargin:index===1?46:0; font.pixelSize:win.width<1200?17:21;font.bold:true;Layout.fillWidth:true;elide:Text.ElideRight}
      Copy {text:modelData.detail;font.pixelSize:12;color:win.muted;Layout.fillWidth:true;wrapMode:Text.WordWrap}
     }
     Canvas { visible:index===1; width:42;height:42;anchors.right:parent.right;anchors.rightMargin:16;anchors.verticalCenter:parent.verticalCenter; onPaint:{let c=getContext("2d");c.clearRect(0,0,width,height);c.fillStyle="#1e3448";c.beginPath();c.arc(21,21,19,0,Math.PI*2);c.fill();c.save();c.beginPath();c.arc(21,21,19,0,Math.PI*2);c.clip();c.fillStyle="#d1e0e9";c.beginPath();c.ellipse(11,2,29,38);c.fill();c.fillStyle="#9bafbd";c.beginPath();c.arc(26,14,4,0,Math.PI*2);c.arc(29,29,3,0,Math.PI*2);c.fill();c.restore();} }
    }
   }
  }
  Flow {
   Layout.fillWidth: true; spacing:8; Layout.preferredHeight:childrenRect.height
   Action {objectName:"pauseButton";text:scene.paused?qsTr("Resume motion"):qsTr("Pause motion");active:scene.paused;onClicked:scene.paused=!scene.paused}
   Action {objectName:"reducedButton";text:scene.reduced?qsTr("Motion: reduced"):qsTr("Motion: subtle");active:scene.reduced;onClicked:scene.reduced=!scene.reduced}
   Action {objectName:"trailsButton";text:scene.trails?qsTr("Trails: on"):qsTr("Trails: off");active:scene.trails;onClicked:scene.trails=!scene.trails}
   Action {text:qsTr("Reset demo");onClicked:scene.reset()}
   Action {text:qsTr("Full screen");onClicked:win.visibility=win.visibility===Window.FullScreen?Window.Windowed:Window.FullScreen}
   Action {text:qsTr("Keys / help");onClicked:win.help=!win.help}
  }
  Copy {Layout.fillWidth:true;text:win.help?qsTr("Space: pause · R: reduced motion · T: trails · 1/2: satellite · F11: full screen · Esc: leave full screen · Q: close. Select satellite diamonds in either view."):qsTr("ILLUSTRATIVE DATA — NOT OBSERVING ADVICE. Accelerated demo paths; not current satellite predictions.");font.pixelSize:12;color:win.muted;wrapMode:Text.WordWrap}
 }
}
