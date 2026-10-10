// Closed-form motion primitives. Every function is a pure function of time,
// so any frame can be rendered without simulating the frames before it.
// Loaded as a classic <script> in index.html (defines window.Motion) and
// also usable from Node (module.exports).

(function (root) {
  const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));

  // Damped spring from 0 to 1. k = stiffness, d = damping.
  // z < 1 overshoots slightly; z >= 1 settles with no overshoot.
  function spring(t, k = 170, d = 26) {
    if (t <= 0) return 0;
    const w0 = Math.sqrt(k), z = d / (2 * w0);
    if (z < 1) {
      const wd = w0 * Math.sqrt(1 - z * z);
      return 1 - Math.exp(-z * w0 * t) * (Math.cos(wd * t) + (z * w0 / wd) * Math.sin(wd * t));
    }
    return 1 - Math.exp(-w0 * t) * (1 + w0 * t);
  }

  // Presets per object class. Pick by what the object is, not by taste.
  const SPRINGS = {
    micro:   [320, 30],   // buttons, toggles, leading edges: snappy, tiny overshoot
    panel:   [170, 26],   // cards, containers, camera: controlled settle
    heavy:   [120, 24],   // big type, logo lockups: no overshoot
    playful: [200, 16],   // mascots, stickers: visible overshoot
  };
  const ease = (t, cls = 'panel') => spring(t, ...SPRINGS[cls]);

  // A value with several targets over time. keys: [[time, value], ...] sorted.
  // Sum of one spring per change, so changing target never restarts motion.
  function track(t, keys, k = 170, d = 26) {
    let v = keys[0][1];
    for (let i = 1; i < keys.length; i++)
      v += (keys[i][1] - keys[i - 1][1]) * spring(t - keys[i][0], k, d);
    return v;
  }

  // Tab indicator that stretches: leading edge stiffer than trailing edge.
  function indicator(t, stops, width = 120) {
    const lead = track(t, stops, 320, 30);
    const trail = track(t, stops, 140, 22);
    return { left: Math.min(lead, trail), right: Math.max(lead, trail) + width };
  }

  // Alpha for text inside a morphing box: in after the morph starts, out before the next.
  function swapAlpha(t, tIn, tOut) {
    return Math.min(clamp((t - tIn - 0.08) / 0.12), clamp((tOut - 0.1 - t) / 0.1));
  }

  // Seamless loop: pin t into [0, dur).
  const loopT = (t, dur) => ((t % dur) + dur) % dur;

  // Seeded RNG (mulberry32). Never Math.random: the render must hash identical every run.
  function rng(seed) {
    return () => {
      seed |= 0; seed = seed + 0x6D2B79F5 | 0;
      let t = Math.imul(seed ^ seed >>> 15, 1 | seed);
      t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
      return ((t ^ t >>> 14) >>> 0) / 4294967296;
    };
  }

  const api = { clamp, spring, SPRINGS, ease, track, indicator, swapAlpha, loopT, rng };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.Motion = api;
})(typeof window !== 'undefined' ? window : globalThis);
