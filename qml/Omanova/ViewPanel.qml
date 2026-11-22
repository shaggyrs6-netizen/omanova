import "." as App
import QtQuick

Rectangle {
    id: panel
    property string appearance: "atlas"
    property bool emphasis: false
    readonly property bool useDesignColours: !App.Palette.themed && App.Palette.observingMode === "normal"
    readonly property color highlight: !useDesignColours ? App.Palette.accent :
        appearance === "field" ? "#ffc982" : appearance === "mission" ? "#70edeb" : "#c7b6ff"

    radius: appearance === "mission" ? 5 : 12
    color: !useDesignColours ? App.Palette.surface :
        appearance === "field" ? (emphasis ? "#32252e" : "#201a2b") :
        appearance === "mission" ? "#0a1828" : "#171a30"
    border.color: emphasis ? highlight : !useDesignColours ? App.Palette.line :
        appearance === "field" ? "#57405c" : appearance === "mission" ? "#315b70" : "#3d4166"
    Rectangle {
        visible: panel.useDesignColours && panel.appearance === "mission"
        width: Math.min(48, parent.width / 5)
        height: 2
        x: 10
        color: panel.highlight
    }
}
