// scripts/DataController.js
// Orchestrates data fetching, caching, refresh, and state management
// .pragma library

.pragma library
.import "CalendarService.js" as CalendarService
.import "EventNormalizer.js" as EventNormalizer
.import "EventLayout.js" as EventLayout
// Configuration defaults
const DEFAULT_REFRESH_INTERVAL_MS = 5 * 60 * 1000; // 5 minutes
const DEFAULT_WEEK_START = 0; // 0=Monday
const DEFAULT_TIME_RANGE = { startHour: 7, endHour: 18 };

// Internal state
var _config = {
    apiKey: "",
    refreshIntervalMs: DEFAULT_REFRESH_INTERVAL_MS,
    weekStartDay: DEFAULT_WEEK_START,
    timeRange: DEFAULT_TIME_RANGE
};

var _activeUsers = [];
var _currentWeekOffset = 0; // 0 = current week, 1 = next, -1 = prev
var _cachedEvents = [];
var _lastFetchTime = 0;
var _refreshTimer = null;
var _isLoading = false;
var _lastError = null;
var _requestId = 0;
var _pendingReload = false;

// Callbacks (set by UI)
var _onEventsChanged = null;
var _onLoadingChanged = null;
var _onErrorChanged = null;

function notifyEventsChanged() {
    if (_onEventsChanged) _onEventsChanged(_cachedEvents);
}

function notifyLoadingChanged(loading) {
    _isLoading = loading;
    if (_onLoadingChanged) _onLoadingChanged(loading);
}

function notifyErrorChanged(error) {
    _lastError = error;
    if (_onErrorChanged) _onErrorChanged(error);
}

// Set configuration (call once at startup)
function setConfig(config) {
    if (config.apiKey !== undefined) _config.apiKey = config.apiKey;
    if (config.refreshIntervalMinutes !== undefined) {
        _config.refreshIntervalMs = config.refreshIntervalMinutes * 60 * 1000;
    }
    if (config.weekStartDay !== undefined) _config.weekStartDay = config.weekStartDay;
    if (config.timeRange !== undefined) _config.timeRange = config.timeRange;
    restartRefreshTimer();
}

// Set active users (call when team.json loads or member toggled).
// `users` is the list of users to show, already filtered by the UI to the
// checked members (mirrors selectedUsers in the reference web app).
function setActiveUsers(users) {
    _activeUsers = users.slice();
    // Immediately drop cached events of newly-deselected users so the UI
    // hides them even before the refetch completes.
    _cachedEvents = _cachedEvents.filter(function(ev) {
        for (var i = 0; i < _activeUsers.length; i++) {
            if (_activeUsers[i].id === ev.userId) return true;
        }
        return false;
    });
    _lastFetchTime = 0;
    notifyEventsChanged();
    loadCurrentWeek();
}

// Set week offset (called by week navigation UI), triggers refetch
function setWeekOffset(offset) {
    var n = Number(offset);
    if (isNaN(n)) return;
    if (n === _currentWeekOffset) return;
    _currentWeekOffset = n;
    _cachedEvents = [];
    _lastFetchTime = 0;
    notifyEventsChanged();
    loadCurrentWeek();
}

// Get week start date for current offset
function getCurrentWeekStart() {
    var now = new Date();
    var day = now.getDay(); // 0=Sun
    var diffToMon = (day === 0 ? -6 : 1) - day;
    var monday = new Date(now);
    monday.setDate(now.getDate() + diffToMon + _currentWeekOffset * 7);
    monday.setHours(0, 0, 0, 0);
    return monday;
}

// Main load function
function loadCurrentWeek() {
    if (_isLoading) {
        // Don't swallow toggles/week-nav made mid-fetch: rerun when done.
        _pendingReload = true;
        return;
    }
    if (!_config.apiKey) {
        notifyErrorChanged("API key not configured");
        notifyEventsChanged();
        return;
    }
    if (_activeUsers.length === 0) {
        _cachedEvents = [];
        notifyEventsChanged();
        notifyErrorChanged(null);
        return;
    }

    var weekStart = getCurrentWeekStart();
    var usersSnapshot = _activeUsers.slice();
    var myRequestId = ++_requestId;
    _pendingReload = false;
    notifyLoadingChanged(true);
    notifyErrorChanged(null);

    CalendarService.fetchEventsForUsers(usersSnapshot, weekStart, _config.apiKey, function(success, rawResult, xhr) {
        if (myRequestId !== _requestId) return; // stale response, discard
        notifyLoadingChanged(false);
        if (!success) {
            notifyErrorChanged(rawResult); // rawResult is error message
            notifyEventsChanged();
        } else {
            var normalized = EventNormalizer.normalizeAll(rawResult, usersSnapshot);
            // Defensive: drop events whose user was deactivated mid-fetch
            var allowed = {};
            for (var i = 0; i < _activeUsers.length; i++) allowed[_activeUsers[i].id] = true;
            normalized = normalized.filter(function(ev) { return allowed[ev.userId]; });
            var withLayout = EventLayout.processEventsForLayout(normalized);
            _cachedEvents = withLayout;
            _lastFetchTime = Date.now();
            notifyEventsChanged();
            notifyErrorChanged(null);
        }
        if (_pendingReload) {
            _pendingReload = false;
            loadCurrentWeek();
        }
    });
}

// Force refresh (manual)
function refresh() {
    _cachedEvents = [];
    _lastFetchTime = 0;
    notifyEventsChanged();
    loadCurrentWeek();
}

// Auto-refresh timer (managed by UI layer via QML Timer)
function restartRefreshTimer() {
    // No-op: UI layer handles timer via QML Timer component
}

function stopRefreshTimer() {
    // No-op
}

// Callback registration
function onEventsChanged(callback) { _onEventsChanged = callback; }
function onLoadingChanged(callback) { _onLoadingChanged = callback; }
function onErrorChanged(callback) { _onErrorChanged = callback; }

// Getters for UI
function getEvents() { return _cachedEvents; }
function isLoading() { return _isLoading; }
function getError() { return _lastError; }
function getWeekOffset() { return _currentWeekOffset; }
function getWeekStart() { return getCurrentWeekStart(); }
function getActiveUsers() { return _activeUsers; }
function getConfig() { return _config; }

// Cleanup
function destroy() {
    stopRefreshTimer();
    _onEventsChanged = null;
    _onLoadingChanged = null;
    _onErrorChanged = null;
}

// Export