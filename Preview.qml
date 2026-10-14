import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io

import "components"
import "scripts/DataController.js" as DataController

// Standalone test harness to run with `quickshell -p ./Preview.qml`
FloatingWindow {
    id: root

    title: "OmaTeamCal - Theme-Adaptive Prototype"
    visible: true
    implicitWidth: 1080
    implicitHeight: 700
    minimumSize: Qt.size(800, 500)
    color: themeBg

    // Theme values - dynamically loaded from Omarchy's active theme
    property color themeBg: "#121212"
    property color themeForeground: "#bebebe"
    property color themeAccent: "#e68e0d"
    property color themeMuted: "#555555"

    // Team roster loaded from team.json. This is the stable ListView model —
    // it is NEVER reassigned on toggle, so delegates are not destroyed while
    // their click handlers are still running.
    property var teamData: []
    // Selected member ids — single source of truth for the checkbox state
    // (mirrors selectedUserIds in the meeting-scheduler reference app).
    property var selectedUserIds: []
    property var activeStyleMap: ({})

    // Events from DataController (replaces sampleEvents)
    property var events: []

    // Loading / error state
    property bool loading: false
    property string errorMessage: ""
    property bool retryPending: false
    property int weekOffset: 0

    // Config from team.json (kept in sync with DataController's clamped values)
    property int weekStartDay: 0
    property int startHour: 7
    property int endHour: 18

    // File reader for active Omarchy theme colors.toml
    FileView {
        id: themeColorsFile
        path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
        watchChanges: true
        printErrors: false

        onLoaded: root.parseThemeColors(text())
        onFileChanged: reload()
    }

    // File watcher for theme switch
    FileView {
        id: themeNameFile
        path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
        watchChanges: true
        printErrors: false

        onFileChanged: {
            reload();
            themeColorsFile.reload();
        }
    }

    // File reader for team.json
    FileView {
        id: teamFile
        path: Quickshell.shellDir + "/team.json"
        watchChanges: true
        onLoaded: {
            try {
                var parsed = JSON.parse(text());
                if (parsed && Array.isArray(parsed.users)) {
                    // Stable model: raw user objects, no injected flags
                    root.teamData = parsed.users;
                    // Default selection: public calendars shown by default
                    var sel = [];
                    for (var i = 0; i < parsed.users.length; i++) {
                        if (parsed.users[i].public !== false) sel.push(parsed.users[i].id);
                    }
                    root.selectedUserIds = sel;
                    root.activeStyleMap = root.computeStyleMap(root.selectedUsers(), root.themeAccent, root.themeBg);
                    // Pass config to DataController (single call), then read
                    // back the clamped values so UI and controller agree
                    var cfg = {};
                    if (parsed.apiKey) cfg.apiKey = parsed.apiKey;
                    if (parsed.refreshIntervalMinutes) {
                        var mins = Number(parsed.refreshIntervalMinutes);
                        if (!isNaN(mins)) {
                            mins = Math.max(1, Math.min(60, mins)); // clamp 1–60 min
                            cfg.refreshIntervalMinutes = mins;
                            refreshTimer.interval = mins * 60 * 1000;
                        }
                    }
                    if (parsed.weekStart !== undefined) cfg.weekStartDay = parsed.weekStart;
                    if (parsed.timeRange) cfg.timeRange = parsed.timeRange;
                    DataController.setConfig(cfg);
                    var cc = DataController.getConfig();
                    root.weekStartDay = cc.weekStartDay;
                    root.startHour = cc.timeRange.startHour;
                    root.endHour = cc.timeRange.endHour;
                    // Set active users in DataController
                    DataController.setActiveUsers(root.selectedUsers());
                }
            } catch (err) {
                console.error("Failed to parse team.json:", err);
            }
        }
    }

    // ── Color / style engine (inlined to avoid Quickshell VFS JS-import restriction) ──

    function parseHex(h) {
        var s = String(h || "#000000").replace("#", "");
        if (s.length === 3) s = s[0]+s[0]+s[1]+s[1]+s[2]+s[2];
        return {
            r: parseInt(s.substring(0, 2), 16) / 255.0,
            g: parseInt(s.substring(2, 4), 16) / 255.0,
            b: parseInt(s.substring(4, 6), 16) / 255.0
        };
    }

    function toRGB(c) {
        if (typeof c === "string") return parseHex(c);
        if (c && typeof c.r === "number") return { r: c.r, g: c.g, b: c.b };
        return { r: 0, g: 0, b: 0 };
    }

    function lerpColor(c1, c2, t) {
        var a = toRGB(c1), b = toRGB(c2);
        return Qt.rgba(
            a.r + (b.r - a.r) * t,
            a.g + (b.g - a.g) * t,
            a.b + (b.b - a.b) * t,
            1.0
        );
    }

    readonly property var _tintLevels:   [0.18, 0.38, 0.62, 0.88]
    readonly property var _patternNames: ["solid", "stripe-45", "stripe-135", "dots", "crosshatch"]
    readonly property var _slots: [
        {tint:3,pattern:0},{tint:0,pattern:1},{tint:2,pattern:2},{tint:1,pattern:3},
        {tint:3,pattern:4},{tint:0,pattern:0},{tint:2,pattern:1},{tint:1,pattern:2},
        {tint:3,pattern:3},{tint:0,pattern:4},{tint:2,pattern:0},{tint:1,pattern:0},
        {tint:0,pattern:2},{tint:0,pattern:3},{tint:1,pattern:1},{tint:1,pattern:4},
        {tint:2,pattern:3},{tint:2,pattern:4},{tint:3,pattern:1},{tint:3,pattern:2}
    ]

    function buildStyle(tintIdx, patternIdx, accent, bg) {
        var factor  = _tintLevels[Math.max(0, Math.min(3, tintIdx))];
        var pattern = _patternNames[Math.max(0, Math.min(4, patternIdx))];
        var baseBg  = lerpColor(bg, accent, factor);
        var stripeColor = factor > 0.5
            ? lerpColor(baseBg, bg, 0.28)
            : lerpColor(baseBg, accent, 0.40);
        var bgRGB = toRGB(baseBg);
        var luminance = 0.299*bgRGB.r + 0.587*bgRGB.g + 0.114*bgRGB.b;
        var textColor = luminance > 0.45
            ? Qt.rgba(0.05, 0.05, 0.05, 1.0)
            : Qt.rgba(0.94, 0.94, 0.94, 1.0);
        var borderColor = lerpColor(accent, Qt.rgba(1,1,1,1), 0.15);
        return { tintFactor: factor, pattern: pattern,
                 backgroundColor: baseBg, stripeColor: stripeColor,
                 borderColor: borderColor, textColor: textColor };
    }

    // Pure: takes the already-selected user list, no id references, so it is
    // safe to call from any scope.
    function computeStyleMap(users, accent, bg) {
        var map = {};
        for (var j = 0; j < users.length; j++) {
            var slot = _slots[j % _slots.length];
            map[users[j].id] = buildStyle(slot.tint, slot.pattern, accent, bg);
        }
        console.log("computeStyleMap: selected=", users.length, "map keys=", Object.keys(map).join(","));
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
    // (The old flow reassigned teamData here, which reset the ListView,
    // destroyed the delegate mid-handler, and left a ReferenceError before
    // the style map / data refetch could run — events never disappeared.)
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
        root.activeStyleMap = root.computeStyleMap(selected, root.themeAccent, root.themeBg);
        DataController.setActiveUsers(selected);
        console.log("TOGGLE user=" + userId + " nowSelected=" + selected.length);
    }

    function parseThemeColors(content) {
        if (!content) return;
        var lines = String(content).split("\n");
        for (var i = 0; i < lines.length; i++) {
            var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/);
            if (!match) continue;
            var key = match[1];
            var val = match[2];

            if (key === "background") root.themeBg = val;
            else if (key === "foreground") root.themeForeground = val;
            else if (key === "accent") root.themeAccent = val;
            else if (key === "muted") root.themeMuted = val;
        }
        root.activeStyleMap = root.computeStyleMap(root.selectedUsers(), root.themeAccent, root.themeBg);
    }

    // Week start 00:00 of the displayed week (honors configured weekStartDay)
    function weekStartDate(offset) {
        var d = new Date();
        var curDay = (d.getDay() + 6) % 7; // 0=Mon .. 6=Sun
        var diff = (curDay - root.weekStartDay + 7) % 7; // days since week start
        var start = new Date(d);
        start.setDate(d.getDate() - diff + offset * 7);
        start.setHours(0, 0, 0, 0);
        return start;
    }
    readonly property var weekStart: weekStartDate(weekOffset)

    // Week label helper
    function weekLabel(offset) {
        var monday = weekStartDate(offset);
        var sunday = new Date(monday);
        sunday.setDate(monday.getDate() + 6);
        var monthNames = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
        return monthNames[monday.getMonth()] + " " + monday.getDate() + " - " + monthNames[sunday.getMonth()] + " " + sunday.getDate();
    }

    // DataController callbacks
    Component.onCompleted: {
        DataController.onEventsChanged(function(newEvents) {
            root.events = newEvents;
        });
        DataController.onLoadingChanged(function(isLoading) {
            root.loading = isLoading;
        });
        DataController.onErrorChanged(function(err) {
            root.errorMessage = err || "";
        });
        DataController.onRetryStateChanged(function(pending, delay) {
            if (pending) retryTimer.interval = Math.max(500, delay);
            root.retryPending = pending;
        });

        if (root.teamData.length === 0) {
            teamFile.reload();
        }
        themeColorsFile.reload();
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

    // Backoff retry timer — interval set by DataController's retry callback
    Timer {
        id: retryTimer
        running: root.retryPending
        repeat: false
        onTriggered: DataController.retryNow()
    }

    // Main UI Layout
    RowLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 16

        // Left sidebar for filtering
        Rectangle {
            Layout.preferredWidth: 260
            Layout.fillHeight: true
            color: Qt.rgba(root.themeForeground.r, root.themeForeground.g, root.themeForeground.b, 0.03)
            radius: 8
            border.color: Qt.rgba(root.themeForeground.r, root.themeForeground.g, root.themeForeground.b, 0.08)
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                // Header with week navigation
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ToolButton {
                        text: "◀"
                        font.pixelSize: 14
                        onClicked: {
                            root.weekOffset -= 1;
                            DataController.setWeekOffset(root.weekOffset);
                        }
                        enabled: !root.loading
                    }

                    Text {
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: weekLabel(root.weekOffset)
                        color: root.themeForeground
                        font.pixelSize: 13
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }

                    ToolButton {
                        text: "▶"
                        font.pixelSize: 14
                        onClicked: {
                            root.weekOffset += 1;
                            DataController.setWeekOffset(root.weekOffset);
                        }
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

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.rgba(root.themeForeground.r, root.themeForeground.g, root.themeForeground.b, 0.12)
                }

                // Error banner — only when there is no data to fall back on
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.errorMessage !== "" && root.events.length === 0
                    height: 40
                    color: Qt.rgba(0.9, 0.3, 0.3, 0.15)
                    border.color: Qt.rgba(0.9, 0.3, 0.3, 0.5)
                    border.width: 1
                    radius: 4

                    Text {
                        anchors.fill: parent
                        anchors.margins: 8
                        textFormat: Text.PlainText
                        text: root.errorMessage + (root.retryPending ? "\nRetrying…" : "")
                        color: "#e06c75"
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                    }
                }

                // Offline/stale badge — subtle: we still have data to show
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.errorMessage !== "" && root.events.length > 0
                    height: offlineText.implicitHeight + 12
                    color: Qt.rgba(0.9, 0.6, 0.2, 0.12)
                    border.color: Qt.rgba(0.9, 0.6, 0.2, 0.45)
                    border.width: 1
                    radius: 4

                    Text {
                        id: offlineText
                        anchors.fill: parent
                        anchors.margins: 6
                        textFormat: Text.PlainText
                        text: "⚠ Showing saved data"
                            + (DataController.getLastFetchTime() > 0
                                ? " · updated " + Qt.formatTime(new Date(DataController.getLastFetchTime()), "HH:mm")
                                : "")
                            + (root.retryPending ? " · retrying…" : "")
                        color: "#e5a046"
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                    }
                }

                // Member filter list
                ListView {
                    id: userList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    model: root.teamData

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
                                    textFormat: Text.PlainText
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
                                onClicked: root.toggleUser(rowDelegate.user.id)
                            }
                        }
                    }
                }
            }
        }

        // Right calendar grid area
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Qt.rgba(root.themeForeground.r, root.themeForeground.g, root.themeForeground.b, 0.02)
            radius: 8
            border.color: Qt.rgba(root.themeForeground.r, root.themeForeground.g, root.themeForeground.b, 0.08)
            border.width: 1

            CalendarGrid {
                anchors.fill: parent
                anchors.margins: 10
                activeStyleMap: root.activeStyleMap
                events: root.events
                weekStart: root.weekStart
                weekStartDay: root.weekStartDay
                startHour: root.startHour
                endHour: root.endHour
                themeForeground: root.themeForeground
                themeMuted: root.themeMuted
                themeAccent: root.themeAccent
                themeBg: root.themeBg
            }

            // Empty state — no fetch in flight and nothing to show
            Rectangle {
                anchors.fill: parent
                visible: !root.loading && root.errorMessage === ""
                    && root.events.length === 0 && root.teamData.length > 0
                color: Qt.rgba(root.themeBg.r, root.themeBg.g, root.themeBg.b, 0.85)
                radius: 8

                Column {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.selectedUserIds.length === 0
                            ? "No active members"
                            : "No events this week"
                        color: root.themeForeground
                        font.pixelSize: 16
                        font.bold: true
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.selectedUserIds.length === 0
                        text: "Tick members in the sidebar to show their events"
                        color: root.themeMuted
                        font.pixelSize: 12
                    }
                }
            }

            // Loading overlay
            Rectangle {
                anchors.fill: parent
                visible: root.loading && root.events.length === 0
                color: Qt.rgba(root.themeBg.r, root.themeBg.g, root.themeBg.b, 0.85)
                radius: 8

                Column {
                    anchors.centerIn: parent
                    spacing: 12

                    Text {
                        text: "Loading calendars..."
                        color: root.themeForeground
                        font.pixelSize: 16
                    }

                    Text {
                        text: "Fetching events from Google Calendar"
                        color: root.themeMuted
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}