# PomodoroBar

A native macOS menu bar pomodoro timer. Swift/AppKit, no dependencies.

## Features

- **Global hotkey** — press **⌃⌥⌘P** anywhere to start a pomodoro (context-aware: it also starts the break from the "pomodoro complete" screen and the next pomodoro from the "break over" screen). No Accessibility permission needed.
- **Menu bar timer** — live countdown in the system tray: `🍅 24:31` while focusing, `☕️ 04:12` on break.
- **25 min tasks / 5 min breaks**, both extendable in +5 min increments from the menu or the fullscreen prompts.
- **Session goals** — when a pomodoro starts you can enter an optional goal; when it ends (completed or stopped early) you record whether the goal was achieved plus a free-text comment.
- **History** — every pomodoro across all days (last 30 days), grouped by day with per-day totals: start/finish time, duration, status (completed/abandoned), goal, and end comment, plus total focus time for today. Open via *History…* in the menu. Persisted to `~/Library/Application Support/PomodoroBar/sessions.json`.
- **Fullscreen prompts** — when a pomodoro completes ("start break or extend task"), and when the break ends ("start next pomodoro or extend break").
- **Typing guard** — a prompt ignores the keyboard until you've stopped typing for ~1.5 s, so a Return/Esc already in flight can't dismiss it before you notice it. Buttons stay disabled while locked.
- **Activity nag** — if you're actively using the computer for ~30 s with no pomodoro running, a fullscreen reminder asks you to start one (snoozable for 5 min).
- **Start at login** — toggle *Start at Login* in the menu to register the app as a login item (requires running the built `.app` bundle, not `swift run`).

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

Available keys: `taskSeconds`, `breakSeconds`, `extendSeconds`, `activityWindowSeconds`, `snoozeSeconds`, `pollSeconds`, `promptGuardSeconds`.
