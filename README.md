# PomodoroBar

A native macOS menu bar pomodoro timer. Swift/AppKit, no dependencies.

## Features

- **Global hotkey** — press **⌃⌥⌘P** anywhere to start a pomodoro (context-aware: it also starts the break from the "pomodoro complete" screen and the next pomodoro from the "break over" screen). No Accessibility permission needed.
- **Menu bar timer** — live countdown in the system tray: `🍅 24:31` while focusing, `☕️ 04:12` on break.
- **25 min tasks / 5 min breaks**, both extendable in +5 min increments from the menu or the fullscreen prompts.
- **Daily summary** — every pomodoro's start/finish time, duration, and status (completed/abandoned), plus total focus time for the day. Open via *Today's Summary…* in the menu. Persisted to `~/Library/Application Support/PomodoroBar/sessions.json`.
- **Fullscreen prompts** — when a pomodoro completes ("start break or extend task"), and when the break ends ("start next pomodoro or extend break").
- **Activity nag** — if you're actively using the computer for ~30 s with no pomodoro running, a fullscreen reminder asks you to start one (snoozable for 5 min).

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

## Testing with short durations

All durations can be overridden on the command line (seconds):

```sh
swift run PomodoroBar -taskSeconds 15 -breakSeconds 10 \
    -activityWindowSeconds 10 -snoozeSeconds 20 -extendSeconds 10
```

Available keys: `taskSeconds`, `breakSeconds`, `extendSeconds`, `activityWindowSeconds`, `snoozeSeconds`, `pollSeconds`.
