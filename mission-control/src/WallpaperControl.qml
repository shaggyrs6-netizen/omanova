import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
 id:control
 visible:true;width:470;height:740;minimumWidth:400;minimumHeight:700
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
 ScrollView {
  id:scroll;anchors.fill:parent;anchors.margins:22;contentWidth:availableWidth;contentHeight:settingsColumn.implicitHeight
 ColumnLayout {
  id:settingsColumn;width:scroll.availableWidth;spacing:12
  Copy {text:qsTr("MISSION CONTROL / WALLPAPER TRIAL");font.pixelSize:13;color:"#6ce2eb";font.letterSpacing:1;Layout.fillWidth:true}
  Copy {text:qsTr("Your original desktop is underneath.");font.pixelSize:21;font.bold:true;Layout.fillWidth:true}
  Action {objectName:"restoreDesktopButton";primary:true;text:qsTr("Restore desktop — this session");onClicked:Qt.quit()}
  Action {objectName:"normalDesktopButton";text:qsTr("Use normal desktop from now on");enabled:!startupOptions.busy;onClicked:startupOptions.disableAndRestore()}
  Copy {text:qsTr("Click-through wallpaper, with your normal desktop underneath. Restore desktop ends this session; Use normal desktop also disables login startup.");color:"#a9c0d0";Layout.fillWidth:true}
  RowLayout {Layout.fillWidth:true;spacing:10
   Action {text:"ISS";onClicked:wallpaperScene.selection=0}
   Action {text:"Tiangong";onClicked:wallpaperScene.selection=1}
  }
  RowLayout {Layout.fillWidth:true;spacing:10
   Action {text:wallpaperScene.paused?qsTr("Resume"):qsTr("Pause");onClicked:wallpaperScene.paused=!wallpaperScene.paused}
   Action {text:wallpaperScene.reduced?qsTr("Reduced motion"):qsTr("Subtle motion");onClicked:wallpaperScene.reduced=!wallpaperScene.reduced}
  }
  Action {objectName:"loginStartupButton";enabled:!startupOptions.busy && startupOptions.available;text:startupOptions.busy?qsTr("Checking startup…"):(!startupOptions.available?qsTr("Login startup unavailable"):(startupOptions.enabled?qsTr("Start at login: On — turn off"):qsTr("Start at login: Off — turn on")));onClicked:startupOptions.setEnabled(!startupOptions.enabled)}
  Copy {text:startupOptions.message;Layout.fillWidth:true;color:"#a9c0d0";font.pixelSize:13}
  Action {text:qsTr("Refresh startup setting");enabled:!startupOptions.busy;onClicked:startupOptions.refresh()}
  Item {Layout.fillHeight:true}
  Connections {target:startupOptions;function onDisabledForRestore(){Qt.quit()}}
  Copy {text:qsTr("Login startup is optional. Your OMANOVA worker and its existing settings stay unchanged.");font.pixelSize:12;color:"#a9c0d0";Layout.fillWidth:true}
 }
 }
}
