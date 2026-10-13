import QtQuick
import QtQuick.Layouts

// Calendar grid displaying weekly timeline with styled event blocks
Item {
  id: root

  property var activeStyleMap: ({})
  property var events: []
  // First day of the displayed week; the day header derives from it
  property var weekStart: new Date()
  // Config (from team.json): 0=Mon .. 6=Sun, and visible hour range
  property int weekStartDay: 0
  property int startHour: 7
  property int endHour: 18
  property color themeForeground: "#bebebe"
  property color themeMuted: "#555555"
  property color themeAccent: "#e68e0d"
  property color themeBg: "#121212"

  // Hover tooltip state. Keyed by the event's unique id (string): object
  // references from `modelData` are NOT stable across re-evaluations, so an
  // identity comparison would never match and the tooltip would never hide.
  property string hoveredId: ""
  property var hoveredEvent: null
  property point tipPos: Qt.point(0, 0)

  // Days of the week header, derived from weekStart + weekStartDay
  readonly property var days: {
    var names = ["PON.", "WT.", "ŚR.", "CZW.", "PT.", "SOB.", "NIEDZ."]
    var out = []
    for (var i = 0; i < 7; i++) {
      var d = new Date(root.weekStart)
      d.setDate(d.getDate() + i)
      out.push(names[(root.weekStartDay + i) % 7] + " " + d.getDate())
    }
    return out
  }
  readonly property int totalHours: Math.max(1, endHour - startHour)

  // Adaptive: each hour row fills 1/N of the Flickable height so grid always fits
  readonly property real pxPerHour: gridFlickable.height > 0
    ? gridFlickable.height / totalHours
    : 50

  ColumnLayout {
    anchors.fill: parent
    spacing: 0

    // Header with days
    RowLayout {
      Layout.fillWidth: true
      Layout.fillHeight: false
      Layout.preferredHeight: 38
      Layout.minimumHeight: 38
      Layout.maximumHeight: 38
      spacing: 0

      // Time gutter spacer
      Item {
        width: 50
        height: parent.height
      }

      Repeater {
        model: root.days
        Rectangle {
          Layout.fillWidth: true
          Layout.fillHeight: true
          color: "transparent"
          border.color: Qt.rgba(root.themeForeground.r, root.themeForeground.g, root.themeForeground.b, 0.08)
          border.width: 1

          Text {
            anchors.centerIn: parent
            text: modelData
            color: root.themeForeground
            font.pixelSize: 11
            font.bold: true
          }
        }
      }
    }

    // Scrollable / Expandable Grid Area
    Flickable {
      id: gridFlickable
      Layout.fillWidth: true
      Layout.fillHeight: true
      contentWidth: width
      // Content height matches the adaptive row height; scroll only if window is tiny
      contentHeight: root.totalHours * root.pxPerHour
      clip: true

      Item {
        width: gridFlickable.width
        height: gridFlickable.contentHeight

        // Background hour lines
        Repeater {
          model: root.totalHours
          Item {
            y: index * root.pxPerHour
            width: parent.width
            height: root.pxPerHour

            // Hour label
            Text {
              x: 8
              y: -8
              text: (root.startHour + index < 10 ? "0" : "") + (root.startHour + index) + ":00"
              color: root.themeMuted
              font.pixelSize: 10
            }

            // Grid line
            Rectangle {
              x: 50
              y: 0
              width: parent.width - 50
              height: 1
              color: Qt.rgba(root.themeForeground.r, root.themeForeground.g, root.themeForeground.b, 0.08)
            }
          }
        }

        // Vertical day dividers
        RowLayout {
          x: 50
          width: parent.width - 50
          height: parent.height
          spacing: 0

          Repeater {
            model: 7
            Rectangle {
              Layout.fillWidth: true
              Layout.fillHeight: true
              color: "transparent"
              border.color: Qt.rgba(root.themeForeground.r, root.themeForeground.g, root.themeForeground.b, 0.05)
              border.width: 1
            }
          }
        }

        // Render Events
        Repeater {
          model: root.events
          delegate: Item {
            id: eventDelegate

            property var eventItem: modelData
            property var userStyle: root.activeStyleMap[eventItem.userId] || null
            property real colWidth: (parent.width - 50) / 7
            property var layout: eventItem.layout || { leftPercent: 0, widthPercent: 100, col: 0, totalCols: 1 }

            // Hide event if member not currently active / assigned style
            visible: userStyle !== null
            x: 50 + (eventItem.dayIndex || 0) * colWidth + 2 + layout.leftPercent / 100.0 * (colWidth - 4)
            y: ((eventItem.startHour || 8) - root.startHour + (eventItem.startMinute || 0) / 60.0) * root.pxPerHour
            width: Math.max(40, (colWidth - 4) * layout.widthPercent / 100.0)
            height: Math.max(26, ((eventItem.durationMinutes || 60) / 60.0) * root.pxPerHour)

            Rectangle {
              anchors.fill: parent
              radius: 4
              // color: "transparent"   // PatternRect handles the fill; don't let QML default (white) bleed through
              border.color: eventDelegate.userStyle ? eventDelegate.userStyle.borderColor : root.themeAccent
              border.width: 1
              clip: true

              // Pattern & Tint fill
              PatternRect {
                anchors.fill: parent
                radius: 4
                backgroundColor: eventDelegate.userStyle ? eventDelegate.userStyle.backgroundColor : "#333"
                stripeColor: eventDelegate.userStyle ? eventDelegate.userStyle.stripeColor : "#555"
                pattern: eventDelegate.userStyle ? eventDelegate.userStyle.pattern : "solid"
                stripeSpacing: 8
                stripeWidth: 2
              }


              // Event text content
              Column {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 1

                Text {
                  width: parent.width
                  text: eventDelegate.eventItem.title || ""
                  font.pixelSize: 10
                  font.bold: true
                  color: eventDelegate.userStyle ? eventDelegate.userStyle.textColor : root.themeForeground
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: eventDelegate.eventItem.timeLabel || ""
                  font.pixelSize: 9
                  color: eventDelegate.userStyle ? eventDelegate.userStyle.textColor : root.themeMuted
                  opacity: 0.85
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: eventDelegate.eventItem.userName || ""
                  font.pixelSize: 9
                  color: eventDelegate.userStyle ? eventDelegate.userStyle.textColor : root.themeMuted
                  opacity: 0.85
                  elide: Text.ElideRight
                }
              }
            }

            // Hover → tooltip with full details (pure hover, no clicks needed)
            MouseArea {
              id: tipArea
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.NoButton
              onEntered: {
                root.hoveredId = String(eventDelegate.eventItem.id)
                root.hoveredEvent = eventDelegate.eventItem
              }
              onExited: {
                if (root.hoveredId === String(eventDelegate.eventItem.id)) {
                  root.hoveredId = ""
                  root.hoveredEvent = null
                }
              }
              onMouseXChanged: root.moveTip(tipArea)
              onMouseYChanged: root.moveTip(tipArea)
            }

            Component.onDestruction: {
              if (root.hoveredId === String(eventDelegate.eventItem.id)) {
                root.hoveredId = ""
                root.hoveredEvent = null
              }
            }
          }
        }
      }
    }
  }

  // Tooltip: direct child of root (outside the ColumnLayout and Flickable)
  // so the layout never positions it and it never scrolls or clips away.
  Rectangle {
    id: tip
    z: 100
    visible: root.hoveredId !== ""
    width: 240
    height: tipCol.implicitHeight + 16
    radius: 6
    color: Qt.darker(root.themeBg, 1.5)
    border.color: Qt.rgba(root.themeAccent.r, root.themeAccent.g, root.themeAccent.b, 0.5)
    border.width: 1

    x: Math.max(4, Math.min(root.tipPos.x + 14, root.width - width - 4))
    y: root.tipPos.y + 14 + height > root.height
      ? Math.max(4, root.tipPos.y - height - 10)
      : root.tipPos.y + 14

    Column {
      id: tipCol
      anchors.fill: parent
      anchors.margins: 8
      spacing: 3

      Text {
        width: parent.width
        text: root.hoveredEvent ? (root.hoveredEvent.title || "") : ""
        font.pixelSize: 11
        font.bold: true
        color: root.themeForeground
        wrapMode: Text.WordWrap
      }
      Text {
        width: parent.width
        text: root.hoveredEvent ? (root.hoveredEvent.timeLabel || "") : ""
        font.pixelSize: 10
        color: root.themeAccent
      }
      Text {
        width: parent.width
        text: root.hoveredEvent ? (root.hoveredEvent.userName || "") : ""
        font.pixelSize: 10
        color: root.themeForeground
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        visible: root.hoveredEvent && root.hoveredEvent.location !== ""
        text: root.hoveredEvent ? ("📍 " + root.hoveredEvent.location) : ""
        font.pixelSize: 10
        color: root.themeForeground
        wrapMode: Text.WordWrap
      }
      Text {
        width: parent.width
        visible: root.hoveredEvent && root.hoveredEvent.description !== ""
        text: root.hoveredEvent ? (root.hoveredEvent.description || "") : ""
        font.pixelSize: 10
        color: root.themeForeground
        opacity: 0.9
        wrapMode: Text.WordWrap
        maximumLineCount: 4
        elide: Text.ElideRight
      }
    }
  }

  // Called from the delegate's hover areas to follow the cursor
  function moveTip(area) {
    if (hoveredId === "") return
    tipPos = area.mapToItem(root, area.mouseX, area.mouseY)
  }
}
