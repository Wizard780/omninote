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
