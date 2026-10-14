// scripts/DataController.js
// Orchestrates data fetching, caching, refresh, and state management
// .pragma library

.pragma library
.import "CalendarService.js" as CalendarService
.import "EventNormalizer.js" as EventNormalizer
.import "EventLayout.js" as EventLayout
.import "Network.js" as Network
// Configuration defaults
const DEFAULT_REFRESH_INTERVAL_MS = 5 * 60 * 1000; // 5 minutes
const DEFAULT_WEEK_START = 0; // 0=Mon .. 6=Sun
const DEFAULT_TIME_RANGE = { startHour: 7, endHour: 18 };
const MAX_RETRY_ATTEMPTS = 3;

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

// Retry state (exponential backoff for transient network errors).
// The UI drives the actual delay via a QML Timer — .pragma libraries can't
// create timers themselves.
var _retryAttempt = 0;
var _retryPending = false;
var _retryDelayMs = 0;

// Callbacks (set by UI)
var _onEventsChanged = null;
var _onLoadingChanged = null;
var _onErrorChanged = null;
var _onRetryStateChanged = null;

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

function notifyRetryStateChanged() {
    if (_onRetryStateChanged) _onRetryStateChanged(_retryPending, _retryDelayMs);
}

// Transient failures worth retrying: timeouts, network errors, 5xx/429
function isRetryableError(msg) {
    if (!msg) return false;
    return msg.indexOf("Network error") !== -1
        || msg.indexOf("timeout") !== -1
        || msg.indexOf("HTTP 5") !== -1
        || msg.indexOf("HTTP 429") !== -1;
}

function scheduleRetry() {
    if (_retryAttempt >= MAX_RETRY_ATTEMPTS) {
        _retryAttempt = 0; // give up; a later user action starts fresh
        return;
    }
    _retryAttempt++;
    _retryDelayMs = 1000 * Math.pow(2, _retryAttempt); // 2s, 4s, 8s
    _retryPending = true;
    notifyRetryStateChanged();
}

function cancelRetry() {
    if (!_retryPending && _retryAttempt === 0) return;
    _retryPending = false;
    _retryDelayMs = 0;
    _retryAttempt = 0;
    notifyRetryStateChanged();
}

// Called by the UI's retry Timer when the backoff delay elapsed
function retryNow() {
    cancelRetry();
    loadCurrentWeek();
}

// Set configuration (call once at startup, or again when team.json changes)
function setConfig(config) {
    if (config.apiKey !== undefined) _config.apiKey = config.apiKey;
    if (config.refreshIntervalMinutes !== undefined) {
        var mins = Number(config.refreshIntervalMinutes);
        if (isNaN(mins)) mins = DEFAULT_REFRESH_INTERVAL_MS / 60000;
        mins = Math.max(1, Math.min(60, mins)); // clamp 1–60 min: no hot-loop polling
        _config.refreshIntervalMs = mins * 60 * 1000;
    }
    if (config.weekStartDay !== undefined) {
        var wd = Math.round(Number(config.weekStartDay));
        _config.weekStartDay = (isNaN(wd) || wd < 0 || wd > 6) ? DEFAULT_WEEK_START : wd;
    }
    if (config.timeRange !== undefined && config.timeRange !== null) {
        var sh = Math.round(Number(config.timeRange.startHour));
        var eh = Math.round(Number(config.timeRange.endHour));
        if (isNaN(sh)) sh = DEFAULT_TIME_RANGE.startHour;
        if (isNaN(eh)) eh = DEFAULT_TIME_RANGE.endHour;
        sh = Math.max(0, Math.min(23, sh));
        eh = Math.max(sh + 1, Math.min(24, eh)); // at least one visible hour
        _config.timeRange = { startHour: sh, endHour: eh };
    }
    restartRefreshTimer();
}

// Set active users (call when team.json loads or member toggled).
// `users` is the list of users to show, already filtered by the UI to the
// checked members (mirrors selectedUsers in the reference web app).
function setActiveUsers(users) {
    cancelRetry();
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
    cancelRetry();
    _currentWeekOffset = n;
    _cachedEvents = [];
    _lastFetchTime = 0;
    notifyEventsChanged();
    loadCurrentWeek();
}

// Get week start date for current offset (honors configured weekStartDay)
function getCurrentWeekStart() {
    var now = new Date();
    var curDay = (now.getDay() + 6) % 7; // 0=Mon .. 6=Sun
    var target = _config.weekStartDay;
    var diff = (curDay - target + 7) % 7; // days elapsed since this week's start
    var start = new Date(now);
    start.setDate(now.getDate() - diff + _currentWeekOffset * 7);
    start.setHours(0, 0, 0, 0);
    return start;
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
            if (isRetryableError(rawResult)) scheduleRetry();
            else cancelRetry();
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
            cancelRetry();
            notifyErrorChanged(null);
        }
        if (_pendingReload) {
            _pendingReload = false;
            loadCurrentWeek();
        }
    });
}

// Force refresh (manual) — also drops the HTTP cache so it really refetches
function refresh() {
    cancelRetry();
    Network.clearCache();
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
function onRetryStateChanged(callback) { _onRetryStateChanged = callback; }

// Getters for UI
function getEvents() { return _cachedEvents; }
function isLoading() { return _isLoading; }
function getError() { return _lastError; }
function getWeekOffset() { return _currentWeekOffset; }
function getWeekStart() { return getCurrentWeekStart(); }
function getActiveUsers() { return _activeUsers; }
function getConfig() { return _config; }
function getLastFetchTime() { return _lastFetchTime; }
function isRetryPending() { return _retryPending; }
function getRetryDelayMs() { return _retryDelayMs; }

// Cleanup
function destroy() {
    stopRefreshTimer();
    _onEventsChanged = null;
    _onLoadingChanged = null;
    _onErrorChanged = null;
    _onRetryStateChanged = null;
}

// Export