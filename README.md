# PomodoroBar

A native macOS menu bar pomodoro timer. Swift/AppKit, no dependencies.

## Features

- **Global hotkey** — press **⌃⌥⌘P** anywhere to start a pomodoro (context-aware: it also starts the break from the "pomodoro complete" screen and the next pomodoro from the "break over" screen). No Accessibility permission needed.
- **Menu bar timer** — live countdown in the system tray: `🍅 24:31` while focusing, `☕️ 04:12` on break.
- **25 min tasks / 5 min breaks**, both extendable in +5 min increments from the menu or the fullscreen prompts.
- **Session goals** — when a pomodoro starts you can enter an optional goal; when it ends (completed or stopped early) you record whether the goal was achieved plus a free-text comment.
- **Task mode** — ties every pomodoro to a task from a NocoDB todo table instead of a free-text goal. See below.
- **History** — every pomodoro across all days (last 30 days), grouped by day with per-day totals: start/finish time, duration, status (completed/abandoned), goal, and end comment, plus total focus time for today. Open via *History…* in the menu. Persisted to `~/Library/Application Support/PomodoroBar/sessions.json`.
- **Fullscreen prompts** — when a pomodoro completes ("start break or extend task"), and when the break ends ("start next pomodoro or extend break").
- **Typing guard** — a prompt ignores the keyboard until you've stopped typing for ~1.5 s, so a Return/Esc already in flight can't dismiss it before you notice it. Buttons stay disabled while locked.
- **Activity nag** — if you're actively using the computer for ~30 s with no pomodoro running, a fullscreen reminder asks you to start one (snoozable for 5 min).
- **Start at login** — toggle *Start at Login* in the menu to register the app as a login item (requires running the built `.app` bundle, not `swift run`).

## Task mode

Outside work hours the goal prompt is replaced by a dropdown of the tasks that
are actually due, so the todo list is always in front of you.

- **When it's on** — *Task Mode* in the menu is `Auto` (default), `Always On` or
  `Off`. Under `Auto` it is active outside **Mon–Fri 09:00–17:00**: evenings,
  nights and all weekend.
- **Which tasks** — open (`Done != 1`), tagged `TODO`, and due **today or
  earlier**; overdue rows are flagged `⚠`. Undated and future tasks never
  appear. Sorted by `Priority` descending, oldest first within a priority.
- **Picking one is required.** Choosing *Other…* reveals a field that creates a
  new task in NocoDB immediately (due today, `TODO`, priority 0 — the same
  defaults as `note_nocodb.sh`), so it's there for the rest of the day.
  Cancelling the dialog aborts the pomodoro rather than recording a session
  with no task.
- **The menu lists the top 7 tasks** while task mode is active; clicking one
  starts a pomodoro on it straight away, no dialog. The list is cached and
  refreshed in the background, so the menu opens instantly.
- **When a pomodoro completes**, its comment is prepended to that task's
  `Komentarz` as `2026-09-13 14:30 — comment`, stamped with the session's start
  time, with the previous contents kept below. A blank comment still records
  the dated line. Pomodoros you stop early are not logged to NocoDB, and
  neither are sessions whose mode changed between start and finish.
- **The app never sets `Done`** — closing a task stays a NocoDB-side action.
- **If NocoDB is unreachable, the pomodoro is cancelled** with an error naming
  the problem. To work through an outage, set *Task Mode* to `Off`. Failed
  comment writes show an alert containing the text so you can paste it in by
  hand; the comment is always saved locally first and is visible in *History*.

### Configuration

Connection details live in `~/Library/Application Support/PomodoroBar/nocodb.json`,
outside the repo so the API token is never committed:

```json
{
  "apiURL": "http://localhost:8080",
  "token": "…",
  "tableID": "…"
}
```

A blank template is written on first run if the file is missing. The table is
expected to have the columns `Title`, `Deadine` (sic), `Kategoria`, `Priority`,
`Komentarz` and `Done`.

## Run

```sh
swift run PomodoroBar
```

The 🍅 appears in the menu bar; there is no Dock icon.

## Install as an app

```sh
./scripts/make-app.sh
open build/PomodoroBar.app     # or copy it to /Applications
```

For reliable auto-start at login, copy the bundle to `/Applications` before enabling *Start at Login* — rebuilds replace `build/PomodoroBar.app` in place, and the login item points at the app's path.

## Testing with short durations

All durations can be overridden on the command line (seconds):

```sh
swift run PomodoroBar -taskSeconds 15 -breakSeconds 10 \
    -activityWindowSeconds 10 -snoozeSeconds 20 -extendSeconds 10
```

Available keys: `taskSeconds`, `breakSeconds`, `extendSeconds`, `activityWindowSeconds`, `snoozeSeconds`, `pollSeconds`, `promptGuardSeconds`, `nocodbTimeoutSeconds`, `taskListRefreshSeconds`.

Task mode has its own (non-duration) overrides — the work-hours window, and how
many tasks the menu lists:

```sh
swift run PomodoroBar -workDayStartHour 8 -workDayEndHour 16 -menuTaskLimit 10
```
