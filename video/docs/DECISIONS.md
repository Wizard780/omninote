# Decisions

- 32 s / 120 BPM: 15 s can't hold six features; 60 s drags.
- Window is re-drawn in canvas from pixel-sampled geometry and theme JSON, not pasted screenshots, because typing
  mid-states don't exist as screenshots. Gate: reviews/fidelity.png compares it with screenshot-pill.png.
- Did not launch the app to capture frames: the URL scheme writes into the user's real notes database.
- SF Mono (app default) instead of System font seen in some screenshots.
- No overlays at all (user asked for no popups). Updater alert, settings popover and the "Oldest note" pill are cut.
- Header word beside the window = the keyword, in the app's accent bold; it is the caption system.
- Sum beat: subtitle mirrors the live status bar line so the totals read at phone size.
- Checkbox color uses the sampled link blue (#5A9AF8) from the real screenshot, not accent3 from code, since
  NSTextView link styling wins on screen.
- Score and SFX synthesized in Node, cues generated from the same timeline.js the picture reads.
- Note position reads 1/N for the newest note (Editor.newNote inserts at index 0), per code review.
- Timer starts at 20.75, 0.6 s after its line is typed (Editor.updateTimer debounce); the body line is typed after.
- Checkbox stays link-blue with the dotted underline: screenshot-list.png was captured with the current styling code
  and shows it on screen, despite the comment on linkTextAttributes.
