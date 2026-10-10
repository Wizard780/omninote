// node score.mjs out/score.wav — the music, synthesized on the TIMELINE grid (120 BPM, 32 s).
// Am – F – C – G, one chord per bar. Deterministic: seeded noise only.
import { writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
const TL = createRequire(import.meta.url)('./timeline.js');

const SR = 48000, DUR = TL.DUR + 2, B = 60 / TL.BPM, BAR = 4 * B;
const L = new Float32Array(DUR * SR), R = new Float32Array(DUR * SR);
let seed = 7; const noise = () => (seed = (seed * 1664525 + 1013904223) >>> 0) / 2147483648 - 1;
const hz = (m) => 440 * 2 ** ((m - 69) / 12);
const CHORDS = [[57, 60, 64, 71], [53, 57, 60, 67], [48, 55, 60, 64], [55, 59, 62, 69]];   // Am9 Fmaj9 Cadd9 G6
const chordAt = (t) => CHORDS[Math.floor(t / BAR) % 4];

function add(t0, len, fn, gain = 1, pan = 0) {
  const s0 = Math.floor(t0 * SR), gl = gain * (1 - pan) / 1, gr = gain * (1 + pan) / 1;
  for (let i = 0; i < len * SR; i++) {
    const j = s0 + i; if (j < 0 || j >= L.length) continue;
    const v = fn(i / SR); L[j] += v * gl; R[j] += v * gr;
  }
}
// Voices
const kick = (t) => Math.sin(2 * Math.PI * (45 * t + 90 * (1 - Math.exp(-t * 30)) / 30)) * Math.exp(-t * 7);
const clap = () => { let lp = 0; return (t) => { const n = noise(); lp += (n - lp) * 0.3; return (n - lp) * Math.exp(-t * 28) * (t < 0.01 || t > 0.02 ? 1 : 0.6); }; };
const hat = () => { let lp = 0; return (t) => { const n = noise(); lp += (n - lp) * 0.5; return (n - lp) * Math.exp(-t * 90); }; };
function bass(m) { let lp = 0; const f = hz(m - 12); return (t) => { const saw = 2 * ((t * f) % 1) - 1; lp += (saw - lp) * 0.06; return lp * Math.min(1, t * 200) * Math.exp(-t * 5); }; }
function pad(ch, len) {
  const lps = ch.map(() => 0);
  return (t) => {
    const env = Math.min(1, t / 0.6) * Math.min(1, (len - t) / 0.5);
    let v = 0; ch.forEach((m, k) => { const f = hz(m); const s = (2 * ((t * f * 1.003) % 1) - 1) + (2 * ((t * f * 0.997) % 1) - 1); lps[k] += (s - lps[k]) * 0.035; v += lps[k]; });
    return v * env * 0.12;
  };
}
const pluck = (m) => (t) => { const f = hz(m); const tri = 2 * Math.abs(2 * ((t * f) % 1) - 1) - 1; return tri * Math.exp(-t * 9) * Math.min(1, t * 400); };

const quiet = (t) => t >= 25.0 && t < 26.5;          // ⌥A: the band drops out until the second press
// Pads all the way through, one per bar
for (let b = 0; b * BAR < TL.DUR; b++) {
  const t0 = b * BAR;
  const len = t0 >= 28 ? 5 : BAR + 0.3;
  add(t0, len, pad(chordAt(t0), len), t0 < 2 ? 0.6 : quiet(t0 + 1) ? 0.35 : 1, (b % 2) * 0.2 - 0.1);
  if (t0 >= 28) break;
}
// Drums + bass from the window arriving (2.0) to the logo (28.0)
for (let t = 2.0; t < 28.0 - 1e-6; t += B / 2) {
  const beat = Math.round(t / B * 2) / 2;
  if (quiet(t)) continue;
  const on = Number.isInteger(beat);
  if (on) add(t, 0.5, kick, 0.9);
  if (on && Math.round(beat) % 2 === 1 && t >= 3) add(t, 0.25, clap(), 0.28, 0.1);
  if (!on) add(t, 0.06, hat(), 0.12, -0.2);
  add(t, B / 2, bass(chordAt(t)[0]), on ? 0.45 : 0.3);
}
// Theme beat: a 16th-note arp in the chord tones
for (let t = 22.0; t < 25.0; t += B / 4) {
  const ch = chordAt(t), i = Math.round(t / (B / 4)) % 4;
  add(t, 0.3, pluck(ch[i] + 12), 0.1, i % 2 ? 0.35 : -0.35);
}
// Hits: hook snap, ⌥A presses, final chord
add(1.0, 1.2, (t) => kick(t) * 1.2 + pluck(69)(t) * 0.2, 0.8);
for (const t of TL.keyPress) add(t, 0.6, kick, 0.9);
add(28.0, 4, (t) => [57, 64, 71, 76].reduce((v, m) => v + pluck(m)(t * 0.35), 0) * 0.5, 0.5);

const n = L.length, buf = Buffer.alloc(44 + n * 4);
buf.write('RIFF', 0); buf.writeUInt32LE(36 + n * 4, 4); buf.write('WAVEfmt ', 8);
buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(2, 22);
buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 4, 28); buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34);
buf.write('data', 36); buf.writeUInt32LE(n * 4, 40);
let peak = 1e-9; for (let i = 0; i < n; i++) peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]));
for (let i = 0; i < n; i++) {
  buf.writeInt16LE(Math.round(L[i] / peak * 0.8 * 32767), 44 + i * 4);
  buf.writeInt16LE(Math.round(R[i] / peak * 0.8 * 32767), 46 + i * 4);
}
writeFileSync(process.argv[2] || 'out/score.wav', buf);
console.log('wrote score', DUR + 's');
