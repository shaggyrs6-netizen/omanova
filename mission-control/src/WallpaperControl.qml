import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
 id:control
 visible:true;width:470;height:580;minimumWidth:400;minimumHeight:560
 title:qsTr("Mission Control trial — Restore desktop")
 color:"#06111f"
 onClosing:Qt.quit()
 component Copy:Text {textFormat:Text.PlainText;color:"#eef7fc";font.family:"DejaVu Sans";font.pixelSize:14;wrapMode:Text.WordWrap}
 component Action:Button {
  id:button;property bool primary:false;implicitHeight:46;Layout.fillWidth:true
  contentItem:Copy {text:button.text;horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter;color:button.primary?"#04101b":"#eef7fc"}
  background:InstrumentFrame {topFill:button.primary?"#69e2eb":(button.hovered?"#18394b":"#0b2233");bottomFill:button.primary?"#52bbc6":"#081726";edge:button.visualFocus?"white":"#4d9dad";emphasis:button.visualFocus}
 }
 Shortcut {sequence:"Escape";onActivated:Qt.quit()}
 ColumnLayout {
  anchors.fill:parent;anchors.margins:22;spacing:12
  Copy {text:qsTr("MISSION CONTROL / WALLPAPER TRIAL");font.pixelSize:13;color:"#6ce2eb";font.letterSpacing:1;Layout.fillWidth:true}
  Copy {text:qsTr("Your original desktop is underneath.");font.pixelSize:21;font.bold:true;Layout.fillWidth:true}
  Copy {text:qsTr("Temporary, click-through background. No keyboard focus, theme changes or login startup. Closing this control window also restores your desktop.");color:"#a9c0d0";Layout.fillWidth:true}
  RowLayout {Layout.fillWidth:true;spacing:10
   Action {text:"ISS";onClicked:wallpaperScene.selection=0}
   Action {text:"Tiangong";onClicked:wallpaperScene.selection=1}
  }
  RowLayout {Layout.fillWidth:true;spacing:10
   Action {text:wallpaperScene.paused?qsTr("Resume"):qsTr("Pause");onClicked:wallpaperScene.paused=!wallpaperScene.paused}
   Action {text:wallpaperScene.reduced?qsTr("Reduced motion"):qsTr("Subtle motion");onClicked:wallpaperScene.reduced=!wallpaperScene.reduced}
  }
  Item {Layout.fillHeight:true}
  Action {objectName:"restoreDesktopButton";primary:true;text:qsTr("Restore desktop — stop trial");onClicked:Qt.quit()}
  Copy {text:qsTr("Autostart OFF for this trial. Your OMANOVA worker and its existing settings stay unchanged.");font.pixelSize:12;color:"#a9c0d0";Layout.fillWidth:true}
 }
}
