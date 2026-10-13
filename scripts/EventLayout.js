// scripts/EventLayout.js
// Computes overlapping event layout (column assignment + widths)
// .pragma library

.pragma library

// Process timed events for overlapping layout
// events: array of UI events with {dayIndex, startHour, startMinute, durationMinutes, ...}
// returns events with added layout: {col, totalCols, leftPercent, widthPercent}
function processTimedEventsForLayout(events) {
    if (!events || events.length === 0) return [];

    // Group events by day
    var eventsByDay = {};
    for (var i = 0; i < events.length; i++) {
        var ev = events[i];
        var day = ev.dayIndex;
        if (!eventsByDay[day]) eventsByDay[day] = [];
        eventsByDay[day].push(ev);
    }

    // Process each day independently
    var result = [];
    for (var day = 0; day <= 6; day++) {
        var dayEvents = eventsByDay[day] || [];
        if (dayEvents.length === 0) continue;

        var processed = processDayEvents(dayEvents);
        result = result.concat(processed);
    }

    return result;
}

function processDayEvents(events) {
    // Convert to minutes from week start for easier comparison
    var timedEvents = events.map(function(ev) {
        var startMinutes = ev.startHour * 60 + ev.startMinute;
        var endMinutes = startMinutes + ev.durationMinutes;
        return {
            event: ev,
            startMinutes: startMinutes,
            endMinutes: endMinutes
        };
    });

    // Sort by start time, then by duration (longer first)
    timedEvents.sort(function(a, b) {
        if (a.startMinutes !== b.startMinutes) return a.startMinutes - b.startMinutes;
        return b.endMinutes - a.endMinutes;
    });

    var layoutInfo = [];

    for (var i = 0; i < timedEvents.length; i++) {
        var ev = timedEvents[i];

        // Find overlapping events already placed
        var overlapping = [];
        for (var j = 0; j < layoutInfo.length; j++) {
            var placed = layoutInfo[j];
            if (placed.endMinutes > ev.startMinutes && placed.startMinutes < ev.endMinutes) {
                overlapping.push(placed);
            }
        }

        // Find first free column
        var usedCols = {};
        for (var k = 0; k < overlapping.length; k++) {
            usedCols[overlapping[k].col] = true;
        }

        var currentCol = 0;
        while (usedCols[currentCol]) {
            currentCol++;
        }

        var newEntry = {
            event: ev.event,
            startMinutes: ev.startMinutes,
            endMinutes: ev.endMinutes,
            col: currentCol,
            totalCols: 1
        };
        layoutInfo.push(newEntry);

        // Update totalCols for all involved events
        var allInvolved = overlapping.concat([newEntry]);
        var maxCols = 0;
        for (var m = 0; m < allInvolved.length; m++) {
            if (allInvolved[m].col + 1 > maxCols) maxCols = allInvolved[m].col + 1;
        }
        for (var n = 0; n < allInvolved.length; n++) {
            if (allInvolved[n].totalCols < maxCols) allInvolved[n].totalCols = maxCols;
        }
    }

    // Convert to output format with percentages
    var output = [];
    for (var p = 0; p < layoutInfo.length; p++) {
        var li = layoutInfo[p];
        var ev = li.event;
        var leftPercent = (100 / li.totalCols) * li.col;
        var widthPercent = 100 / li.totalCols;

        // Create new event object with layout info
        var newEvent = {};
        for (var key in ev) {
            if (ev.hasOwnProperty(key)) newEvent[key] = ev[key];
        }
        newEvent.layout = {
            col: li.col,
            totalCols: li.totalCols,
            leftPercent: leftPercent,
            widthPercent: widthPercent
        };
        output.push(newEvent);
    }

    return output;
}

// Main entry: timed events get column/width layout for the hour grid;
// all-day events are returned unchanged — the grid packs them into the
// all-day band itself (CalendarGrid.allDayRender), where the visible-day
// count lives.
function processEventsForLayout(events) {
    var timed = [];
    var allDay = [];
    for (var i = 0; i < events.length; i++) {
        if (events[i].isAllDay) allDay.push(events[i]);
        else timed.push(events[i]);
    }
    return processTimedEventsForLayout(timed).concat(allDay);
}