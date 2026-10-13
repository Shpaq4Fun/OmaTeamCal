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

### 2.3 `Panel.qml` ✅ DONE — rewritten as modern single-entry Omarchy plugin
- Root is now shell `Panel` (from `qs.Ui`): `moduleName`/`ipcTarget` set,
  `manageIpc` default handles open/close/toggle IPC
- Bar button (`WidgetButton`, 📅) + popup (`KeyboardPanel` anchored to the
  button; outside-click dismissal, screen-cap fitting via `fittedContentWidth`)
- `implicitWidth`/`implicitHeight` bound to the button (bar slot sizes from
  these — Bar.qml:1814)
- Theme: live from the `Color` singleton (`qs.Commons`) — no FileView watchers
  needed, theme switches apply automatically (3.4 theme half: moot)
- Auto-refresh `Timer` added (interval from team.json, default 5 min)
- `team.json` loaded via `Qt.resolvedUrl` (works installed AND standalone)

### 2.4 `BarWidget.qml` ✅ REMOVED
- Obsolete: the modern Omarchy pattern is a single `Panel.qml` entry; the
  manifest now points `entryPoints.barWidget` at `Panel.qml`

---

## Phase 3: Next Implementation (prioritized) ✅ ALL DONE (2026-10-13)

### 3.1 Wire `BarWidget.qml` → `Panel.qml` ✅ DONE (2026-10-13)
- Implemented as the modern single-entry pattern (see 2.3) instead of
  Loader wiring — `Panel.qml` IS the barWidget entry
- Compile-verified standalone (harness with `qs.*` symlinked) and via
  `_Bisect.qml` — **not yet smoke-tested inside the live Omarchy bar** (Phase 4)

### 3.2 Dynamic week/day headers in `CalendarGrid.qml` ✅ DONE (2026-10-13)
- `weekStart` property added; `days` derived (`PON. 12` …) from it
- `weekStartDate(offset)` + `weekStart` binding in Preview/Panel; passed to
  grid; re-renders on ◀/▶ week navigation
- Verified: `weekStart=Mon Oct 12 2026`, `days=[PON. 12 … NIEDZ. 18]`,
  labels `OCT 12 - OCT 18` / next `OCT 19 - OCT 25`

### 3.3 Wire remaining `team.json` config ✅ DONE (2026-10-13)
- `timeRange {startHour, endHour}` → clamped in `DataController.setConfig`,
  passed to `CalendarGrid` (was hardcoded 7–18)
- `weekStart` (0=Mon … 6=Sun) → honored in `DataController.getCurrentWeekStart()`,
  `CalendarService.getWeekRange()` (now trusts the configured start),
  UI `weekStartDate()`/`weekLabel()`, and the day header rotation in
  `CalendarGrid.days`
- Single `setConfig` call on team.json load; UI reads back the clamped values
  via `getConfig()` so both sides always agree
- Verified live: `weekStart: 1` + `timeRange 6–20` → `weekStart=Tue Oct 13`,
  days `[WT. 13 … PON. 19]`, hours 6–20, toggle PASS; restored defaults verified

### 3.4 `Panel.qml` parity with `Preview.qml` ✅ DONE (2026-10-13)
- Theme handled via the `Color` singleton (live, better than FileView
  watchers); auto-refresh `Timer` added
- ~~**BLOCKER for live events:** `team.json` `apiKey` placeholder~~ — resolved,
  user restored the real key; live fetch verified (41 events, PASS)

### 3.5 Use the existing HTTP cache ✅ DONE (2026-10-13)
- `CalendarService.fetchEventsForCalendar` → `Network.fetchJsonCached`
  (30 s TTL): rapid member toggles re-render instantly from cache
- Manual ⟳ Refresh calls `Network.clearCache()` first so it really refetches
- Auto-refresh interval (≥ 5 min) always exceeds the TTL → fresh data

### 3.6 Error handling & UX polish ✅ DONE (2026-10-13)
- **Retry:** exponential backoff (2s/4s/8s, max 3 attempts) for transient
  errors (network/timeout/5xx/429); UI drives the delay via a retry Timer —
  `.pragma library` can't create timers itself. Banner shows "Retrying…"
- **Offline badge:** when a fetch fails but events exist, the red banner is
  replaced by a subtle amber "⚠ Showing saved data · updated HH:MM · retrying…"
- **Empty states:** "No active members" (with hint) / "No events this week"
- **Tooltips:** hover any event → details card (title, time, member, location,
  description ≤ 4 lines), clamped inside the grid, immune to scroll clipping

---

## Phase 4: Install & Verify

- **Prereq:** restore real Google API key in `team.json`
- Install as Omarchy plugin (symlink `~/.config/omarchy/plugins/shpaq.omateamcal`
  → this repo) → test bar widget → panel → toggle → week nav → live theme switch
- Keep `_Bisect.qml` as a regression check until this lands, then remove it

---

## File Map (Target State)

```
/home/shpaq/GoogleDrive/Pomysly/OmaTeamCal/
├── manifest.json           # entryPoints.barWidget → Panel.qml
├── team.json              # apiKey, refreshIntervalMinutes, weekStart, timeRange ✅
├── Panel.qml              # single-entry Omarchy plugin: bar button + KeyboardPanel ✅
├── Preview.qml            # standalone dev harness
├── components/
│   ├── CalendarGrid.qml   # ✅ dynamic day headers, configurable hours, tooltips
│   ├── MemberFilter.qml   # aligned to selectedUserIds contract (unused so far)
│   └── PatternRect.qml
└── scripts/
    ├── ColorEngine.js
    ├── StyleAssigner.js
    ├── Network.js         # ✅ fetchJsonCached wired into CalendarService
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
- **Omarchy integration** — theme comes live from the `Color` singleton
  (`qs.Commons`); `Preview.qml` falls back to FileView watchers on `colors.toml`
