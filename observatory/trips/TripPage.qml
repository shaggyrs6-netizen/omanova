import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id:root
    property var draft:null
    property var result:null
    property int tab:0
    property string editing:"destination"
    property var searchRows:[]
    property string searchTarget:"destination"
    property string message:""
    property string pending:""
    property string pendingSearch:""
    property int revision:0
    property int requestedRevision:-1
    property int resultRevision:-1
    property int editingSector:-1
    property bool cooling:false
    readonly property bool terrainPreview:Quickshell.env("OMANOVA_TERRAIN_PREVIEW")==="1"
    property var terrainProfile:null
    property string terrainPending:""
    property string terrainRequestKey:""
    property string terrainAction:"terrain-status"
    function terrainKey() {return root.editing+":"+key(root.current)+":"+Number(root.current.observingHeight??1.7)}
    function readTerrain(action) {
        if(terrainJob.running||!root.draft)return
        terrainAction=action;terrainRequestKey=terrainKey()
        terrainPending=JSON.stringify({place:root.current,download:action==="terrain"&&downloadTerrain.checked})+"\n"
        terrainJob.stdinEnabled=true;terrainJob.running=true
        if(action==="terrain")root.message="Estimating terrain… regional tiles can take a few minutes on first use. Manual obstructions are kept."
    }
    function useTerrain(enabled) {
        let d=copy(draft);d[editing].useTerrain=enabled;draft=d;revision++
    }
    function changeHeight() {
        const value=Number(observerHeight.text)
        if(!observerHeight.text.trim()||!Number.isFinite(value)||value<0||value>100){root.message="Enter a height from 0 to 100 metres above ground.";return}
        let d=copy(draft);d[editing].observingHeight=value;d[editing].useTerrain=false;draft=d
        revision++;terrainProfile=null;readTerrain("terrain-status")
        root.message="Observing height changed. Recheck your measured trees/buildings at this height; their angles were kept."
    }
    readonly property string statePath:Quickshell.env("OMANOVA_TRIP_STATE")
    readonly property string runtime:Quickshell.env("OMANOVA_TRIP_RUNTIME")
    readonly property var current: draft ? draft[editing] : ({ name:"",lat:0,lon:0,elevation:0,timezone:"UTC",horizon:[] })
    readonly property bool staleResult:resultRevision !== revision
    function copy(value) {return JSON.parse(JSON.stringify(value))}
    function key(place) {return Number(place.lat).toFixed(6)+","+Number(place.lon).toFixed(6)+","+Number(place.elevation||0).toFixed(1)}
    function setSite(which,site) {
        let d=copy(draft), store=d.horizonStore||({})
        const previous=d[which];store[key(previous)]=previous.horizon
        if(key(previous)===key(site)){site.observingHeight=previous.observingHeight??1.7;site.useTerrain=previous.useTerrain===true}
        site.horizon=store[key(site)]||[]
        d[which]=site;d.horizonStore=store;draft=d;revision++;editingSector=-1;terrainProfile=null;fillManual();readTerrain("terrain-status")
    }
    function setMask(sectors) {
        let d=copy(draft),site=copy(current);site.horizon=sectors;d[editing]=site
        d.horizonStore=d.horizonStore||({});d.horizonStore[key(site)]=sectors
        const other=editing==="home"?"destination":"home"
        if(key(d[other])===key(site))d[other].horizon=sectors
        draft=d;revision++
    }
    function fillManual() {
        placeName.text=current.name;latitude.text=String(current.lat);longitude.text=String(current.lon)
        elevation.text=String(current.elevation);tz.text=current.timezone;observerHeight.text=String(current.observingHeight??1.7)
    }
    function switchPlace(which) {editing=which;editingSector=-1;obstructionName.clear();terrainProfile=null;fillManual();readTerrain("terrain-status")}
    function shiftDate(field,days) {
        const d=new Date(field.text+"T12:00:00Z")
        if(!Number.isFinite(d.getTime()) || d.toISOString().slice(0,10)!==field.text) {message="Enter a valid YYYY-MM-DD date first.";return}
        d.setUTCDate(d.getUTCDate()+days);field.text=d.toISOString().slice(0,10);revision++
    }
    function compare() {
        const d=copy(draft);d.start=firstDate.text;d.end=lastDate.text;d.weather=weather.checked
        draft=d;pending=JSON.stringify(d)+"\n";requestedRevision=revision
        message="Calculating both places… longer trips take a little longer."
        calculate.stdinEnabled=true;calculate.running=true
    }
    FileView {
        id:configFile;path:root.statePath+"/trip.json";printErrors:false
        onLoaded: {
            try {root.draft=JSON.parse(text());firstDate.text=root.draft.start;lastDate.text=root.draft.end;weather.checked=false;root.fillManual();root.readTerrain("terrain-status")}
            catch(e) {root.message="Could not read the trip settings."}
        }
    }
    FileView {
        id:resultFile;path:root.statePath+"/comparison.json";printErrors:false
        onLoaded: {try {root.result=JSON.parse(text());nightPicker.currentIndex=0} catch(e) {root.message="Could not read the comparison."}}
    }
    Process {
        id:calculate
        command:[root.runtime+"/.venv/bin/python",root.runtime+"/observatory/trips/trips.py","compare","--state",root.statePath].concat(Quickshell.env("OMANOVA_TRIP_FIXTURE")==="1"?["--fixture"]:[])
        environment:({"OPENBLAS_NUM_THREADS":"1"});stdinEnabled:true
        onStarted:{write(root.pending);root.pending="";stdinEnabled=false}
        stderr:StdioCollector {id:diagnostic}
        onExited:function(code) {
            if(code===0){root.resultRevision=root.requestedRevision;resultFile.reload();root.message="Comparison saved locally.";root.tab=2}
            else root.message=diagnostic.text.trim()||"Comparison unavailable. Check the dates and locations."
        }
    }
    Process {
        id:lookup
        command:[root.runtime+"/.venv/bin/python",root.runtime+"/observatory/trips/trips.py","lookup","--state",root.statePath]
        environment:({"OPENBLAS_NUM_THREADS":"1"});stdinEnabled:true
        onStarted:{write(root.pendingSearch);root.pendingSearch="";stdinEnabled=false}
        stdout:StdioCollector {id:lookupOutput}
        onExited:function(code) {
            if(code===0){try {root.searchRows=JSON.parse(lookupOutput.text);root.message=root.searchRows.length?"Choose a place below; its time zone comes with it.":"No places found."}catch(e){root.message="Lookup unavailable."}}
            else root.message="Lookup unavailable. Manual coordinates and time zone are still available."
        }
    }
    Process {
        id:terrainJob
        command:[root.runtime+"/.venv/bin/python",root.runtime+"/observatory/trips/trips.py",root.terrainAction,"--state",root.statePath]
        environment:({"OPENBLAS_NUM_THREADS":"1"});stdinEnabled:true
        onStarted:{write(root.terrainPending);root.terrainPending="";stdinEnabled=false}
        stdout:StdioCollector {id:terrainOutput}
        stderr:StdioCollector {id:terrainError}
        onExited:function(code) {
            downloadTerrain.checked=false
            if(root.terrainRequestKey!==root.terrainKey())return
            if(code===0) {
                try {
                    root.terrainProfile=JSON.parse(terrainOutput.text)
                    if(root.terrainAction==="terrain"&&root.terrainProfile){root.useTerrain(true);root.message="Terrain estimate ready. Manual trees/buildings were kept. Save & compare to apply it to viewing windows."}
                } catch(e) {root.message="Could not read the terrain estimate. Manual obstructions were kept."}
            } else root.message=terrainError.text.trim()||"Terrain unavailable. Manual obstructions were kept."
        }
    }
    Timer {interval:5000;running:root.cooling;onTriggered:root.cooling=false}
        Rectangle {
            id:ui;anchors.fill:parent;color:"#070d1b"
            component Copy:Text {Layout.fillWidth:true;wrapMode:Text.Wrap;textFormat:Text.PlainText;color:"#eef5ff";font.pixelSize:14}
            component Heading:Copy {font.pixelSize:24;font.bold:true}
            component Toggle:CheckBox {palette.windowText:"#eef5ff";palette.text:"#eef5ff";palette.buttonText:"#eef5ff";palette.button:"#15253c";palette.base:"#0a1424";palette.highlight:"#70edeb"}
            ColumnLayout {
                anchors.fill:parent;spacing:0
                ColumnLayout {
                    Layout.fillWidth:true;Layout.margins:20;spacing:6
                    Copy {text:root.terrainPreview?"O M A N O V A   /   TERRAIN PREVIEW":"O M A N O V A   /   TRIP PLANNER";color:"#70edeb";font.pixelSize:12}
                    Heading {text:qsTr("Trip Planner & My Horizon")}
                    Copy {text:root.terrainPreview?qsTr("Separate terrain preview · live locations, horizons, alerts and bar are unchanged. Save & compare keeps this preview locally."):qsTr("Plan a trip without changing your active observing location or alerts. Trip and horizon settings are saved locally.");color:"#a7b7ce"}
                    Flow {
                        Layout.fillWidth:true;spacing:8
                        TripButton {text:qsTr("1 · Destination & dates");onClicked:root.tab=0}
                        TripButton {text:qsTr("2 · My horizon");onClicked:root.tab=1}
                        TripButton {text:qsTr("3 · Compare");enabled:!!root.result;onClicked:root.tab=2}
                        TripButton {text:calculate.running?qsTr("Calculating…"):qsTr("Save & compare nights");enabled:!!root.draft&&!calculate.running&&!terrainJob.running;onClicked:root.compare()}
                    }
                    Copy {text:root.message;visible:text.length>0;color:"#ffcc7b"}
                }
                Rectangle {Layout.fillWidth:true;implicitHeight:1;color:"#2a3e58"}
                ScrollView {
                    id:scroll;Layout.fillWidth:true;Layout.fillHeight:true;clip:true
                    contentWidth:availableWidth
                    ColumnLayout {
                        width:scroll.availableWidth;spacing:14
                        ColumnLayout {
                            visible:root.tab===0;Layout.fillWidth:true;Layout.margins:20;spacing:14
                            GridLayout {
                                Layout.fillWidth:true;columns:width<800?1:2;columnSpacing:16;rowSpacing:12
                                Repeater {
                                    model:["home","destination"]
                                    Rectangle {
                                        required property string modelData
                                        Layout.fillWidth:true;implicitHeight:placeInfo.implicitHeight+28;radius:10;color:"#101c32";border.color:root.editing===modelData?"#70edeb":"#2a3e58"
                                        ColumnLayout {
                                            id:placeInfo;anchors.fill:parent;anchors.margins:14
                                            Copy {text:parent.parent.modelData==="home"?qsTr("HOME"):qsTr("DESTINATION");color:"#70edeb";font.pixelSize:12}
                                            Heading {text:root.draft?root.draft[parent.parent.modelData].name:"Loading…"}
                                            Copy {text:root.draft?root.draft[parent.parent.modelData].timezone:"";color:"#a7b7ce"}
                                            TripButton {text:parent.parent.modelData==="home"?qsTr("Edit Home copy"):qsTr("Choose destination");onClicked:root.switchPlace(parent.parent.modelData)}
                                        }
                                    }
                                }
                            }
                            Heading {text:root.editing==="home"?qsTr("Edit Home (trip copy)"):qsTr("Choose your destination")}
                            Copy {text:qsTr("Search sends only your city/postcode query to Open-Meteo/GeoNames when pressed. No automatic location tracking.");color:"#a7b7ce"}
                            RowLayout {
                                Layout.fillWidth:true
                                TripField {id:query;Layout.fillWidth:true;placeholderText:qsTr("City or postcode, optionally country");maximumLength:120;Accessible.name:placeholderText}
                                TripButton {text:qsTr("Search online");enabled:query.text.trim().length>=2&&!lookup.running&&!root.cooling;onClicked:{root.searchTarget=root.editing;root.searchRows=[];root.pendingSearch=JSON.stringify(query.text.trim())+"\n";root.cooling=true;lookup.stdinEnabled=true;lookup.running=true;root.message="Searching…"}}
                            }
                            Repeater {
                                model:root.searchRows
                                TripButton {
                                    required property var modelData
                                    Layout.fillWidth:true;text:modelData.label+" · "+(modelData.timezone||"choose time zone manually")
                                    onClicked:{root.editing=root.searchTarget;root.setSite(root.searchTarget,{name:modelData.name,lat:modelData.lat,lon:modelData.lon,elevation:modelData.elevation,timezone:modelData.timezone||"",horizon:[]});root.searchRows=[];root.message=modelData.timezone?"Location selected. Check the dates below.":"Time zone unavailable. Please enter it manually before comparing."}
                                }
                            }
                            Toggle {id:manual;text:qsTr("Manual coordinates and time zone")}
                            GridLayout {
                                visible:manual.checked;Layout.fillWidth:true;columns:width<800?1:3
                                TripField {id:placeName;Layout.fillWidth:true;placeholderText:qsTr("Place name");maximumLength:64}
                                TripField {id:latitude;Layout.fillWidth:true;placeholderText:qsTr("Latitude")}
                                TripField {id:longitude;Layout.fillWidth:true;placeholderText:qsTr("Longitude")}
                                TripField {id:elevation;Layout.fillWidth:true;placeholderText:qsTr("Elevation, metres")}
                                TripField {id:tz;Layout.fillWidth:true;placeholderText:qsTr("IANA zone, e.g. America/Chicago")}
                                TripButton {text:qsTr("Apply location");onClicked:{if(!latitude.text.trim()||!longitude.text.trim()){root.message="Enter latitude and longitude.";return}root.setSite(root.editing,{name:placeName.text,lat:Number(latitude.text),lon:Number(longitude.text),elevation:Number(elevation.text||0),timezone:tz.text,horizon:[]});root.message="Location applied to this trip."}}
                            }
                            Copy {text:qsTr("Home initially copies your saved Home point and system time zone. Verify the zone when planning travel. A changed observing point gets its own horizon.");color:"#a7b7ce"}
                            Heading {text:qsTr("Observing nights")}
                            Copy {text:qsTr("Choose 1–14 local evenings, inclusive. Each night runs from local noon to the following noon; daylight-saving changes are handled independently at each place.");color:"#a7b7ce"}
                            GridLayout {
                                Layout.fillWidth:true;columns:width<800?1:2
                                ColumnLayout {
                                    Layout.fillWidth:true
                                    Copy {text:qsTr("First observing night · YYYY-MM-DD")}
                                    RowLayout {
                                        TripField {id:firstDate;Layout.fillWidth:true;maximumLength:10;onTextEdited:root.revision++}
                                        TripButton {text:"−";Accessible.name:qsTr("First night one day earlier");onClicked:root.shiftDate(firstDate,-1)}
                                        TripButton {text:"+";Accessible.name:qsTr("First night one day later");onClicked:root.shiftDate(firstDate,1)}
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth:true
                                    Copy {text:qsTr("Last observing night · YYYY-MM-DD")}
                                    RowLayout {
                                        TripField {id:lastDate;Layout.fillWidth:true;maximumLength:10;onTextEdited:root.revision++}
                                        TripButton {text:"−";Accessible.name:qsTr("Last night one day earlier");onClicked:root.shiftDate(lastDate,-1)}
                                        TripButton {text:"+";Accessible.name:qsTr("Last night one day later");onClicked:root.shiftDate(lastDate,1)}
                                    }
                                }
                            }
                            Toggle {id:weather;text:qsTr("Fetch forecasts for this comparison (optional)");onClicked:root.revision++}
                            Copy {text:qsTr("Open-Meteo receives both locations rounded to two decimal places. Forecasts only cover the current forecast horizon; distant dates remain unavailable. This choice resets when the Observatory reopens.");color:"#a7b7ce"}
                        }
                        ColumnLayout {
                            visible:root.tab===1;Layout.fillWidth:true;Layout.margins:20;spacing:12
                            Heading {text:qsTr("My horizon · %1").arg(root.current.name)}
                            Flow {Layout.fillWidth:true;spacing:8;TripButton {text:qsTr("Home horizon");onClicked:root.switchPlace("home")} TripButton {text:qsTr("Destination horizon");onClicked:root.switchPlace("destination")}}
                            Copy {text:qsTr("True north = 0°/360°, east = 90°. A range such as 330° → 30° crosses north. Heights are your estimates above the horizon, not a terrain survey.");color:"#a7b7ce"}
                            Heading {text:qsTr("Estimated terrain")}
                            Copy {text:qsTr("Keep manual trees/buildings below. The terrain layer estimates hills and ridges; the higher layer blocks the view.");color:"#a7b7ce"}
                            RowLayout {
                                Layout.fillWidth:true
                                Copy {text:qsTr("Observing height above ground (metres)")}
                                TripField {id:observerHeight;Layout.preferredWidth:90;maximumLength:8;Accessible.name:qsTr("Observing height above ground in metres")}
                                TripButton {text:qsTr("Apply height");enabled:!terrainJob.running&&!calculate.running;onClicked:root.changeHeight()}
                            }
                            Copy {text:qsTr("Use your eye/telescope height, including a balcony if applicable. Changing it does not automatically adjust your measured tree/building angles.");color:"#a7b7ce"}
                            Toggle {id:downloadTerrain;text:qsTr("Allow one-time terrain download for this estimate");enabled:!terrainJob.running}
                            Copy {text:qsTr("Requests coarse 1° regional tiles from AWS, never your entered name or exact coordinates. Cached tiles are reused offline. Up to 16 tiles, 32 MB each; no background refresh. Calculation covers 50 km, from 70°S to 70°N.");color:"#a7b7ce"}
                            Flow {
                                Layout.fillWidth:true;spacing:8
                                TripButton {text:terrainJob.running?qsTr("Working…"):qsTr("Estimate terrain");enabled:!!root.draft&&!terrainJob.running&&!calculate.running;onClicked:root.readTerrain("terrain")}
                                Toggle {text:qsTr("Use estimated terrain in comparison");checked:root.current.useTerrain===true;enabled:!!root.terrainProfile&&!terrainJob.running&&!calculate.running;onClicked:root.useTerrain(checked)}
                            }
                            Copy {text:root.terrainProfile ? "Estimated terrain · computed "+root.terrainProfile.created.slice(0,10)+" · height "+root.terrainProfile.observingHeight+" m · grid ground "+root.terrainProfile.groundElevation+" m" : "No terrain estimate loaded for this location and height. Manual obstructions still work.";color:"#ffcc7b"}
                            Copy {visible:!!root.terrainProfile;text:root.terrainProfile?.limits||"";color:"#a7b7ce"}
                            Flow {
                                Layout.fillWidth:true;spacing:8
                                TripButton {text:qsTr("Terrain source & coverage");onClicked:Qt.openUrlExternally("https://registry.opendata.aws/terrain-tiles/")}
                                TripButton {text:qsTr("Terrain data credits");onClicked:Qt.openUrlExternally("https://github.com/tilezen/joerd/blob/master/docs/attribution.md")}
                            }
                            Copy {text:qsTr("Cyan: manual trees/buildings · amber: terrain estimate. Use terrain toggle controls whether the amber layer affects comparisons.");color:"#a7b7ce"}
                            HorizonChart { terrain:root.terrainProfile?.samples||[];Layout.fillWidth:true;Layout.preferredHeight:200;sectors:root.current.horizon}
                            Copy {text:qsTr("The shaded area is blocked. Overlaps use the higher edge. A hidden Moon can still brighten the sky, so the mask does not change astronomical darkness. These masks apply to trip comparisons; active-location alerts are unchanged.");color:"#a7b7ce"}
                            Repeater {
                                model:root.current.horizon
                                RowLayout {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth:true
                                    Copy {text:modelData.name+" · "+modelData.from+"° → "+modelData.to+"° · "+modelData.height+"° high"}
                                    TripButton {text:qsTr("Edit");onClicked:{root.editingSector=index;obstructionName.text=modelData.name;fromBearing.value=modelData.from;toBearing.value=modelData.to;obstructionHeight.value=modelData.height}}
                                    TripButton {text:qsTr("Remove");onClicked:{root.setMask(root.current.horizon.filter((x,i)=>i!==index));root.editingSector=-1}}
                                }
                            }
                            GridLayout {
                                Layout.fillWidth:true;columns:width<800?2:4
                                ColumnLayout {Layout.fillWidth:true;Copy {text:qsTr("Obstruction name")} TripField {id:obstructionName;Layout.fillWidth:true;placeholderText:qsTr("e.g. East trees");maximumLength:48}}
                                ColumnLayout {Copy {text:qsTr("From bearing")} TripSpin {id:fromBearing;from:0;to:359;value:60}}
                                ColumnLayout {Copy {text:qsTr("To bearing")} TripSpin {id:toBearing;from:0;to:360;value:120}}
                                ColumnLayout {Copy {text:qsTr("Height above horizon")} TripSpin {id:obstructionHeight;from:0;to:90;value:25}}
                            }
                            Flow {
                                Layout.fillWidth:true;spacing:8
                                TripButton {text:root.editingSector>=0?qsTr("Update obstruction"):qsTr("Add obstruction");enabled:obstructionName.text.trim().length>0&&fromBearing.value!==toBearing.value&&(root.editingSector>=0||root.current.horizon.length<32);onClicked:{let rows=root.copy(root.current.horizon);let s={name:obstructionName.text.trim(),from:fromBearing.value,to:toBearing.value,height:obstructionHeight.value};if(root.editingSector>=0)rows[root.editingSector]=s;else rows.push(s);root.setMask(rows);root.editingSector=-1;obstructionName.clear()}}
                                TripButton {text:qsTr("Cancel edit");visible:root.editingSector>=0;onClicked:{root.editingSector=-1;obstructionName.clear()}}
                            }
                            Copy {text:qsTr("Save & compare nights to see which viewing windows survive. Horizon profiles are kept locally per observing point.");color:"#a7b7ce"}
                        }
                        ColumnLayout {
                            visible:root.tab===2&&!!root.result;Layout.fillWidth:true;Layout.margins:20;spacing:14
                            Heading {text:qsTr("Home versus destination")}
                            Copy {text:root.result?.basis||"";color:"#a7b7ce"}
                            Copy {visible:root.staleResult;text:qsTr("Inputs changed or this is a saved comparison. Press Save & compare nights to refresh before relying on it.");color:"#ffcc7b"}
                            Flow {
                                Layout.fillWidth:true;spacing:10
                                TripChoice {id:nightPicker;model:root.result?.dates||[];Accessible.name:qsTr("Observing night")}
                                TripChoice {id:target;model:["All targets","Moon","Mercury","Venus","Mars","Jupiter","Saturn"];Accessible.name:qsTr("Target")}
                            }
                            GridLayout {
                                Layout.fillWidth:true;columns:width<900?1:2;columnSpacing:16;rowSpacing:16
                                Repeater {
                                    model:root.result&&nightPicker.currentIndex>=0?["home","destination"]:[]
                                    TripNightCard {required property string modelData;site:root.result[modelData];night:site.nights[nightPicker.currentIndex]||site.nights[0];side:modelData;targetFilter:target.currentText;Layout.alignment:Qt.AlignTop}
                                }
                            }
                            Heading {text:qsTr("Station passes and meteor activity")}
                            Copy {text:qsTr("Meteor entries are activity dates, not recalculated radiant windows. Use the Observatory for detailed meteor guidance.");color:"#a7b7ce"}
                            Repeater {
                                model:root.result?["home","destination"]:[]
                                ColumnLayout {
                                    required property string modelData
                                    Layout.fillWidth:true;spacing:6
                                    Copy {text:root.result[modelData].name;font.bold:true;font.pixelSize:19}
                                    Copy {text:root.result[modelData].stationNote;color:"#a7b7ce"}
                                    Repeater {
                                        model:root.result[modelData].stations
                                        Copy {required property var modelData;text:modelData.name+" · Home: "+modelData.look.home+" · Destination: "+modelData.look.destination+" · "+modelData.direction+" "+modelData.bearing+"° / "+modelData.altitude+"° up"}
                                    }
                                    Repeater {
                                        model:root.result[modelData].meteors
                                        Copy {required property var modelData;text:modelData.name+" · activity "+modelData.start+" → "+modelData.end+" · peak "+modelData.peak;color:"#a7b7ce"}
                                    }
                                }
                            }
                            Heading {text:qsTr("Launches during the destination dates")}
                            Copy {text:root.result?.launchNote||"";color:"#ffcc7b"}
                            Copy {visible:root.result?.launchStale===true;text:qsTr("Launch cache is stale or unavailable. These entries are not a current schedule.");color:"#ffcc7b"}
                            Copy {visible:!(root.result?.launches||[]).length;text:qsTr("No matching launch in the available cache. This does not establish that no launch will occur.")}
                            Repeater {
                                model:root.result?.launches||[]
                                Copy {required property var modelData;text:modelData.name+" · "+modelData.status+" · precision "+modelData.precision+(modelData.time ? "\nHome: "+modelData.time.home+"\nDestination: "+modelData.time.destination : "\nTentative provider date (UTC): "+modelData.providerDate+" · no confirmed local time")}
                            }
                            Copy {text:root.result?.limits||"";color:"#a7b7ce"}
                        }
                    }
                }
            }
        }
        IpcHandler {
            target:"omanova-trips"
            function tab(index:int):void {root.tab=index}
            function compare():void {root.compare()}
            function summary():string {return JSON.stringify({ready:!!root.draft,busy:calculate.running,hasResult:!!root.result,homeZone:root.draft?.home?.timezone,destinationZone:root.draft?.destination?.timezone,dates:root.result?.dates,tab:root.tab,stale:root.staleResult})}
            function terrainSample():void {
                if(Quickshell.env("OMANOVA_TRIP_FIXTURE")==="1"){root.switchPlace("home");root.tab=1}
            }
            function fixtureEnableTerrain():void {
                if(Quickshell.env("OMANOVA_TRIP_FIXTURE")==="1"&&root.terrainProfile)root.useTerrain(true)
            }
            function scrollPreview(y:real):void {if(Quickshell.env("OMANOVA_TRIP_FIXTURE")==="1")scroll.contentItem.contentY=y}
            function terrainSummary():string {return JSON.stringify({busy:terrainJob.running,loaded:!!root.terrainProfile,enabled:root.current.useTerrain,height:root.current.observingHeight,samples:root.terrainProfile?.samples?.length})}
            function sampleHorizon():void {
                if(Quickshell.env("OMANOVA_TRIP_FIXTURE")==="1") {root.switchPlace("destination");root.setMask([{name:"Sample east trees",from:45,to:135,height:30},{name:"Sample south roof",from:150,to:230,height:22}]);root.tab=1}
            }
            function capture(name:string):void {if(Quickshell.env("OMANOVA_TRIP_FIXTURE")==="1"&&["plan","horizon","comparison"].includes(name))ui.grabToImage(r=>r.saveToFile(root.statePath+"/"+name+".png"))}
            
        }
}
