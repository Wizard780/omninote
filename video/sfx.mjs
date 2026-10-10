// node sfx.mjs cues.json out/sfx.wav
// cues.json: [{"t": 0.5, "type": "click"}, {"t": 1.0, "type": "thump"}, ...]
// Synthesizes UI sound effects on the same timeline that drives the picture.
// Deterministic: seeded noise, no Math.random. Output: 16-bit mono WAV at 48 kHz.
import { readFileSync, writeFileSync } from 'node:fs';

const SR = 48000;
const cues = JSON.parse(readFileSync(process.argv[2], 'utf8'));
if (!cues.length) throw new Error('cues.json is empty');
const buf = new Float32Array(Math.ceil((Math.max(...cues.map((c) => c.t)) + 2) * SR));

let s = 42;
const noise = () => (s = (s * 1664525 + 1013904223) >>> 0) / 2147483648 - 1;

// [length seconds, sample function of local time]
const VOICES = {
  click:  [0.05, (t) => Math.sin(2 * Math.PI * 1800 * t) * Math.exp(-t * 90) * 0.5],
  pop:    [0.15, (t) => Math.sin(2 * Math.PI * (600 + 900 * t) * t) * Math.exp(-t * 30) * 0.4],
  thump:  [0.50, (t) => Math.sin(2 * Math.PI * (90 - 60 * t) * t) * Math.exp(-t * 9) * 0.9],
  whoosh: [0.35, (t) => noise() * Math.sin(Math.PI * Math.min(1, t / 0.35)) * 0.25],
  // keyboard: short filtered clicks; pitch varies per key from the seeded noise
  tick:   [0.03, (t) => (noise() * 0.6 + Math.sin(2 * Math.PI * 3200 * t)) * Math.exp(-t * 260) * 0.12],
  tickb:  [0.03, (t) => (noise() * 0.6 + Math.sin(2 * Math.PI * 2400 * t)) * Math.exp(-t * 260) * 0.10],
  enter:  [0.06, (t) => (noise() * 0.5 + Math.sin(2 * Math.PI * 1500 * t)) * Math.exp(-t * 120) * 0.18],
  snap:   [0.20, (t) => (Math.sin(2 * Math.PI * 880 * t) + 0.5 * Math.sin(2 * Math.PI * 1320 * t)) * Math.exp(-t * 22) * 0.16],
  check:  [0.30, (t) => (Math.sin(2 * Math.PI * 1046 * t) * Math.exp(-t * 18) + Math.sin(2 * Math.PI * 1568 * Math.max(0, t - 0.06)) * Math.exp(-Math.max(0, t - 0.06) * 18) * (t > 0.06)) * 0.18],
  swish:  [0.70, (t) => noise() * Math.sin(Math.PI * Math.min(1, t / 0.7)) ** 2 * 0.22],
  thock:  [0.12, (t) => (Math.sin(2 * Math.PI * (300 - 600 * t) * t) + noise() * 0.3) * Math.exp(-t * 45) * 0.5],
};

for (const c of cues) {
  if (!VOICES[c.type]) throw new Error('unknown cue type ' + c.type + ' (have: ' + Object.keys(VOICES) + ')');
  const [len, fn] = VOICES[c.type];
  const start = Math.floor(c.t * SR);
  for (let i = 0; i < len * SR && start + i < buf.length; i++) buf[start + i] += fn(i / SR);
}

const n = buf.length, b = Buffer.alloc(44 + n * 2);
b.write('RIFF', 0); b.writeUInt32LE(36 + n * 2, 4); b.write('WAVEfmt ', 8);
b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22);
b.writeUInt32LE(SR, 24); b.writeUInt32LE(SR * 2, 28); b.writeUInt16LE(2, 32); b.writeUInt16LE(16, 34);
b.write('data', 36); b.writeUInt32LE(n * 2, 40);
for (let i = 0; i < n; i++) b.writeInt16LE(Math.round(Math.max(-1, Math.min(1, buf[i])) * 32767), 44 + i * 2);
writeFileSync(process.argv[3], b);
console.log('wrote', process.argv[3], (n / SR).toFixed(2) + 's');
