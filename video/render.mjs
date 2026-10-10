// node render.mjs [--fps 60] [--dur 6] [--sub 4] [--w 1080] [--h 1920] [--from 0] [--to DUR]
//                 [--out out/silent.mp4] [--page index.html]
// Walks time, calls window.seek(t) in headless Chromium, pipes PNG frames into ffmpeg.
// --sub N renders N subframes per frame and averages them (motion blur). --sub 1 for fast previews.
// --from/--to render a slice (seconds) so one shot can be re-rendered after a fix.
// --w/--h set the viewport; index.html reads the canvas size and lays out per format.
import { chromium } from 'playwright';
import { spawn } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const arg = (k, d) => { const i = process.argv.indexOf('--' + k); return i > 0 ? process.argv[i + 1] : d; };
import { createRequire } from 'node:module';
const FPS = +arg('fps', 60), DUR = +arg('dur', createRequire(import.meta.url)('./timeline.js').DUR), SUB = +arg('sub', 4);
const W = +arg('w', 1080), H = +arg('h', 1920);
const FROM = +arg('from', 0), TO = +arg('to', DUR);
const OUT = arg('out', 'out/silent.mp4'), PAGE = resolve(arg('page', 'index.html'));
mkdirSync(dirname(OUT), { recursive: true });

const browser = await chromium.launch({ args: ['--allow-file-access-from-files'] });
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
await page.goto('file://' + PAGE);
page.on('console', (m) => console.log('page:', m.text()));
page.on('pageerror', (e) => { console.error('page error:', e.message); process.exit(1); });
await page.evaluate(() => window.READY);               // fonts + icon loaded before frame 0

// --stills 0.5,3,6 writes out/stills/<t>.png instead of a video (fast contact sheets).
const STILLS = arg('stills', '');
if (STILLS) {
  mkdirSync('out/stills', { recursive: true });
  for (const t of STILLS.split(',').map(Number)) {
    await page.evaluate((t) => window.seek(t), t);
    await page.locator('canvas').screenshot({ path: `out/stills/${t.toFixed(2).padStart(5, '0')}.png` });
  }
  await browser.close(); console.log('stills', STILLS); process.exit(0);
}

// tmix averages SUB consecutive subframes; select keeps the last of each group.
const vf = SUB > 1
  ? `tmix=frames=${SUB},select='eq(mod(n\\,${SUB})\\,${SUB - 1})',setpts=N/${FPS}/TB`
  : `setpts=N/${FPS}/TB`;
const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS * SUB), '-i', '-',
  '-vf', vf, '-r', String(FPS), '-c:v', 'libx264', '-crf', '16', '-pix_fmt', 'yuv420p', OUT],
  { stdio: ['pipe', 'inherit', 'inherit'] });

const first = Math.round(FROM * FPS * SUB), last = Math.round(TO * FPS * SUB);
for (let i = first; i < last; i++) {
  await page.evaluate((t) => window.seek(t), i / (FPS * SUB));
  const png = await page.locator('canvas').screenshot({ type: 'png' });
  if (!ff.stdin.write(png)) await new Promise((r) => ff.stdin.once('drain', r));
  if (i % (FPS * SUB) === 0) console.log(`rendered ${i / (FPS * SUB)}s / ${TO}s`);
}
ff.stdin.end();
await new Promise((r) => ff.on('close', r));
await browser.close();
console.log('wrote', OUT, `${W}x${H}`, `${FROM}s-${TO}s`);
