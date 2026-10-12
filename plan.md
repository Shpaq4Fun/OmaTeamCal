# OmaTeamCal Implementation Plan

## Phase 1: Network & API Layer (Data Fetching) ✅ COMPLETE

### 1.1 `scripts/Network.js` — HTTP Utility
- `.pragma library` module
- `fetchJson(url, callback)` — GET, JSON parse, error handling
- `fetchJsonPost(url, body, callback)` — POST for FreeBusy query
- Timeout handling, user-agent header
- In-memory cache with TTL (`fetchJsonCached` — **implemented but not wired up yet**)

### 1.2 `scripts/CalendarService.js` — Google Calendar API
- `.pragma library`, imports `Network.js`
- `fetchEventsForUsers(activeUsers, weekStartDate, apiKey, callback)`
  - Compute `timeMin`/`timeMax` (Monday 00:00 → next Monday 00:00 UTC)
  - Parallel `events.list` per calendarId
  - `freebusy.query` for busy blocks not covered by events
  - Returns normalized event array
- `buildEventsListUrl(calendarId, timeMin, timeMax, apiKey)`
- `buildFreeBusyUrl(apiKey)`

### 1.3 `scripts/EventNormalizer.js` — API → UI Shape
- `.pragma library`
- `normalizeEvents(rawEvents, activeUsers, weekStartDate)` → UI event array
- Each event: `{id, userId, title, dayIndex, startHour, startMinute, durationMinutes, timeLabel, userName}`
- Handles all-day events, multi-day events, timezone normalization
- Filters to week range (Mon–Sun)
- Deduplicates FreeBusy blocks overlapping real events

### 1.4 `scripts/DataController.js` — Orchestration
- `.pragma library`, imports `CalendarService`, `EventNormalizer`
- `setConfig(config)` — apiKey, refreshIntervalMinutes
- `setActiveUsers(users)` — **takes the already-filtered selection** (mirrors
  `selectedUsers` in the meeting-scheduler reference app), purges cached events
  of deselected users immediately, triggers refetch
- `setWeekOffset(offset)` — navigation, triggers refetch
- `refresh()` — manual refresh
- Callbacks: `onEventsChanged`, `onLoadingChanged`, `onErrorChanged`
- Mid-fetch toggles handled via `_pendingReload` rerun

---

## Phase 2: UI Integration ✅ COMPLETE (verified)

### 2.1 `Preview.qml` ✅ DONE
- Integrated `DataController.js`
- Loading overlay, error banner
- Week navigation (◀/▶), Refresh button
- Theme-aware via `FileView` watchers on Omarchy `colors.toml` / `theme.name`

### 2.2 Member toggle architecture ✅ FIXED (2026-10-13)
- **Bug:** events did not disappear when unchecking a member. The click handler
  reassigned `teamData` (the ListView model) mid-handler → ListView reset →
  the clicked delegate was destroyed → `ReferenceError: root is not defined` →
  style map never recomputed and `setActiveUsers` never called.
- **Fix (mirrors meeting-scheduler reference app):**
  - `teamData` = stable ListView model (raw team.json users, never reassigned
    on toggle — delegates survive their handlers)
  - `selectedUserIds` = root-level array, single source of truth for checkboxes
  - delegate `onClicked: root.toggleUser(id)`; root-level `toggleUser()` flips
    the id list, recomputes `activeStyleMap`, calls `setActiveUsers(selected)`
  - `CalendarGrid` keeps `visible: userStyle !== null` as belt-and-suspenders
- Same fix applied to `Panel.qml`; `components/MemberFilter.qml` aligned
- Regression harness: `_Bisect.qml` (headless driver, prints PASS/FAIL) —
  run with `quickshell -p ./_Bisect.qml`; delete when no longer needed

### 2.3 `Panel.qml` ✅ FIXED
- Pre-existing stray brace in `teamFile.onLoaded` made the file **fail to load
  entirely** — fixed
- Uses `PopupWindow` as root (Omarchy-compatible), contains `CalendarGrid` +
  member sidebar, auto-closes on outside click (`grabFocus: true`)
- **Still missing for parity with Preview (see Phase 3.4):** theme `FileView`
  watchers (theme props are hardcoded defaults today) and the auto-refresh
  `Timer`

### 2.4 `BarWidget.qml` ⚠️ NOT WIRED
- Toggle via `Loader` + `PopupWindow` Component works, but the Component
  creates an **empty PopupWindow** — `Panel.qml` is never loaded, no shell /
  bar / theme properties are passed, and no positioning is done
- This is the main blocker for the plugin being usable from the Omarchy bar

---

## Phase 3: Next Implementation (prioritized)

### 3.1 Wire `BarWidget.qml` → `Panel.qml` — HIGHEST PRIORITY
- `panelComponent` should instantiate `Panel.qml` (via `Loader.source` or
  inline the panel content), passing `shell`, `bar`, and theme properties
- Position the `PopupWindow` relative to the bar widget (Omarchy popup
  conventions); verify outside-click close (`grabFocus`) still works
- Smoke-test the real plugin path end to end

### 3.2 Dynamic week/day headers in `CalendarGrid.qml`
- Day header is **hardcoded** (`"PON. 20" … "NIEDZ. 26"`) — wrong for any
  week other than the one it was screenshotted in
- Derive day names + dates from the DataController week start
  (`DataController.getWeekStart()`), re-rendered on week navigation

### 3.3 Wire remaining `team.json` config
- `timeRange {startHour, endHour}` → pass through to `CalendarGrid`
  (currently hardcoded readonly 7–18)
- `weekStart` (0=Mon … 6=Sun) → honor in `DataController.getCurrentWeekStart()`
  and `CalendarService.getWeekRange()` (currently hardcoded Monday)
- Defaults already exist in `DataController._config`

### 3.4 `Panel.qml` parity with `Preview.qml`
- Add theme `FileView` watchers (`colors.toml`, `theme.name`) so the panel is
  theme-aware and reacts to live theme switches
- Add the auto-refresh `Timer` (only Preview has it today)

### 3.5 Use the existing HTTP cache
- `Network.fetchJsonCached` is implemented but unused; `CalendarService` uses
  plain `fetchJson`. Switch `events.list` GETs to `fetchJsonCached` (30 s TTL)
  so rapid member toggles re-render instantly from cache and hammer the
  Google API less

### 3.6 Error handling & UX polish
- Retry with exponential backoff on network error
- Offline detection (cached data + stale badge)
- Empty state: "No events this week" / "No active members"
- Tooltips on events with full description

---

## Phase 4: Install & Verify

- Install as Omarchy plugin → test bar widget → panel → toggle → week nav →
  live theme switch
- Keep `_Bisect.qml` as a regression check until this lands, then remove it

---

## File Map (Target State)

```
/home/shpaq/GoogleDrive/Pomysly/OmaTeamCal/
├── manifest.json
├── team.json              # apiKey, refreshIntervalMinutes, (+ timeRange, weekStart)
├── BarWidget.qml          # must load Panel.qml (3.1)
├── Panel.qml              # + theme watchers + refresh timer (3.4)
├── Preview.qml            # standalone dev harness
├── components/
│   ├── CalendarGrid.qml   # + dynamic day headers, configurable hours (3.2, 3.3)
│   ├── MemberFilter.qml   # aligned to selectedUserIds contract (unused so far)
│   └── PatternRect.qml
└── scripts/
    ├── ColorEngine.js
    ├── StyleAssigner.js
    ├── Network.js         # fetchJsonCached exists — wire it up (3.5)
    ├── CalendarService.js
    ├── EventNormalizer.js
    └── DataController.js
```

---

## Notes & Constraints

- **No OAuth** — public calendars only, API key auth
- **Quickshell JS restrictions** — `.pragma library` modules, no ES6 modules, `XMLHttpRequest` only
- **QML delegate lifecycle** — never reassign a ListView's JS-array model from
  within a delegate signal handler; keep selection state outside the model
  (see 2.2). Root functions called from delegates are fine as long as the
  model stays stable.
- **Timezones** — Google Calendar returns RFC3339 with timezone; normalize to local for display
- **Rate limits** — maxResults=100 per calendar; use the HTTP cache (3.5)
- **Omarchy integration** — `themeBg`, `themeAccent`, `themeForeground`, `themeMuted` from `colors.toml`
