import QtQuick
import Quickshell

BarWidget {
    id: root

    // Module name for Omarchy
    property string moduleName: "shpaq.omateamcal"

    // Track if panel is open
    readonly property bool opened: panelLoader.item !== null

    // Bar widget appearance
    width: 32
    height: 30

    contentItem: Rectangle {
        anchors.fill: parent
        radius: 4
        color: mouseArea.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15) : "transparent"

        Text {
            anchors.centerIn: parent
            text: "📅"
            font.pixelSize: 14
        }
    }

    // Mouse interaction
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor

        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton) {
                if (root.opened) {
                    panelLoader.sourceComponent = undefined;
                } else {
                    panelLoader.sourceComponent = panelComponent;
                }
            }
        }
    }

    // Lazy loader for popup panel
    Loader {
        id: panelLoader
    }

    // Panel component definition - creates PopupWindow anchored to this bar widget
    Component {
        id: panelComponent
        PopupWindow {
            // Panel will receive shell, bar, and theme properties from Omarchy shell
            // The PopupWindow is automatically positioned by Omarchy
        }
    }
}