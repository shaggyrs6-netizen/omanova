import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: page
    spacing: 14
    property var catalog: null
    property string loadError: ""
    property bool dropInOnly: false
    readonly property var visibleSites: (catalog?.sites ?? []).filter(site => !dropInOnly || site.dropIn)

    function duration(minutes) {
        const hours = Math.floor(minutes / 60)
        return hours ? qsTr("%1 h %2 min").arg(hours).arg(minutes % 60) : qsTr("%1 min").arg(minutes)
    }
    function mapLink(site) {
        return "https://www.openstreetmap.org/?mlat=" + site.latitude + "&mlon=" + site.longitude
            + "#map=15/" + site.latitude + "/" + site.longitude
    }

    component Copy: Text {
        Layout.fillWidth: true
        color: "#eef5ff"
        font.pixelSize: 15
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }
    component Action: Button {
        id: action
        implicitHeight: 35
        leftPadding: 11
        rightPadding: 11
        contentItem: Text {
            text: action.text
            color: "#eef5ff"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: 14
        }
        background: Rectangle {
            radius: 6
            color: action.checked || action.hovered ? "#233c55" : "#15253c"
            border.color: action.visualFocus || action.checked ? "#70edeb" : "#36516d"
        }
    }

    FileView {
        path: Quickshell.env("OMASKY_DARK_SITES")
        onLoaded: {
            try { page.catalog = JSON.parse(text()) }
            catch (error) { page.loadError = qsTr("Could not read the site catalogue.") }
        }
        onLoadFailed: page.loadError = qsTr("Could not load the site catalogue.")
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.margins: 22
        spacing: 8
        Copy { text: Quickshell.env("OMASKY_DARK_SITES_EMBEDDED") === "1" ? qsTr("OMANOVA OBSERVATORY  /  FIELD GUIDE") : qsTr("OMANOVA OBSERVATORY  /  PREVIEW"); color: "#70edeb"; font.pixelSize: 12; font.letterSpacing: 1.6 }
        Copy { text: qsTr("Dark-sky sites"); font.pixelSize: 34; font.bold: true }
        Copy { text: qsTr("Near Mount Juliet, Tennessee"); color: "#a7b7ce" }
        Copy {
            text: qsTr("Approximate road miles and drive times from central Mount Juliet. Routes use public map data without live traffic. Check the site’s access page before heading out.")
            color: "#a7b7ce"
        }
        Copy {
            text: qsTr("Lower Bortle numbers and higher SQM readings mean darker skies. Ratings describe the site in good conditions. Moonlight, clouds and nearby lights can change what you see.")
            color: "#a7b7ce"
        }
        Action {
            checkable: true
            checked: page.dropInOnly
            text: qsTr("Drop-in night access only")
            onToggled: page.dropInOnly = checked
        }
        Copy {
            visible: !!page.catalog?.checked
            text: visible ? qsTr("Access and routes checked · %1").arg(page.catalog.checked) : ""
            color: "#a7b7ce"
        }
        Copy {
            visible: !page.catalog
            text: page.loadError || qsTr("Loading sites…")
        }
    }

    Repeater {
        model: page.visibleSites
        delegate: Rectangle {
            id: card
            required property var modelData
            Layout.fillWidth: true
            Layout.leftMargin: 22
            Layout.rightMargin: 22
            implicitHeight: details.implicitHeight + 34
            color: "#111e31"
            border.color: "#2a3e58"
            radius: 12

            ColumnLayout {
                id: details
                anchors.fill: parent
                anchors.margins: 17
                spacing: 6
                Copy { text: card.modelData.name; font.pixelSize: 22; font.bold: true }
                Copy {
                    text: qsTr("%1 · %2 mi by road · about %3")
                        .arg(card.modelData.area).arg(card.modelData.roadMiles).arg(page.duration(card.modelData.driveMinutes))
                    color: "#70edeb"
                }
                Copy { text: card.modelData.darkness; font.bold: true }
                Copy { text: card.modelData.darknessDetail; color: "#a7b7ce" }
                Copy { text: card.modelData.access; color: card.modelData.dropIn ? "#eef5ff" : "#ffcc7b"; font.bold: true }
                Copy { text: card.modelData.accessDetail; color: "#a7b7ce" }
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    Action { text: qsTr("Map pin ↗"); onClicked: Qt.openUrlExternally(page.mapLink(card.modelData)) }
                    Action { text: qsTr("Site information ↗"); onClicked: Qt.openUrlExternally(card.modelData.visit) }
                    Action { text: card.modelData.evidenceLabel + " ↗"; onClicked: Qt.openUrlExternally(card.modelData.evidence) }
                    Action {
                        visible: !!card.modelData.hours || !!card.modelData.rating
                        text: card.modelData.hours ? qsTr("Park hours ↗") : qsTr("Bortle rating ↗")
                        onClicked: Qt.openUrlExternally(card.modelData.hours || card.modelData.rating)
                    }
                }
            }
        }
    }
    Copy {
        Layout.margins: 22
        text: qsTr("Route estimates via OSRM · map data © OpenStreetMap contributors.")
        color: "#a7b7ce"
    }
}
