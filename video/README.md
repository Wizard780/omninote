# omninote launch reel

A 32-second motion piece for omninote, rendered from code. Each frame is `window.seek(t)` in `index.html`,
captured by headless Chromium and encoded with ffmpeg. Music and UI sounds are synthesized in Node on the
same timeline (`timeline.js`), so every keystroke, result, swipe and theme wipe lands on its sound.

## Build

Needs Node 22+, ffmpeg, macOS (it loads SF Mono / SF Pro from /System/Library/Fonts).

```sh
npm i && npx playwright install chromium
node -e "require('fs').writeFileSync('cues.json', JSON.stringify(require('./timeline.js').cues()))"
node sfx.mjs cues.json out/sfx.wav && node score.mjs out/score.wav
node render.mjs --w 1920 --h 1080 --fps 60 --sub 4 --dur 32 --out out/silent_16x9.mp4   # also 1080x1920, 1080x1080
ffmpeg -y -i out/silent_16x9.mp4 -i out/score.wav -i out/sfx.wav \
  -filter_complex "[1:a][2:a]amix=inputs=2:normalize=0,alimiter=limit=0.7:level=false,loudnorm=I=-16:TP=-2:LRA=11[a]" \
  -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 192k -shortest out/omninote_16x9.mp4
```

`node render.mjs --stills 3,8.5,12` writes single frames to `out/stills/`; `./sheet.sh W H name 8x4 240` makes a
contact sheet. Open `index.html` in a browser for a live (non-exact) preview.

## What was tested
- Two renders of the same slice hash identically (deterministic).
- Contact sheets, motion strips and a phone-size tile reviewed in three rounds (`reviews/review_log.md`).
- All three formats rendered at 60 fps with 4-subframe motion blur and muxed at -16 LUFS.

## Notes
- The window is drawn from colors and geometry sampled off the real screenshots in `docs/` and the
  theme JSON in `Resources/themes`; no UI was invented. Decisions are in `docs/DECISIONS.md`.
- No popups or callout overlays by design.
