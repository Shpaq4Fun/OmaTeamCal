import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Sidebar list with checkboxes and live matching swatches for each team member
Item {
  id: root

  property var users: []
  // Selected member ids — parent owns this state; the users model stays stable
  property var selectedUserIds: []
  property var activeStyleMap: ({})
  property color themeForeground: "#bebebe"
  property color themeMuted: "#555555"
  property color themeAccent: "#e68e0d"
  property color themeBg: "#121212"

  signal memberToggled(string userId, bool active)

  ColumnLayout {
    anchors.fill: parent
    spacing: 10

    Text {
      text: "Team Members"
      color: root.themeForeground
      font.pixelSize: 14
      font.bold: true
      Layout.fillWidth: true
    }

    Text {
      text: "Select members to plan meeting"
      color: root.themeMuted
      font.pixelSize: 11
      Layout.fillWidth: true
    }

    Rectangle {
      Layout.fillWidth: true
      height: 1
      color: Qt.rgba(root.themeForeground.r, root.themeForeground.g, root.themeForeground.b, 0.12)
    }

    ListView {
      id: userList
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      spacing: 4
      model: root.users

      delegate: Item {
        id: rowDelegate
        width: userList.width
        height: 32

        property var user: modelData
        property bool isActive: root.selectedUserIds.indexOf(user.id) !== -1
        property var userStyle: root.activeStyleMap[user.id] || null

        Rectangle {
          anchors.fill: parent
          radius: 6
          color: mouseArea.containsMouse ? Qt.rgba(root.themeAccent.r, root.themeAccent.g, root.themeAccent.b, 0.08) : "transparent"

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            spacing: 8

            // Swatch displaying the exact tint & pattern when active
            Rectangle {
              width: 18
              height: 18
              radius: 4
              border.color: rowDelegate.isActive ? root.themeAccent : root.themeMuted
              border.width: 1.5
              clip: true

              PatternRect {
                anchors.fill: parent
                radius: 3
                visible: rowDelegate.isActive && rowDelegate.userStyle !== null
                backgroundColor: rowDelegate.userStyle ? rowDelegate.userStyle.backgroundColor : "transparent"
                stripeColor: rowDelegate.userStyle ? rowDelegate.userStyle.stripeColor : "transparent"
                pattern: rowDelegate.userStyle ? rowDelegate.userStyle.pattern : "solid"
                stripeSpacing: 4
                stripeWidth: 1.5
              }

              // Check icon / dot when active
              Text {
                anchors.centerIn: parent
                text: "✓"
                font.pixelSize: 10
                font.bold: true
                color: rowDelegate.userStyle ? rowDelegate.userStyle.textColor : root.themeAccent
                visible: rowDelegate.isActive
              }
            }

            // Member name
            Text {
              Layout.fillWidth: true
              text: rowDelegate.user.name
              color: rowDelegate.isActive ? root.themeForeground : root.themeMuted
              font.pixelSize: 12
              font.bold: rowDelegate.isActive
              elide: Text.ElideRight
            }
          }

          MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.memberToggled(rowDelegate.user.id, !rowDelegate.isActive);
            }
          }
        }
      }
    }
  }
}
