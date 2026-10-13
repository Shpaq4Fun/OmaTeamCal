# OmaTeamCal — Team Calendar for Omarchy

A bar widget plugin for [Omarchy](https://omarchy.org) that shows your team's
Google Calendars in a weekly grid, right in your shell bar. Click the 📅 button,
see who's busy, toggle members in and out, and navigate weeks — without ever
leaving your keyboard-driven desktop.

Built with Quickshell/QML, fully theme-adaptive: colors come live from your
active Omarchy theme, so it always matches the rest of your bar.

## Features

- **Bar widget + popup panel** — 📅 button in the bar, wide weekly grid in a
  popup anchored to the button (dismiss with outside click)
- **Multi-member view** — every team member's events in one weekly grid
  (default Mon–Sun, 07:00–18:00)
- **Per-member styling** — each member gets a unique color tint **and** pattern
  (solid / diagonal stripes / dots / crosshatch), derived from your theme's
  accent color. Sidebar checkboxes share the same swatch, so members are easy to
  match
- **Toggle members** — click a member to show/hide their events; the selection
  updates instantly without refetching the whole week
- **Week navigation** — ◀ / ▶ moves one week at a time; day headers always show
  the real dates of the displayed week
- **Configurable week** — set the first day of the week (`0`=Mon … `6`=Sun) and
  the visible hour range (default 07:00–18:00) in `team.json`
- **Hover tooltips** — hover an event for full details: title, time, member,
  location, and description
- **Instant toggling** — API responses are cached for 30 s, so rapid member
  clicks re-render immediately instead of re-hitting Google every time
- **Auto-refresh** — polls Google Calendar on an interval you configure
  (default: every 5 minutes), plus a manual ⟳ Refresh button
- **Error handling** — transient failures (offline, timeout, 5xx) are retried
  automatically with backoff; when a fetch fails but data is already on screen,
  a subtle "⚠ Showing saved data · updated HH:MM" badge replaces the error
- **Empty states** — "No active members" / "No events this week" instead of a
  blank grid
- **Theme-adaptive** — follows your Omarchy theme live; switch themes and the
  panel restyles itself, no restart needed

## Requirements

- **Omarchy** with shell plugin support (`omarchy plugin …` commands)
- **Google Calendar API key** (free; see [Setup](#1-get-a-google-calendar-api-key))
- **Publicly readable calendars** — API-key auth only works for calendars
  shared publicly (see [Sharing calendars](#2-share-the-calendars-publicly))

## Install

```sh
omarchy plugin add https://github.com/Shpaq4Fun/OmaTeamCal.git --enable
```

The installer asks where to place the widget in the bar (the manifest suggests
**right**). The plugin is cloned into
`~/.config/omarchy/plugins/shpaq.omateamcal/` and picks up changes
automatically — no restart needed.

Then create your config (it is deliberately **not** shipped with the repo):

```sh
cd ~/.config/omarchy/plugins/shpaq.omateamcal
cp team.example.json team.json
$EDITOR team.json
```

The panel opens as soon as `team.json` is valid — save the file and click 📅.

Uninstall with `omarchy plugin remove shpaq.omateamcal`.

## 1. Get a Google Calendar API key

1. Go to [Google Cloud Console](https://console.cloud.google.com/) and create a
   project (or pick an existing one).
2. **APIs & Services → Library** → find **Google Calendar API** → **Enable**.
3. **APIs & Services → Credentials → Create credentials → API key**.
4. (Recommended) **Edit** the key → **API restrictions** → restrict it to
   **Google Calendar API** only. Application restrictions are optional for a
   local desktop widget.
5. Copy the key (`AIza…`) into `team.json` → `apiKey`.

> If Google rejects the key, the panel shows
> `HTTP 400: API key not valid` or `API has not been used` — redo steps 2–4.

## 2. Share the calendars publicly

The plugin authenticates with an API key, so every calendar it should read must
be public:

1. In Google Calendar, open **Settings → [the calendar] → Access permissions
   for events**.
2. Enable **Make available to public**.
3. While you're there, copy the **Calendar ID** from
   **Integrate calendar** — you'll need it for `team.json`
   (looks like `…@group.calendar.google.com` or an address).

Only expose events you're comfortable making readable by anyone with the key.

## Preparing `team.json`

```jsonc
{
  "apiKey": "AIza…",              // your Google Calendar API key
  "refreshIntervalMinutes": 5,     // auto-refresh interval (optional, default 5)
  "weekStart": 0,                  // first day of week: 0=Mon … 6=Sun (default 0)
  "timeRange": {                   // visible hours in the grid (default 7–18)
    "startHour": 7,
    "endHour": 18
  },
  "users": [
    {
      "id": "user-0",              // stable, unique id (any string)
      "name": "First team member",      // display name in the sidebar
      "calendarId": [              // one or more Google Calendar IDs
        "abc123@group.calendar.google.com"
      ],
      "public": true               // selected by default at startup (default true)
    }
  ]
}
```

### Fields

| Field | Where | Required | Meaning |
|---|---|---|---|
| `apiKey` | top level | yes | Google Calendar API key |
| `refreshIntervalMinutes` | top level | no | Auto-refresh period in minutes (default `5`) |
| `weekStart` | top level | no | First day of the week: `0`=Mon … `6`=Sun (default `0`) |
| `timeRange` | top level | no | Visible hours: `{"startHour": 7, "endHour": 18}` (default 7–18; clamped so at least one hour shows) |
| `users` | top level | yes | List of team members shown in the sidebar |
| `id` | user | yes | Unique, stable id — used for selection and styling. Never reuse an id for a different person (selection state keys off it) |
| `name` | user | yes | Label shown in the sidebar |
| `calendarId` | user | yes | Array of Calendar IDs to merge into this member's lane. Use several IDs to combine, e.g., a personal + a team calendar |
| `public` | user | no | `true` (default): member starts **selected**. `false`: starts deselected, still togglable by hand |
| `invitationCalId` | user | no | Reserved for a future feature — ignored today |

Copy [`team.example.json`](./team.example.json) as your starting point.

> `team.json` is git-ignored on purpose — it holds your API key and team data.
> Never commit it.

## Usage

| Action | How |
|---|---|
| Open/close panel | Click 📅 in the bar |
| Show/hide a member | Click the member in the sidebar |
| Previous/next week | ◀ / ▶ in the panel header |
| Refresh now | ⟳ Refresh button |
| Event details | Hover an event for the tooltip |
| Close panel | Click outside the panel |
| From the terminal | `omarchy-shell shpaq.omateamcal toggle` (also `open` / `close`) |

The color+pattern swatch next to each member matches how their events are
rendered in the grid. The first 20 selected members get unique combinations;
after that they repeat.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `API key not valid` / `API has not been used` | Enable Google Calendar API, check the key — see [Setup](#1-get-a-google-calendar-api-key) |
| `HTTP 403` for a calendar | That calendar isn't shared publicly — see [Sharing calendars](#2-share-the-calendars-publicly) |
| Panel opens but the grid is empty | `team.json` missing/invalid, no users selected, or no events that week — check the terminal running the shell for QML errors |
| Wrong dates in the header | The header derives from today's date; check the system clock |
| Widget missing from the bar | `omarchy plugin list` to confirm it's discovered, then `omarchy plugin enable shpaq.omateamcal` |

## Development

```sh
git clone https://github.com/Shpaq4Fun/OmaTeamCal.git
cd OmaTeamCal
```

- **`Preview.qml`** — standalone harness, runs without installing:
  `quickshell -p ./Preview.qml`
- **`_Bisect.qml`** — headless regression driver (toggle invariants). It prints
  `DRIVER RESULT: PASS/FAIL`; run `quickshell -p ./_Bisect.qml`
- **Installed plugin** — saved changes under
  `~/.config/omarchy/plugins/shpaq.omateamcal/` hot-reload the live shell
- **Validate the manifest** before publishing:
  `omarchy plugin validate .`

### Structure

```
manifest.json            # Omarchy plugin manifest (entry: Panel.qml)
Panel.qml                # Bar button + popup panel (the plugin entry point)
Preview.qml              # Standalone dev harness
team.example.json        # Config template
components/
  CalendarGrid.qml       # Weekly grid with derived day headers
  MemberFilter.qml       # Sidebar checkbox list (selection contract reference)
  PatternRect.qml        # Tint/pattern swatch renderer
scripts/
  DataController.js      # Orchestration, selection, week offset, callbacks
  CalendarService.js     # Google Calendar API calls (+ FreeBusy)
  EventNormalizer.js     # API responses → grid rows
  EventLayout.js         # Grid overlap/stacking of event blocks
  Network.js             # XMLHttpRequest helper + TTL cache
  ColorEngine.js         # (palette utilities)
  StyleAssigner.js       # (style slot utilities)
```

## Roadmap

- Keyboard dismissal (`Escape`) for the popup
- RSVP/invitation support (the reserved `invitationCalId` field)

## Notes

- **No OAuth** — public calendars only, plain API-key auth. Nothing is stored
  locally except `team.json`.
- Not affiliated with Google or Omarchy.
