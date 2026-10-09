# omninote

An open, dependency-free macOS scratchpad in the spirit of [Antinote](https://antinote.io): one plain-text
window, a stack of notes you swipe through, and a keyword on the first line that turns the note into a
calculator, a checklist, or a timer. Built from the reverse-engineering notes in `ANTINOTE_RE.md`.

## Build and run

Requires macOS 14+ and the Xcode Command Line Tools (no Xcode needed).

```sh
make test   # core library self-checks
make run    # builds dist/omninote.app and opens it
```

`Package.swift` is included for SwiftPM users, but on machines with only Command Line Tools its manifest
fails to link, so the Makefile is the supported path.

## Using it

Type one of these on the first line of a note (add `: Title` after it to name the note):

| Keyword | What the note does |
|---|---|
| `math` | A line ending in `=` shows its result. `name : value` defines a variable (names may contain spaces), `ans` is the last result. `100 + 15%`, `50% of 200`, `√16`, `2^10`, `5!`, `sqrt log log2 ln ceil floor round abs`. Lines starting with `//` are ignored. |
| `sum` / `avg` / `count` | Totals, averages, or counts every number (or lines/words/characters) in the note; shown in the bottom bar. |
| `list` | Every line becomes a checkbox. Type `/x` at the end of a line to toggle it, or click the box. |
| `timer` | `timer` stopwatch · `timer 3.5` or `timer 3:30` countdown · `timer 5 1` pomodoro · `timer pomo` 25/5 · `timer p` pause · `timer r` restart · `timer s` stop. Plays a sound and brings the window forward when done. |
| `code` | Monospace, no link detection. |

Shortcuts: ⌘N new · ⌘D delete · ⌘[ / ⌘] older / newer · ⌘1 front · ⌘⇧1 promote to front · ⌘F search ·
⌘S export · ⌘P pin on top · ⌘+ / ⌘- text size · **⌥A shows or hides omninote from any app** (also the
menu-bar icon).

Notes auto-save and live in `~/Library/Application Support/omninote/notes.sqlite3`, the same `notes`
table shape Antinote 1.x uses. Auto-delete of untouched notes (off by default) is in the app menu.

## Themes

omninote reads Antinote theme files unchanged. Drop any community theme JSON (for example
[dracula/antinote](https://github.com/dracula/antinote)) into the folder opened by **omninote > Open
Themes Folder**, choose **Reload Themes**, and pick it from the Theme menu. Knight, Paper, and Dracula
are bundled.

## URL scheme

```
omninote://createNote?content=hello%20world
omninote://appendToCurrent?content=more
```

## Not implemented (on purpose, for now)

iCloud sync, extensions, link shrinking, screenshot OCR, unit and currency conversion, trackpad swipe
gestures (keyboard only), find-and-replace, timer state across relaunch, word stripping inside math
lines (use clean expressions; unknown words show `= ?`).
