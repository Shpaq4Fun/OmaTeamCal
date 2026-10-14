// scripts/EventNormalizer.js
// Convert raw Google Calendar API events → UI event shape
// .pragma library

.pragma library

// Normalize a single raw event to UI shape
// rawEvent: { raw: {...}, userId, userName, calendarId }
// weekStart: Date (Monday 00:00 local)
function normalizeEvent(rawEvent, weekStart) {
    var ev = rawEvent.raw;
    var userId = rawEvent.userId;
    var userName = rawEvent.userName;

    if (!ev.id || !ev.summary) return null;

    // Parse start/end - handle both dateTime (RFC3339) and date (all-day)
    var isAllDay = !ev.start.dateTime && ev.start.date;
    var startDate, endDate;

    if (isAllDay) {
        startDate = new Date(ev.start.date + "T00:00:00");
        // All-day events in Google Calendar have end.date = day AFTER last day
        if (ev.end.date) {
            var endDateObj = new Date(ev.end.date);
            endDateObj.setDate(endDateObj.getDate() - 1); // inclusive last day
            endDate = new Date(endDateObj);
            endDate.setHours(23, 59, 59, 999);
        } else {
            endDate = new Date(startDate);
            endDate.setHours(23, 59, 59, 999);
        }
    } else {
        startDate = new Date(ev.start.dateTime);
        endDate = new Date(ev.end.dateTime);
    }

    // Filter: event must intersect with the week (Mon-Sun)
    var weekEnd = new Date(weekStart);
    weekEnd.setDate(weekStart.getDate() + 7);
    weekEnd.setHours(23, 59, 59, 999);

    if (endDate < weekStart || startDate > weekEnd) {
        return null; // outside week
    }

    // Clamp to week boundaries for display
    var displayStart = startDate < weekStart ? weekStart : startDate;
    var displayEnd = endDate > weekEnd ? weekEnd : endDate;

    // Compute dayIndex (0=Mon, 6=Sun) based on displayStart
    var dayIndex = Math.floor((displayStart.getTime() - weekStart.getTime()) / (24 * 60 * 60 * 1000));
    dayIndex = Math.max(0, Math.min(6, dayIndex));

    // Inclusive day span within the week — all-day events may cover several
    // consecutive days (Google's end.date is exclusive, already handled above)
    var dayMs = 24 * 60 * 60 * 1000;
    var spanStartDay = Math.floor((displayStart.getTime() - weekStart.getTime()) / dayMs);
    var spanEndDay = Math.floor((displayEnd.getTime() - weekStart.getTime()) / dayMs);
    spanStartDay = Math.max(0, Math.min(6, spanStartDay));
    spanEndDay = Math.max(spanStartDay, Math.min(6, spanEndDay));

    // Start hour/minute in local time
    var startHour = displayStart.getHours();
    var startMinute = displayStart.getMinutes();

    // Duration in minutes
    var durationMs = displayEnd.getTime() - displayStart.getTime();
    var durationMinutes = Math.round(durationMs / 60000);

    // Label: "HH:MM - HH:MM" for timed events, "All day" or a day range for
    // all-day events
    var timeLabel;
    if (isAllDay) {
        timeLabel = spanEndDay > spanStartDay
            ? dayLabel(weekStart, spanStartDay) + " - " + dayLabel(weekStart, spanEndDay)
            : "All day";
    } else {
        var endHour = displayEnd.getHours();
        var endMinute = displayEnd.getMinutes();
        timeLabel = pad2(startHour) + ":" + pad2(startMinute) + " - " + pad2(endHour) + ":" + pad2(endMinute);
    }

    return {
        id: ev.id,
        userId: userId,
        title: ev.summary,
        dayIndex: dayIndex,
        spanStartDay: spanStartDay,
        spanEndDay: spanEndDay,
        startHour: startHour,
        startMinute: startMinute,
        durationMinutes: durationMinutes,
        timeLabel: timeLabel,
        userName: userName,
        description: cleanDescription(ev.description),
        location: ev.location || "",
        isAllDay: isAllDay
    };
}

var EN_SHORT_DAYS = ["SUN.", "MON.", "TUE.", "WED.", "THU.", "FRI.", "SAT."];

// "TUE. 13" — label for dayIndex days after weekStart
function dayLabel(weekStart, dayIndex) {
    var d = new Date(weekStart);
    d.setDate(d.getDate() + dayIndex);
    return EN_SHORT_DAYS[d.getDay()] + " " + d.getDate();
}

function pad2(n) {
    return n < 10 ? "0" + n : String(n);
}

// Tooltip shows room/building only: strip URLs (e.g. USOS links) from
// Google Calendar descriptions, collapse leftover blank lines.
function cleanDescription(s) {
    if (!s) return "";
    var out = String(s).replace(/https?:\/\/\S+/g, "");
    out = out.replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").replace(/^\s+|\s+$/g, "");
    return out;
}

// Normalize freebusy busy blocks
function normalizeFreeBusy(freeBusyData, calIdToUser, weekStart) {
    var normalized = [];
    var weekEnd = new Date(weekStart);
    weekEnd.setDate(weekStart.getDate() + 7);
    weekEnd.setHours(23, 59, 59, 999);

    for (var calId in freeBusyData) {
        if (!freeBusyData.hasOwnProperty(calId)) continue;
        var calInfo = freeBusyData[calId];
        var user = calIdToUser[calId];
        if (!user) continue;

        var busyBlocks = calInfo.busy;
        if (!busyBlocks || !busyBlocks.length) continue;

        for (var i = 0; i < busyBlocks.length; i++) {
            var block = busyBlocks[i];
            var start = new Date(block.start);
            var end = new Date(block.end);

            // Filter to week
            if (end < weekStart || start > weekEnd) continue;

            var displayStart = start < weekStart ? weekStart : start;
            var displayEnd = end > weekEnd ? weekEnd : end;

            var dayIndex = Math.floor((displayStart.getTime() - weekStart.getTime()) / (24 * 60 * 60 * 1000));
            dayIndex = Math.max(0, Math.min(6, dayIndex));

            var startHour = displayStart.getHours();
            var startMinute = displayStart.getMinutes();
            var durationMinutes = Math.round((displayEnd.getTime() - displayStart.getTime()) / 60000);
            var endHour = displayEnd.getHours();
            var endMinute = displayEnd.getMinutes();
            var timeLabel = pad2(startHour) + ":" + pad2(startMinute) + " - " + pad2(endHour) + ":" + pad2(endMinute);

            normalized.push({
                id: "freebusy-" + calId + "-" + i,
                userId: user.id,
                title: "BUSY",
                dayIndex: dayIndex,
                spanStartDay: dayIndex,
                spanEndDay: dayIndex,
                startHour: startHour,
                startMinute: startMinute,
                durationMinutes: durationMinutes,
                timeLabel: timeLabel,
                userName: user.name,
                description: "",
                location: "",
                isAllDay: false
            });
        }
    }
    return normalized;
}

// Main entry: normalize all events + freebusy, merge, deduplicate
// rawResult: { events: [...], freeBusy: {...}, weekStart: Date }
// activeUsers: array of user objects (for calIdToUser mapping)
function normalizeAll(rawResult, activeUsers) {
    var weekStart = rawResult.weekStart;
    var allowedIds = {};
    var calIdToUser = {};
    for (var i = 0; i < activeUsers.length; i++) {
        var user = activeUsers[i];
        allowedIds[user.id] = true;
        for (var j = 0; j < user.calendarId.length; j++) {
            calIdToUser[user.calendarId[j]] = user;
        }
    }

    var normalized = [];

    // Normalize events.list events (re-validate userId: drop stale users)
    for (var k = 0; k < rawResult.events.length; k++) {
        if (!allowedIds[rawResult.events[k].userId]) continue;
        var norm = normalizeEvent(rawResult.events[k], weekStart);
        if (norm) normalized.push(norm);
    }

    // Normalize freebusy blocks
    var fbNorm = normalizeFreeBusy(rawResult.freeBusy, calIdToUser, weekStart);
    normalized = normalized.concat(fbNorm);

    // Deduplicate: freebusy blocks that overlap with real events for same user
    var deduped = [];
    for (var m = 0; m < normalized.length; m++) {
        var ev = normalized[m];
        var isDup = false;
        if (ev.title === "BUSY") {
            for (var n = 0; n < normalized.length; n++) {
                var other = normalized[n];
                if (other.title !== "BUSY" && other.userId === ev.userId) {
                    var evStart = ev.startHour * 60 + ev.startMinute;
                    var evEnd = evStart + ev.durationMinutes;
                    var otherStart = other.startHour * 60 + other.startMinute;
                    var otherEnd = otherStart + other.durationMinutes;
                    if (ev.dayIndex === other.dayIndex && otherStart <= evStart && otherEnd >= evEnd) {
                        isDup = true;
                        break;
                    }
                }
            }
        }
        if (!isDup) deduped.push(ev);
    }

    // Sort by dayIndex, then startHour, then startMinute
    deduped.sort(function (a, b) {
        if (a.dayIndex !== b.dayIndex) return a.dayIndex - b.dayIndex;
        var aMin = a.startHour * 60 + a.startMinute;
        var bMin = b.startHour * 60 + b.startMinute;
        return aMin - bMin;
    });

    return deduped;
}

// Export
