import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

import "components"
import "scripts/DataController.js" as DataController

// Omarchy bar widget + popup panel in one entry point (manifest points
// entryPoints.barWidget here). The shell injects bar/moduleName/settings;
// theme colors come live from the Color singleton, so theme switches apply
// without any file watching of our own. The popup is a KeyboardPanel anchored
// to the bar button — outside-click dismissal and focus handling included.
Panel {
    id: root

    moduleName: "shpaq.omateamcal"
    ipcTarget: "shpaq.omateamcal"

    // Theme (live from the active Omarchy theme via the Color singleton)
    readonly property color foreground: Color.foreground
    readonly property color background: Color.background
    readonly property color accent: Color.accent
    readonly property color muted: Color.muted
    readonly property bool barVertical: bar ? bar.vertical : false

    // Team roster: stable ListView model, never reassigned on toggle
    property var teamData: []
    // Selected member ids — single source of truth for the checkbox state
    property var selectedUserIds: []
    property var activeStyleMap: ({})

    // Events from DataController
    property var events: []

    // Loading / error state
    property bool loading: false
    property string errorMessage: ""
    property int weekOffset: 0

    // Monday 00:00 of the displayed week
    function weekStartDate(offset) {
        var d = new Date();
        var day = d.getDay();
        var diffToMon = (day === 0 ? -6 : 1) - day;
        var monday = new Date(d);
        monday.setDate(d.getDate() + diffToMon + offset * 7);
        monday.setHours(0, 0, 0, 0);
        return monday;
    }
    readonly property var weekStart: weekStartDate(weekOffset)

    function weekLabel(offset) {
        var monday = weekStartDate(offset);
        var sunday = new Date(monday);
        sunday.setDate(monday.getDate() + 6);
        var monthNames = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
        return monthNames[monday.getMonth()] + " " + monday.getDate() + " - " + monthNames[sunday.getMonth()] + " " + sunday.getDate();
    }

    // ── Color / style engine ──

    function parseHex(h) {
        var s = String(h || "#000000").replace("#", "");
        if (s.length === 3) s = s[0]+s[0]+s[1]+s[1]+s[2]+s[2];
        return { r: parseInt(s.substring(0, 2), 16) / 255.0, g: parseInt(s.substring(2, 4), 16) / 255.0, b: parseInt(s.substring(4, 6), 16) / 255.0 };
    }
    function toRGB(c) { if (typeof c === "string") return parseHex(c); if (c && typeof c.r === "number") return { r: c.r, g: c.g, b: c.b }; return { r: 0, g: 0, b: 0 }; }
    function lerpColor(c1, c2, t) { var a = toRGB(c1), b = toRGB(c2); return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1.0); }

    readonly property var _tintLevels: [0.18, 0.38, 0.62, 0.88]
    readonly property var _patternNames: ["solid", "stripe-45", "stripe-135", "dots", "crosshatch"]
    readonly property var _slots: [
        {tint:3,pattern:0},{tint:0,pattern:1},{tint:2,pattern:2},{tint:1,pattern:3},
        {tint:3,pattern:4},{tint:0,pattern:0},{tint:2,pattern:1},{tint:1,pattern:2},
        {tint:3,pattern:3},{tint:0,pattern:4},{tint:2,pattern:0},{tint:1,pattern:0},
        {tint:0,pattern:2},{tint:0,pattern:3},{tint:1,pattern:1},{tint:1,pattern:4},
        {tint:2,pattern:3},{tint:2,pattern:4},{tint:3,pattern:1},{tint:3,pattern:2}
    ]

    function buildStyle(tintIdx, patternIdx, accent, bg) {
        var factor = _tintLevels[Math.max(0, Math.min(3, tintIdx))];
        var pattern = _patternNames[Math.max(0, Math.min(4, patternIdx))];
        var baseBg = lerpColor(bg, accent, factor);
        var stripeColor = factor > 0.5 ? lerpColor(baseBg, bg, 0.28) : lerpColor(baseBg, accent, 0.40);
        var bgRGB = toRGB(baseBg);
        var luminance = 0.299*bgRGB.r + 0.587*bgRGB.g + 0.114*bgRGB.b;
        var textColor = luminance > 0.45 ? Qt.rgba(0.05, 0.05, 0.05, 1.0) : Qt.rgba(0.94, 0.94, 0.94, 1.0);
        var borderColor = lerpColor(accent, Qt.rgba(1,1,1,1), 0.15);
        return { tintFactor: factor, pattern: pattern, backgroundColor: baseBg, stripeColor: stripeColor, borderColor: borderColor, textColor: textColor };
    }

    // Pure: takes the already-selected user list, no id references, so it is
    // safe to call from any scope.
    function computeStyleMap(users, accent, bg) {
        var map = {};
        for (var j = 0; j < users.length; j++) { var slot = _slots[j % _slots.length]; map[users[j].id] = buildStyle(slot.tint, slot.pattern, accent, bg); }
        return map;
    }

    // Selected users derived from teamData + selectedUserIds
    function selectedUsers() {
        var out = [];
        for (var i = 0; i < root.teamData.length; i++) {
            if (root.selectedUserIds.indexOf(root.teamData[i].id) !== -1) out.push(root.teamData[i]);
        }
        return out;
    }

    // Toggle a member. Runs at root scope; the ListView model is untouched,
    // so the clicked delegate survives and the whole handler completes.
    function toggleUser(userId) {
        var next = [];
        var wasSelected = false;
        for (var i = 0; i < root.selectedUserIds.length; i++) {
            var id = root.selectedUserIds[i];
            if (id === userId) { wasSelected = true; continue; }
            next.push(id);
        }
        if (!wasSelected) next.push(userId);
        root.selectedUserIds = next;

        var selected = root.selectedUsers();
        root.activeStyleMap = root.computeStyleMap(selected, root.accent, root.background);
        DataController.setActiveUsers(selected);
    }

    // Bar slot sizes itself from these (Bar.qml:1814) — keep them bound to
    // the button's implicit size so the bar item never collapses to 0×0.
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    // Load team.json from the plugin directory (works both installed under
    // ~/.config/omarchy/plugins/ and when run standalone)
    FileView {
        id: teamFile
        path: Qt.resolvedUrl("team.json").toString()
        watchChanges: true
        printErrors: false
        onLoaded: {
            try {
                var parsed = JSON.parse(text());
                // Stable model: raw user objects, no injected flags
                root.teamData = parsed.users;
                // Default selection: public calendars shown by default
                var sel = [];
                for (var i = 0; i < parsed.users.length; i++) {
                    if (parsed.users[i].public !== false) sel.push(parsed.users[i].id);
                }
                root.selectedUserIds = sel;
                root.activeStyleMap = root.computeStyleMap(root.selectedUsers(), root.accent, root.background);
                if (parsed.apiKey) DataController.setConfig({ apiKey: parsed.apiKey });
                if (parsed.refreshIntervalMinutes) {
                    DataController.setConfig({ refreshIntervalMinutes: parsed.refreshIntervalMinutes });
                    refreshTimer.interval = parsed.refreshIntervalMinutes * 60 * 1000;
                }
                DataController.setActiveUsers(root.selectedUsers());
            } catch (err) { console.error("Failed to parse team.json:", err); }
        }
    }

    // DataController callbacks
    Component.onCompleted: {
        DataController.onEventsChanged(function(newEvents) { root.events = newEvents; });
        DataController.onLoadingChanged(function(isLoading) { root.loading = isLoading; });
        DataController.onErrorChanged(function(err) { root.errorMessage = err || ""; });

        teamFile.reload();
    }

    // Auto-refresh timer (from team.json config)
    Timer {
        id: refreshTimer
        interval: 5 * 60 * 1000 // default 5 min, updated from team.json
        running: true
        repeat: true
        onTriggered: {
            if (!root.loading) {
                DataController.refresh();
            }
        }
    }

    // Bar button
    WidgetButton {
        id: button
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.barVertical ? parent.width : implicitWidth
        bar: root.bar
        text: "📅"
        tooltipText: "Team calendar"
        onPressed: function(buttonCode) { root.toggle() }
    }

    // Popup panel anchored to the bar button
    KeyboardPanel {
        id: panel
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        contentWidth: panel.fittedContentWidth(Style.space(960))
        contentHeight: panel.fittedContentHeight(Style.space(640))

        ColumnLayout {
            anchors.fill: parent
            spacing: 10

            // Header with week nav
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ToolButton {
                    text: "◀"
                    font.pixelSize: 14
                    onClicked: { root.weekOffset -= 1; DataController.setWeekOffset(root.weekOffset); }
                    enabled: !root.loading
                }

                Text {
                    Layout.fillWidth: true
                    text: root.weekLabel(root.weekOffset)
                    color: root.foreground
                    font.pixelSize: 14
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }

                ToolButton {
                    text: "▶"
                    font.pixelSize: 14
                    onClicked: { root.weekOffset += 1; DataController.setWeekOffset(root.weekOffset); }
                    enabled: !root.loading
                }
            }

            ToolButton {
                Layout.fillWidth: true
                text: root.loading ? "⟳ Loading..." : "⟳ Refresh"
                font.pixelSize: 11
                onClicked: DataController.refresh()
                enabled: !root.loading
            }

            // Error banner
            Rectangle {
                Layout.fillWidth: true
                visible: root.errorMessage !== ""
                height: 36
                color: Qt.rgba(0.9, 0.3, 0.3, 0.15)
                border.color: Qt.rgba(0.9, 0.3, 0.3, 0.5)
                border.width: 1
                radius: 4

                Text {
                    anchors.fill: parent
                    anchors.margins: 8
                    text: root.errorMessage
                    color: "#e06c75"
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                }
            }

            // Main content: sidebar + calendar
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                // Sidebar
                Rectangle {
                    Layout.preferredWidth: 240
                    Layout.fillHeight: true
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
                    radius: 6
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        Text { text: "Team Members"; color: root.foreground; font.pixelSize: 13; font.bold: true; Layout.fillWidth: true; }
                        Text { text: "Select members to view"; color: root.muted; font.pixelSize: 10; Layout.fillWidth: true; }
                        Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1); }

                        ListView {
                            id: userList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 3
                            model: root.teamData

                            delegate: Item {
                                id: rowDelegate
                                width: userList.width
                                height: 30
                                property var user: modelData
                                property bool isActive: root.selectedUserIds.indexOf(user.id) !== -1
                                property var userStyle: root.activeStyleMap[user.id] || null

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 5
                                    color: mouseArea.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.08) : "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 6
                                        anchors.rightMargin: 6
                                        spacing: 6

                                        Rectangle {
                                            width: 16
                                            height: 16
                                            radius: 3
                                            border.color: rowDelegate.isActive ? root.accent : root.muted
                                            border.width: 1.5
                                            clip: true

                                            PatternRect {
                                                anchors.fill: parent
                                                radius: 2
                                                visible: rowDelegate.isActive && rowDelegate.userStyle !== null
                                                backgroundColor: rowDelegate.userStyle ? rowDelegate.userStyle.backgroundColor : "transparent"
                                                stripeColor: rowDelegate.userStyle ? rowDelegate.userStyle.stripeColor : "transparent"
                                                pattern: rowDelegate.userStyle ? rowDelegate.userStyle.pattern : "solid"
                                                stripeSpacing: 3
                                                stripeWidth: 1.2
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                text: "✓"
                                                font.pixelSize: 9
                                                font.bold: true
                                                color: rowDelegate.userStyle ? rowDelegate.userStyle.textColor : root.accent
                                                visible: rowDelegate.isActive
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: rowDelegate.user.name
                                            color: rowDelegate.isActive ? root.foreground : root.muted
                                            font.pixelSize: 11
                                            font.bold: rowDelegate.isActive
                                            elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        id: mouseArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleUser(rowDelegate.user.id)
                                    }
                                }
                            }
                        }
                    }
                }

                // Calendar Grid
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.02)
                    radius: 6
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                    border.width: 1

                    CalendarGrid {
                        anchors.fill: parent
                        anchors.margins: 8
                        activeStyleMap: root.activeStyleMap
                        events: root.events
                        weekStart: root.weekStart
                        themeForeground: root.foreground
                        themeMuted: root.muted
                        themeAccent: root.accent
                        themeBg: root.background
                    }

                    // Loading overlay
                    Rectangle {
                        anchors.fill: parent
                        visible: root.loading && root.events.length === 0
                        color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.9)
                        radius: 6

                        Column {
                            anchors.centerIn: parent
                            spacing: 8

                            Text { text: "Loading calendars..."; color: root.foreground; font.pixelSize: 14; }
                            Text { text: "Fetching events from Google Calendar"; color: root.muted; font.pixelSize: 11; }
                        }
                    }
                }
            }
        }
    }
}
