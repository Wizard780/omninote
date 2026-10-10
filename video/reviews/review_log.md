# Review log

Scores: hook · phone readability · motion · variety · composition · brand accuracy · sound sync

## Round 0 (contact_r0, first stills)
6 · 5 · 7 · 8 · 7 · 8 · n/a
1. Count subtitle ran into the window (18.0). → status mirror wraps on " · ".
2. `=` stayed white; the app colors " = result" with typeSubtle (screenshot-math.png). → `=` eases to subtle with the result.
3. End lockup: icon sat above the wordmark block's center. → icon y aligned to the block.

## Round 1 (prev.mp4 strips, contact_portrait/square, phone.png)
7 · 6 · 7 · 7 · 7 · 8 · 8
1. ⌥A: note text stayed on screen while the window was hidden (keyword span reset globalAlpha). → base-alpha multiplier.
2. Hidden beat (25.5–26.5) was dead on the right half; keycaps tiny. → keys glide into the window's spot, grow, second press brings the window back over them.
3. 9:16 / 1:1: header crossed the morphing icon at 28.2. → icon-left/wordmark-right lockup in every format.
4. Phone tile: window text ~7 px at 360 wide. → window 760x520 (notes only use the top), scale 1.3 → 1.5 in 16:9.
Determinism: two renders of 21.5–23 s, md5 ed532dea… both.

## Round 2 (contact_l2, end strips)
8 · 8 · 8 · 8 · 8 · 9 · 8
Remaining nits accepted: header "dracula" sits 60 px from the window edge in 16:9; square lockup brushes the icon for ~2 frames at 28.3.

## Round 3 (subagent code review vs app source)
Fixed: note position (newest is 1/N), timer start after the 0.6 s debounce, duplicate key clicks when header and
note type on the same instant, render.mjs default duration. Kept: checkbox color (real screenshot wins).
