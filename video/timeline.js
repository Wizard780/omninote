// The one timeline. index.html reads it for picture, cues.mjs reads it for sound.
// 120 BPM: beat 0.5 s, keys on a 1/16 s grid (32nd notes) so typing stays musical.
(function (root) {
  const K = 1 / 16;
  const KEYWORDS = ['math', 'list', 'sum', 'avg', 'count', 'timer', 'code'];

  // Keystroke helpers. Events: {t, k} where k is a char, '\n' or '\b'; {t, move: [line, col]}.
  function type(ev, t, s, rate = K) { for (const ch of s) { ev.push({ t, k: ch }); t += rate; } return t; }
  function back(ev, t, n, rate = K) { for (let i = 0; i < n; i++) { ev.push({ t, k: '\b' }); t += rate; } return t; }

  // Notes. `from` = time the note becomes the current one (swipe commit).
  const notes = [];
  { const e = []; // math: "math" lands on 3.0, each "=" on a beat
    type(e, 2.8125, 'math: Trip');
    e.push({ t: 3.5, k: '\n' }); type(e, 3.5625, 'nights : 3');
    e.push({ t: 4.25, k: '\n' }); type(e, 4.3125, 'hotel : 189');
    e.push({ t: 5.0, k: '\n' }); type(e, 5.0625, 'nights * hotel =');      // '=' at 6.0
    e.push({ t: 6.25, k: '\n' }); type(e, 6.375, 'ans + 15% =');           // '=' at 7.0
    e.push({ t: 7.25, k: '\n' }); type(e, 7.375, 'sqrt(144) =');           // '=' at 8.0
    notes.push({ from: 2.0, ev: e });
  }
  { const e = []; // list: "/x" toggles on 12.0 and 12.5
    type(e, 9.3125, 'list: Groceries');
    e.push({ t: 10.25, k: '\n' }); type(e, 10.3125, 'milk');
    e.push({ t: 10.625, k: '\n' }); type(e, 10.6875, 'eggs');
    e.push({ t: 11.0, k: '\n' }); type(e, 11.0625, 'bread');
    e.push({ t: 11.75, move: [2, 4] }); type(e, 11.9375, '/x');
    e.push({ t: 12.3125, move: [3, 5] }); type(e, 12.4375, '/x');
    notes.push({ from: 9.0, ev: e });
  }
  { const e = []; // sum -> avg (17.0) -> count (18.0)
    type(e, 14.375, 'sum: Rent');
    e.push({ t: 15.0, k: '\n' }); type(e, 15.0625, '1450');
    e.push({ t: 15.375, k: '\n' }); type(e, 15.4375, '320.50');
    e.push({ t: 15.875, k: '\n' }); type(e, 15.9375, '89.99');
    e.push({ t: 16.5, move: [0, 3] }); back(e, 16.625, 3); type(e, 16.875, 'avg');
    back(e, 17.5625, 3); type(e, 17.75, 'count');
    notes.push({ from: 14.0, ev: e });
  }
  { const e = []; // timer: the app applies the line after a 0.6 s debounce (Editor.updateTimer), so it starts on 20.75
    type(e, 19.25, 'timer 3:30: Tea');                                   // ends 20.125
    e.push({ t: 20.875, k: '\n' }); type(e, 20.9375, 'steep, then add honey');   // typed after it started
    notes.push({ from: 19.0, ev: e, timerStart: 20.75, timerSecs: 210 });
  }

  // Swipes: finger drag from t0, spring commit at t1 (= next note's `from`).
  const swipes = [{ t0: 8.6, t1: 9.0 }, { t0: 13.6, t1: 14.0 }, { t0: 18.6, t1: 19.0 }];

  // Header word beside the window: same editor verbs.
  const header = [];
  type(header, 0.25, 'math', 0.25);                     // hook: 8th notes, "h" on 1.0
  back(header, 8.75, 4); type(header, 9.0, 'list');
  back(header, 13.75, 4); type(header, 14.0, 'sum');
  back(header, 16.625, 3); type(header, 16.875, 'avg');
  back(header, 17.5625, 3); type(header, 17.75, 'count');
  back(header, 18.6875, 5); type(header, 19.0, 'timer');
  back(header, 22.0, 5); type(header, 22.125, 'dracula');
  back(header, 23.0, 7); type(header, 23.1875, 'paper');
  back(header, 24.0, 5); type(header, 24.125, 'knight');
  back(header, 25.0, 6); type(header, 25.125, '⌥A');
  back(header, 27.75, 2); type(header, 28.0, 'omninote');

  // Subtitles under the header: typed in, removed by select + delete. live: mirrors the status line.
  const subs = [
    { t: 3.25, out: 8.5, text: 'a calculator that\nreads like a note' },
    { t: 9.5, out: 13.5, text: 'every line becomes\na checkbox' },
    { t: 14.5, out: 18.5, live: true },
    { t: 19.6, out: 21.75, text: 'countdown, stopwatch,\npomodoro' },
    { t: 22.5, out: 24.875, text: 'antinote themes,\nunchanged' },
    { t: 25.2, out: 27.6, text: 'show or hide it\nfrom any app' },
  ];

  const themes = [{ t: 22.5, to: 'dracula' }, { t: 23.5, to: 'paper' }, { t: 24.5, to: 'knight' }];
  const keyPress = [25.5, 26.5];          // ⌥A: hide on the first, show on the second
  const keycaps = { in: 25.125, out: 27.5 };
  const end = { morph: 28.0, ring: 28.45, real: 29.1, line1: 29.5, line2: 30.25 };
  const endLines = ['free · open source · macOS 14+', 'github.com/Wizard780/omninote'];

  // Sound cues on the same times. Types are voices in sfx.mjs.
  function cues() {
    const c = [];
    const allKeys = [...header, ...notes.flatMap((n) => n.ev)].filter((e) => e.k);
    const seen = new Set();   // header and note type on the same instants for avg/count: one click each
    for (const e of allKeys) { if (seen.has(e.t)) continue; seen.add(e.t); c.push({ t: e.t, type: e.k === '\b' ? 'tickb' : e.k === '\n' ? 'enter' : 'tick' }); }
    c.push({ t: 1.0, type: 'thump' }, { t: 2.0, type: 'whoosh' });
    for (const t of [3.0, 9.5, 14.5, 17.0, 18.0, 19.5]) c.push({ t, type: 'snap' });
    c.push({ t: 20.75, type: 'pop' });                                                    // timer starts   // keyword recognised
    for (const t of [6.0, 7.0, 8.0]) c.push({ t: t + 0.06, type: 'pop' });               // math results
    for (const t of [12.0, 12.5]) c.push({ t, type: 'check' });
    for (const s of swipes) c.push({ t: s.t1 - 0.05, type: 'whoosh' });
    for (const th of themes) c.push({ t: th.t, type: 'swish' });
    for (const t of keyPress) c.push({ t, type: 'thock' });
    c.push({ t: end.morph, type: 'whoosh' }, { t: end.real, type: 'thump' });
    for (let i = 0; i < endLines[0].length; i++) c.push({ t: end.line1 + i / 40, type: 'tick' });
    for (let i = 0; i < endLines[1].length; i++) c.push({ t: end.line2 + i / 40, type: 'tick' });
    return c.sort((a, b) => a.t - b.t);
  }

  const TL = { DUR: 32, BPM: 120, K, KEYWORDS, notes, swipes, header, subs, themes, keyPress, keycaps, end, endLines, cues };
  if (typeof module !== 'undefined' && module.exports) module.exports = TL;
  else root.TL = TL;
})(typeof window !== 'undefined' ? window : globalThis);
