pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Colors.js" as Colors
QtObject {
    id: root
    readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME")+"/.local/share"
    readonly property string directory: Quickshell.env("OMASKY_STATE") || dataHome+"/omasky"
    readonly property string runtime: Quickshell.env("OMASKY_RUNTIME") || Quickshell.env("OMASKY_ORBIT_TOOL") || directory+"/runtime"
    property bool testFile: false
    readonly property string themeFile: testFile && Quickshell.env("OMANOVA_THEME_TRIAL")==="1" ? directory+"/theme-test.toml" : Quickshell.env("HOME")+"/.local/state/omarchy/current/theme/colors.toml"
    property bool follow: false
    property string previewTheme: ""
    property string raw: ""
    property string error: ""
    readonly property var resolved: Colors.palette(previewTheme || raw)
    readonly property bool themed: follow && !!resolved
    readonly property bool missing: follow && !resolved
    readonly property color background: themed ? resolved.background : "#070d1b"
    readonly property color surface: themed ? resolved.surface : "#101c32"
    readonly property color field: themed ? resolved.field : "#0a1424"
    readonly property color button: themed ? resolved.button : "#15253c"
    readonly property color hover: themed ? resolved.hover : "#1a3049"
    readonly property color ink: themed ? resolved.ink : "#eef5ff"
    readonly property color muted: themed ? resolved.muted : "#a7b7ce"
    readonly property color accent: themed ? resolved.accent : "#70edeb"
    readonly property color violet: themed ? resolved.violet : "#a8a1ff"
    readonly property color border: themed ? resolved.border : "#36516d"
    readonly property color line: themed ? resolved.border : "#2a3e58"
    readonly property color good: themed ? resolved.good : "#70edeb"
    readonly property color warning: themed ? resolved.warning : "#ffcc7b"
    readonly property color bad: themed ? resolved.bad : "#f18d98"
    readonly property color terrain: themed ? resolved.terrain : "#ffcc7b"
    readonly property color shade: themed ? Colors.blend(resolved.background,resolved.accent,.20) : "#284851"
    readonly property color onAccent: Colors.readable("#ffffff",String(accent),4.5)
    property FileView preferences: FileView {
        path: root.directory+"/appearance.json";watchChanges:true;printErrors:false
        onFileChanged:reload()
        onLoaded:{try {root.follow=JSON.parse(text()).mode==="desktop"}catch(e){root.follow=false}}
        onLoadFailed:root.follow=false
    }
    property FileView desktop: FileView {
        path:root.themeFile;watchChanges:true;printErrors:false
        onLoaded:root.raw=text()
        onFileChanged:reload()
        onLoadFailed:root.raw=""
    }
    // Reopen the path after a theme's symlink target changes as well as file edits.
    property Timer refresh: Timer {interval:2000;repeat:true;running:root.follow;onTriggered:desktop.reload()}
    property Process save: Process {
        command:[root.runtime+"/.venv/bin/python",root.runtime+"/appearance.py","--state",root.directory,"--mode",root.follow?"observatory":"desktop"]
        stderr:StdioCollector {id:diagnostics}
        onExited:function(code){if(code===0){root.error="";preferences.reload()}else root.error="Appearance could not be saved. Try again."}
    }
    function sample(name) {
        if(Quickshell.env("OMANOVA_THEME_TRIAL")!=="1")return
        testFile=name==="file"
        previewTheme=name==="light" ? 'background="#f5f2e9"\nforeground="#24202c"\naccent="#694086"\nmuted="#6c6672"\ngreen="#267c42"\nyellow="#9c6400"\nred="#b6273c"\norange="#a65b12"\nmagenta="#85417e"'
            : name==="dark" ? 'background="#101c20"\nforeground="#e4f1ec"\naccent="#78cba7"\nmuted="#a4b7b0"\ngreen="#8cd59e"\nyellow="#e9c97a"\nred="#ee929e"\norange="#e2aa72"\nmagenta="#c0a9e3"' : ""
    }
    function toggle() {if(!save.running)save.running=true}
}
