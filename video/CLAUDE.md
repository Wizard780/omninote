# Motion studio rules

These apply to every film made in this folder.

## Render contract
- Every film is a pure function of time: `window.seek(t)` paints frame t.
- No CSS transitions, no setTimeout, no requestAnimationFrame in render mode, no state carried between frames.
- Seeded randomness only (`Motion.rng(seed)`), never `Math.random`.
- One `TIMELINE` object holds every beat, move and cue.
- Render with `node render.mjs`. H.264, yuv420p, CRF 16.

## Look
- Banned defaults: centered title on a gradient, everything fading in, corner labels and frame borders, glow on UI chrome, generic particle bursts, stock 3D blobs, fake metrics.
- One display face, one UI face. One accent color unless the brief says otherwise.
- Real product UI only. Never redraw a product screen from imagination. If a required screenshot is missing, stop and ask.
- Every 2 to 4 seconds something new happens on screen.

## Motion
- Closed-form springs from `lib/motion.js`. Pick the class by object type: micro, panel, heavy, playful.
- Any value with more than one target uses `Motion.track()`.
- One focal action at a time. Camera holds still while text is read.
- Objects stay alive across scenes and transform instead of being replaced.

## Sound
- Supplied track: measure it with `beats.py`, use it unchanged. No track: write the score in Node on the same beat grid (extend `sfx.mjs` VOICES or add a `score.mjs`), then SFX with `sfx.mjs`.
- Cues land on the measured beat grid (`beats.json`). Mux and normalise with the command in `~/.claude/skills/motion-design/references/critique.md`: -16 LUFS integrated, true peak at most -1.5 dBTP.

## Loop before showing anyone
1. Render a contact sheet (one frame per beat) and look at it.
2. Score 1 to 10 on the seven criteria: hook in first 2s, readability at phone size, motion quality, variety, composition, brand accuracy, sound sync. Log in `reviews/review_log.md`.
3. Fix the 3 worst problems. Re-render only the affected seconds (`node render.mjs --from A --to B`). Repeat until every score is 8 or above.
4. Only then do the full render.
