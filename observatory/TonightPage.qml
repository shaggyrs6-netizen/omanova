import "../qml/Omanova" as App
import "../qml/Omanova/Tonight.js" as Tonight
import ".." as Core
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
ColumnLayout {
    id: page
    required property var sky
    required property var night
    property bool canAddToNight: false
    signal addToNight(string key)
    signal inspect(var selected)
    signal recordObservation(var selected)
    signal openEvents()
    signal openSettings()
    signal openOrbit(string station, string rise, string time)
    readonly property bool weatherCurrent: sky.data?.settings?.weather === true && !!strip?.weatherFetched &&
        sky.now >= Date.parse(strip.weatherFetched) && sky.now - Date.parse(strip.weatherFetched) < 21600000
    spacing: 14
    readonly property bool nightCurrent: night.current
    readonly property var strip: nightCurrent ? night.dataSet : null
    readonly property double end: strip ? Date.parse(strip.end) : sky.now+86400000
    readonly property var picks: Tonight.select(sky.plannedEvents, sky.now, sky.plannerStale,
        sky.data?.settings?.observing?.interests || [],
        row => !sky.applyEquipmentProfile || sky.equipmentMatches(row), end)
    function clock(t) {return t ? Qt.formatDateTime(new Date(t),"HH:mm") : "Unavailable"}
    component Copy: Text {
        Layout.fillWidth:true;wrapMode:Text.Wrap;textFormat:Text.PlainText
        color:App.Palette.ink;font.pixelSize:14
    }
    TonightInstruments {
        Layout.fillWidth: true
        Layout.leftMargin: 16; Layout.rightMargin: 16; Layout.topMargin: 8
        sky: page.sky; strip: page.strip; weatherCurrent: page.weatherCurrent
        onOpenOrbit: (station,rise,time) => page.openOrbit(station,rise,time)
    }
    App.PageHeader {
        Layout.margins:24;Layout.bottomMargin:0
        eyebrow:"TONIGHT"
        title:"Your night at a glance"
        description: "What is coming up, where to look and what the current data can support."
    }
    Rectangle {
        Layout.fillWidth:true;Layout.leftMargin:24;Layout.rightMargin:24
        implicitHeight:nightBody.implicitHeight+32
        color:App.Palette.surface;border.color:App.Palette.line;radius:10
        ColumnLayout {
            id:nightBody;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:16;spacing:10
            Copy {text:page.strip ? "Night of "+page.strip.night+" · "+page.strip.zone : "Night strip";font.weight:Font.DemiBold;font.pixelSize:18}
            Copy {text:page.strip ? "Sunset "+page.clock(page.strip.sunset)+" · Sunrise "+page.clock(page.strip.sunrise) : page.night.error || (!page.sky.data?.place ? "Set your location in Settings to see the night strip." : "Calculating from cached astronomy and weather…");color:App.Palette.muted}
            Copy {visible:page.sky.snapshotStale;text:"Snapshot stale · this strip is context only. Refresh or check the worker before observing.";color:App.Palette.warning}
            // The strip scrolls at small widths rather than shrinking labels beyond readability.
            Flickable {
                id:stripView;visible:!!page.strip;Layout.fillWidth:true;implicitHeight:120
                contentWidth:Math.max(width,960);contentHeight:height;clip:true
                ScrollBar.horizontal:ScrollBar {policy:stripView.contentWidth>stripView.width?ScrollBar.AlwaysOn:ScrollBar.AlwaysOff}
                Row {
                    width:stripView.contentWidth;spacing:2
                    Repeater {
                        model:page.strip?.hours || []
                        Column {
                            id: hourCell
                            required property var modelData
                            required property int index
                            width:(stripView.contentWidth-2*((page.strip?.hours.length || 24)-1))/(page.strip?.hours.length || 24)
                            spacing:5
                            Rectangle {
                                width:parent.width;height:28;radius:3
                                color:hourCell.modelData.light==="dark"?App.Palette.field:hourCell.modelData.light==="twilight"?App.Palette.button:App.Palette.hover
                                border.color:App.Palette.border
                                Text {anchors.centerIn:parent;text:hourCell.modelData.light==="dark"?"D":hourCell.modelData.light==="twilight"?"T":"☀";color:App.Palette.ink;font.pixelSize:12;textFormat:Text.PlainText}
                            }
                            Text {text:hourCell.modelData.moonUp?"Moon":"—";color:App.Palette.muted;font.pixelSize:11;textFormat:Text.PlainText}
                            Text {text:page.sky.data?.settings?.weather === true && page.strip.weatherFetched && page.sky.now-Date.parse(page.strip.weatherFetched)<21600000 && page.sky.now>=Date.parse(page.strip.weatherFetched) && hourCell.modelData.cloud!==null ? hourCell.modelData.cloud+"%":"?";color:App.Palette.ink;font.pixelSize:11;textFormat:Text.PlainText}
                            Text {
                                readonly property int count:page.picks.filter(p => Date.parse(p.start)>=Date.parse(hourCell.modelData.time) && Date.parse(p.start)<Date.parse(hourCell.modelData.time)+3600000).length
                                text:count?"• "+count:"";color:App.Palette.accent;font.pixelSize:11;textFormat:Text.PlainText
                            }
                            Text {text:hourCell.modelData.label;color:App.Palette.muted;font.pixelSize:11;textFormat:Text.PlainText}
                        }
                    }
                }
            }
            Copy {visible:!!page.strip;text:"D = astronomical dark · T = twilight · ☀ = daylight · Moon = above horizon · % = cloud cover · ? = unknown · • = suggested event starts";color:App.Palette.muted;font.pixelSize:12}
            Copy {visible:!!page.strip;text:page.sky.data?.settings?.weather !== true ? "Weather downloads are off; cloud cover unknown." : page.strip?.weatherFetched && page.sky.now-Date.parse(page.strip.weatherFetched)>=21600000 ? "Cached forecast expired; cloud cover unknown. Recheck Conditions." : page.strip?.weatherNote || "";color:App.Palette.muted;font.pixelSize:12}
            Copy {visible:!!page.strip;text:page.strip?.basis || "";color:App.Palette.muted;font.pixelSize:12}
        }
    }
    RowLayout {
        Layout.fillWidth:true;Layout.leftMargin:24;Layout.rightMargin:24
        Copy {text:page.strip?"Opportunities for this night":"Opportunities in the next 24 hours";font.pixelSize:22;font.weight:Font.DemiBold}
        App.ActionButton {text:"All events";onClicked:page.openEvents()}
    }
    Copy {
        Layout.leftMargin:24;Layout.rightMargin:24
        text: page.sky.plannerStale ? "Planning data is missing or stale. No current recommendations; all cached events remain available to inspect." :
            !page.picks.length ? "No current suggestion matches this night, your interests and equipment. You can still inspect all events and their limitations." :
            "Best-ranked pick first, then upcoming opportunities in time order. Potential viewing is not a confirmed sighting."
        color:page.sky.plannerStale?App.Palette.warning:App.Palette.muted
    }
    Repeater {
        model:page.picks
        Core.OpportunityCard {
            required property var modelData
            required property int index
            Layout.leftMargin:24;Layout.rightMargin:24
            event:modelData;sky:page.sky;hero:index===0
            onInspect:function(selected){page.inspect(selected)}
            canAddToNight:page.canAddToNight
            onAddToNight:key=>page.addToNight(key)
            onRecordObservation:function(selected){page.recordObservation(selected)}
        }
    }
    RowLayout {
        Layout.leftMargin:24;Layout.rightMargin:24;Layout.bottomMargin:24
        App.ActionButton {text:"Inspect all events";visible:!page.picks.length;onClicked:page.openEvents()}
        App.ActionButton {text:"Location, downloads & status";onClicked:page.openSettings()}
    }
}
