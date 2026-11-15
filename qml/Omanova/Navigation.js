.pragma library
// Stable page keys. Numeric adapters only preserve existing event/IPC references.
var groups = [
    {id:"tonight", label:"Tonight"}, {id:"sky", label:"Sky"},
    {id:"spaceflight", label:"Satellites & launches"}, {id:"plan", label:"Plan"},
    {id:"log", label:"Log"}, {id:"settings", label:"Settings"}
];
var pages = [
    {id:"overview", label:"Overview", group:"tonight", legacy:0},
    {id:"conditions", label:"Conditions", group:"tonight", legacy:2},
    {id:"sky-view", label:"Sky View", group:"sky", legacy:1},
    {id:"sky-finder", label:"Sky Finder", group:"sky", legacy:23, extended:true},
    {id:"moon", label:"Moon", group:"sky", legacy:5},
    {id:"planets", label:"Planets", group:"sky", legacy:7},
    {id:"comets", label:"Comets", group:"sky", legacy:8},
    {id:"meteors", label:"Meteor Showers", group:"sky", legacy:6},
    {id:"eclipses", label:"Eclipses", group:"sky", legacy:9},
    {id:"aurora", label:"Aurora", group:"sky", legacy:13},
    {id:"events", label:"Events", group:"spaceflight", legacy:3},
    {id:"orbit", label:"Orbit", group:"spaceflight", legacy:4},
    {id:"watchlist", label:"Watchlist", group:"spaceflight", legacy:11},
    {id:"trains", label:"Starlink Trains", group:"spaceflight", legacy:12},
    {id:"plumes", label:"Launch Plumes", group:"spaceflight", legacy:10},
    {id:"following", label:"Launch Following", group:"spaceflight", legacy:18, extended:true},
    {id:"trips", label:"Trip Planner", group:"plan", legacy:17, extended:true},
    {id:"sites", label:"Destination Sites", group:"plan", legacy:22, extended:true},
    {id:"regional-sites", label:"Regional Sites", group:"plan", legacy:14},
    {id:"calendar", label:"Calendar Export", group:"plan", legacy:20, extended:true},
    {id:"offline", label:"Offline Cards", group:"plan", legacy:21, extended:true},
    {id:"log", label:"Observing Log", group:"log", legacy:15},
    {id:"settings", label:"Settings", group:"settings", legacy:16, extended:true},
    {id:"equipment", label:"My Equipment and Sky", group:"settings", legacy:19, extended:true}
];
function available(extended) { return pages.filter(p => extended || !p.extended); }
function page(id) { return pages.find(p => p.id === id) || null; }
function fromLegacy(index) { return pages.find(p => p.legacy === index)?.id || ""; }
function section(id) { return page(id)?.group || "tonight"; }
function sectionPages(group, extended) { return available(extended).filter(p => p.group === group); }
