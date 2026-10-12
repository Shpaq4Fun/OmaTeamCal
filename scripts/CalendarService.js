// scripts/CalendarService.js
// Google Calendar API integration for public calendars (API key auth)
// .pragma library

.pragma library
.import "Network.js" as Network

const CALENDAR_API_BASE = "https://www.googleapis.com/calendar/v3";

// Compute Monday 00:00 and next Monday 00:00 for a given date (local timezone)
function getWeekRange(date) {
    var d = new Date(date);
    d.setHours(0, 0, 0, 0);
    var day = d.getDay(); // 0=Sun, 1=Mon...
    var diffToMon = (day === 0 ? -6 : 1) - day; // days to add to get to Monday
    var monday = new Date(d);
    monday.setDate(d.getDate() + diffToMon);
    var nextMonday = new Date(monday);
    nextMonday.setDate(monday.getDate() + 7);
    return {
        timeMin: monday.toISOString(),
        timeMax: nextMonday.toISOString(),
        weekStart: monday
    };
}

function buildEventsListUrl(calendarId, timeMin, timeMax, apiKey) {
    var encodedCalId = encodeURIComponent(calendarId);
    return CALENDAR_API_BASE + "/calendars/" + encodedCalId + "/events" +
        "?key=" + encodeURIComponent(apiKey) +
        "&timeMin=" + encodeURIComponent(timeMin) +
        "&timeMax=" + encodeURIComponent(timeMax) +
        "&singleEvents=true" +
        "&orderBy=startTime" +
        "&maxResults=100" +
        "&showDeleted=false";
}

function buildFreeBusyUrl(apiKey) {
    return CALENDAR_API_BASE + "/freeBusy?key=" + encodeURIComponent(apiKey);
}

function fetchEventsForCalendar(calendarId, timeMin, timeMax, apiKey, callback) {
    var url = buildEventsListUrl(calendarId, timeMin, timeMax, apiKey);
    Network.fetchJson(url, function(success, data, xhr) {
        if (!success) {
            callback(false, "Calendar " + calendarId + ": " + data, null);
            return;
        }
        callback(true, data.items || [], null);
    });
}

function fetchFreeBusy(calendarIds, timeMin, timeMax, apiKey, callback) {
    var url = buildFreeBusyUrl(apiKey);
    var items = calendarIds.map(function(id) { return { id: id }; });
    var body = {
        timeMin: timeMin,
        timeMax: timeMax,
        items: items
    };
    Network.fetchJsonPost(url, body, function(success, data, xhr) {
        if (!success) {
            callback(false, "FreeBusy: " + data, null);
            return;
        }
        callback(true, data.calendars || {}, null);
    });
}

// Main entry: fetch events for all active users
// activeUsers: array of user objects from team.json (with calendarId array, id, name)
// weekStartDate: Date object (any day in the target week)
// apiKey: string
// callback(success, result) where result = { events: [...], freeBusy: {...}, weekStart: Date }
function fetchEventsForUsers(activeUsers, weekStartDate, apiKey, callback) {
    var range = getWeekRange(weekStartDate);
    var timeMin = range.timeMin;
    var timeMax = range.timeMax;
    var weekStart = range.weekStart;

    // Collect all calendar IDs with user mapping
    var allCalendarIds = [];
    var calIdToUser = {};
    for (var i = 0; i < activeUsers.length; i++) {
        var user = activeUsers[i];
        for (var j = 0; j < user.calendarId.length; j++) {
            var calId = user.calendarId[j];
            allCalendarIds.push(calId);
            calIdToUser[calId] = user;
        }
    }
    if (allCalendarIds.length === 0) {
        callback(true, { events: [], freeBusy: {}, weekStart: weekStart });
        return;
    }
    var allEvents = [];
    var hadError = false;
    var errorMsg = "";
    var pending = allCalendarIds.length;

    function checkDone() {
        pending--;
        if (pending === 0 && !hadError) {
            // Fetch FreeBusy after all events.list calls
            fetchFreeBusy(allCalendarIds, timeMin, timeMax, apiKey, function(fbSuccess, fbData, fbXhr) {
                if (!fbSuccess) {
                    // Don't fail the whole request, just proceed without freebusy
                    callback(true, { events: allEvents, freeBusy: {}, weekStart: weekStart });
                } else {
                    callback(true, { events: allEvents, freeBusy: fbData, weekStart: weekStart });
                }
            });
        }
    }

    for (var k = 0; k < allCalendarIds.length; k++) {
        (function(calId) {
            var user = calIdToUser[calId];
            fetchEventsForCalendar(calId, timeMin, timeMax, apiKey, function(success, events, xhr) {
                if (hadError) return;
                if (!success) {
                    hadError = true;
                    errorMsg = events; // events is error message here
                    callback(false, errorMsg, null);
                    return;
                }
                for (var e = 0; e < events.length; e++) {
                    var ev = events[e];
                    if (!ev.id || !ev.summary) continue;
                    allEvents.push({
                        raw: ev,
                        userId: user.id,
                        userName: user.name,
                        calendarId: calId
                    });
                }
                checkDone();
            });
        })(allCalendarIds[k]);
    }
}

// Export