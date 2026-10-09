# omninote — progress

## Task
Build "omninote", an open alternative to Antinote (see ANTINOTE_RE.md), as a native macOS app.

## Plan (decisions)
- Stack: Swift Package (SwiftPM executable), AppKit NSTextView editor, system sqlite3 C API, no third-party deps. Bundled into omninote.app by a script (Info.plist with omninote:// URL scheme).
- v0.1 scope: note stack in SQLite (same shape as Antinote: id, created, lastModified, content, dbIndex);
  ⌘N new, ⌘D delete, ⌘[ / ⌘] prev/next, ⌘1 front, ⌘⇧1 promote, ⌘F search;
  first-line keywords: math (lines ending "=", variables "name : value", ans, % ), sum / avg / count, list (/x toggles, click toggles), timer (stopwatch / countdown / pomo + notification), code (monospace, no features);
  global hotkey ⌥A (Carbon), status-bar item, floating window that remembers frame;
  Antinote-compatible JSON themes (drop community themes into ~/Library/Application Support/omninote/Themes);
  auto-delete unmodified notes after N days; export current note .txt/.md; omninote://createNote?content=.
- Skipped on purpose: iCloud sync, extensions, link shrinking, OCR, currency/unit conversion, Setapp/licensing, swipe gestures (keyboard only), find&replace.

## Done criteria
- `swift build` and `swift test` pass (tests for math evaluator + keyword processors + store).
- App launches, screenshot shows editor with a math note evaluated.
- URL scheme creates a note (verified in sqlite).
- Subagent review of the code, findings fixed.

## Log
- 2026-10-08 Stage 1 done: OmninoteCore + 77 assert checks (`make test` OK). SwiftPM manifest fails to link on this CLT install, so builds use the Makefile (swiftc).
- 2026-10-08 Stage 2+3 done: AppKit app (editor, menus, search, timer, themes, hotkey, status item, auto-delete, export, URL scheme). Verified: launched dist/omninote.app, created math/list/timer notes via omninote://createNote, screenshots /tmp/omninote-{math,list,timer,dracula}.png, rows present in notes.sqlite3. Fixed: results not saved on load; theme pref overwritten on init; checkbox link styling.
- Not verified: ⌥A global hotkey and checkbox click (synthetic input needs Accessibility access, which is denied here). Timer restarts on relaunch (state not persisted; skipped).
## Next
- Subagent code review, fix findings, commit.
- 2026-10-08 Review fixed (11 findings + 3 minor): timer input validation, undo registration for programmatic edits, number regex backtracking, keyword-alone detection, "/x" in URLs, variable substitution without exponents, comma thousands vs decimal, pomodoro phase alerts, timer command debounce, LIKE escaping, link scheme allowlist, nil editor on failed store, empty stack guard. 99 checks pass; app relaunched OK.
- 2026-10-08 Advisor pass: timer phase now computed from spec (stopwatch no longer alerts each tick), timer survives note switching, window frame restores. 105 checks pass. Test DB and theme default removed so first launch is clean.
## Status: done. Build with `make run`.
- 2026-10-08 Added: two-finger swipe navigation (SwipeTextView, momentum ignored), "Empty note deleted" pill, arrow-key caret placement after navigating, Font menu (SF Mono default), app icon (scripts/make-icon.swift → Resources/omninote.icns). Verified: build, launch, URL-scheme notes render in SF Mono, icon renders. Not verified by me: the swipe gesture itself (no synthetic trackpad input), though the pill appeared during the session from live trackpad use.
- 2026-10-08 Note transitions slide+fade in the swipe direction (reduced-motion respected); pill rebuilt as a container with a centered label and fade in/out; URL actions nextNote/previousNote added (also used to drive the verification). Verified by rapid frame capture: /tmp/anim-1.png faded-out, anim-2.png mid-slide; pill centered in docs/screenshot-pill.png.
- 2026-10-08 Settings: hover gear in the top-right corner opens a SwiftUI popover (theme, font, size, menu bar, Dock, pin, auto-delete) backed by SettingsModel; menus stay in sync. Second review pass fixed 7 findings: backspace on an empty list marker, keystrokes during the swipe animation, duplicate theme names, timer debounce across notes, stale pill fade, exotic line separators, CRLF. 113 checks. Verified popover via omninote://settings on the installed copy (docs/screenshot-settings.png). Not verified: hover reveal, toggling Dock/menu bar live (needs real input). Gotcha: both dist/ and /Applications bundles register the URL scheme; test against the installed copy only.
