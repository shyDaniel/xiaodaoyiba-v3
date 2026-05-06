#!/usr/bin/env node
// scripts/gen-mountain-composite.mjs — S-439 §H2.5 textured mountain
// composite. Loads the Kenney "Background Elements" pointy_mountains
// silhouette PNG (CC0) and bakes ridge highlights + snow caps + valley
// shadows + mid-tone shading into it so the live frame's left-edge
// mountain region exhibits ≥6 distinct hue clusters instead of the
// flat blue-grey ≤3-cluster polygon that has shipped for 6 prior
// iterations.
//
// Output (deterministic, idempotent — re-running produces byte-identical PNGs):
//   client/assets/sprites/3rd-party/composites/mountain_back.png
//     — wider, paler, more atmospheric range (background parallax layer)
//   client/assets/sprites/3rd-party/composites/mountain_front.png
//     — narrower, deeper-toned ridge with crisp snow caps (foreground layer)
//
// The §I.0 ban is on `client/scripts/**` `draw_line/circle/rect/polygon
// /set_pixel` runtime calls. This is a build-time Node script that
// produces PNG environment art from a CC0 silhouette mask — same
// pattern as the existing scripts/gen-3rd-party-composites.mjs and
// scripts/gen-ui-art.mjs (which the §I.0 grep filter already excludes
// via path).
//
// Per-pixel recipe (single pass over the silhouette mask):
//   1. Load pointy_mountains.png; treat alpha>0 pixels as "mountain".
//   2. For each mountain column, find its top row (peak in that column)
//      and bottom row of the silhouette (the horizon line).
//   3. Per mountain pixel, compute relative_height = (y_bot - y) /
//      (y_bot - y_top_col). 0 = valley, 1 = peak.
//   4. Sample a 6-stop palette ramp keyed on relative_height:
//        0.00..0.18  valley_shadow  (deepest blue-grey)
//        0.18..0.40  base_lower     (mid blue-grey)
//        0.40..0.62  base_upper     (slightly lighter, slightly warmer)
//        0.62..0.78  ridge          (warmed lavender-grey highlight)
//        0.78..0.92  snow_dirty     (off-white with blue undertone)
//        0.92..1.00  snow_pure      (near-white peak cap)
//   5. Add a 1-pixel left-side ridge highlight (lighter than base) every
//      column where the silhouette transitions UP — mimics light coming
//      from the upper-left in classic Stardew/Pokemon overworlds.
//   6. Background variant uses the same recipe but desaturated +25%
//      lighter overall (atmospheric perspective).
//
// Result: ≥6 hue clusters (the 6 ramp stops) within any horizontal
// slice of the rendered mountain — quantitatively measurable by
// scripts/check-aesthetic-coverage.py.

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { deflateSync } from 'node:zlib';
import { PNG } from 'pngjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');
const SRC_PNG = resolve(
  ROOT,
  'client/assets/sprites/3rd-party/kenney_background-elements/pointy_mountains.png',
);
const OUT_DIR = resolve(ROOT, 'client/assets/sprites/3rd-party/composites');
mkdirSync(OUT_DIR, { recursive: true });

// ── PNG codec ──────────────────────────────────────────────────────────────
function crc32() {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return (buf) => {
    let c = 0xffffffff;
    for (let i = 0; i < buf.length; i++) c = t[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
}
const CRC = crc32();
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0);
  const t = Buffer.from(type, 'ascii');
  const td = Buffer.concat([t, data]);
  const cb = Buffer.alloc(4); cb.writeUInt32BE(CRC(td), 0);
  return Buffer.concat([len, td, cb]);
}
function encodePng(w, h, rgba) {
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const stride = w * 4;
  const raw = Buffer.alloc((stride + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (stride + 1)] = 0;
    for (let x = 0; x < stride; x++) raw[y * (stride + 1) + 1 + x] = rgba[y * stride + x];
  }
  return Buffer.concat([
    sig,
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// ── Load CC0 silhouette mask ───────────────────────────────────────────────
const srcBuf = readFileSync(SRC_PNG);
const srcPng = PNG.sync.read(srcBuf);
const SW = srcPng.width;
const SH = srcPng.height;
const src = new Uint8Array(srcPng.data);
process.stderr.write(`[gen-mountain] source ${SW}×${SH}\n`);

// Build column->topRow map and a global horizon row.
function isMaskPx(x, y) {
  if (x < 0 || y < 0 || x >= SW || y >= SH) return false;
  return src[(y * SW + x) * 4 + 3] > 8;
}
const topPerCol = new Int32Array(SW).fill(-1);
let globalBottom = 0;
for (let x = 0; x < SW; x++) {
  for (let y = 0; y < SH; y++) {
    if (isMaskPx(x, y)) {
      topPerCol[x] = y;
      break;
    }
  }
  // Bottom of silhouette in this column
  for (let y = SH - 1; y >= 0; y--) {
    if (isMaskPx(x, y)) {
      if (y > globalBottom) globalBottom = y;
      break;
    }
  }
}

// Helper: for each peak (local minima in topPerCol) build a list with
// (peak_x, peak_y) so we can detect "near a peak" for snow cap weighting.
const peaks = [];
for (let x = 1; x < SW - 1; x++) {
  const y = topPerCol[x];
  if (y < 0) continue;
  const yl = topPerCol[x - 1] >= 0 ? topPerCol[x - 1] : y;
  const yr = topPerCol[x + 1] >= 0 ? topPerCol[x + 1] : y;
  if (y <= yl && y <= yr) peaks.push([x, y]);
}
process.stderr.write(`[gen-mountain] detected ${peaks.length} peaks\n`);

// ── Palette ramps (Endesga 32-leaning, cool blue-grey through warm
// snow-tinted off-white). Six distinct hue clusters per ramp ensures
// the §H2.5 acceptance gate passes by construction.
function rgb(r, g, b) { return [r, g, b]; }

// FRONT (foreground) ramp — saturated, deeper shadows, sharp snow.
const RAMP_FRONT = [
  // [maxRelHeight, r, g, b]
  [0.18, ...rgb( 38,  46,  72)], // valley shadow      (deepest)
  [0.40, ...rgb( 64,  80, 110)], // base lower
  [0.62, ...rgb( 96, 116, 148)], // base upper
  [0.78, ...rgb(146, 156, 184)], // ridge highlight    (lavender-warm)
  [0.92, ...rgb(208, 216, 232)], // dirty snow
  [1.01, ...rgb(248, 250, 255)], // pure snow cap
];
// Optional accent: warm dawn-light kiss on the lit side of every peak.
const RIDGE_KISS = rgb(196, 180, 168);

// BACK (parallax, atmospheric) ramp — desaturated +18% lighter, more
// haze-blue. Same number of stops so the back layer still contributes
// hue clusters even when the front is offscreen / partially covered.
const RAMP_BACK = [
  [0.18, ...rgb( 88,  98, 124)],
  [0.40, ...rgb(112, 124, 152)],
  [0.62, ...rgb(140, 152, 178)],
  [0.78, ...rgb(170, 182, 204)],
  [0.92, ...rgb(212, 222, 236)],
  [1.01, ...rgb(244, 248, 255)],
];

function rampPick(ramp, t) {
  for (const stop of ramp) {
    if (t < stop[0]) return [stop[1], stop[2], stop[3]];
  }
  return [ramp[ramp.length - 1][1], ramp[ramp.length - 1][2], ramp[ramp.length - 1][3]];
}

// ── Compose ────────────────────────────────────────────────────────────────
function compose(ramp, opts = {}) {
  const W = SW;
  const H = SH;
  const out = new Uint8Array(W * H * 4);
  const lighter = opts.lighter || 0; // 0..1 lerp toward white
  const desat = opts.desat || 0;     // 0..1 lerp toward grey

  // First pass: ramp-shaded body.
  for (let x = 0; x < W; x++) {
    const yTop = topPerCol[x];
    if (yTop < 0) continue;
    // Find this column's bottom (inside silhouette)
    let yBot = yTop;
    for (let y = H - 1; y >= yTop; y--) {
      if (isMaskPx(x, y)) { yBot = y; break; }
    }
    const span = Math.max(1, yBot - yTop);
    for (let y = yTop; y <= yBot; y++) {
      if (!isMaskPx(x, y)) continue;
      const rel = (yBot - y) / span;
      let [r, g, b] = rampPick(ramp, rel);
      if (lighter > 0) {
        r = Math.round(r + (255 - r) * lighter);
        g = Math.round(g + (255 - g) * lighter);
        b = Math.round(b + (255 - b) * lighter);
      }
      if (desat > 0) {
        const grey = Math.round(0.299 * r + 0.587 * g + 0.114 * b);
        r = Math.round(r + (grey - r) * desat);
        g = Math.round(g + (grey - g) * desat);
        b = Math.round(b + (grey - b) * desat);
      }
      const i = (y * W + x) * 4;
      out[i] = r; out[i + 1] = g; out[i + 2] = b; out[i + 3] = 255;
    }
  }

  // Second pass: 1-pixel ridge highlight on the LIT (left) face of each
  // upward silhouette transition. Detect: yTop[x] < yTop[x-1], i.e. this
  // column's peak is higher than the previous one — paint the topmost
  // pixel of this column lighter to suggest sun-from-upper-left.
  for (let x = 1; x < W; x++) {
    const yTop = topPerCol[x];
    const yPrev = topPerCol[x - 1];
    if (yTop < 0) continue;
    if (yPrev < 0 || yTop < yPrev) {
      // Lit face — push the top 3 pixels toward RIDGE_KISS.
      for (let dy = 0; dy < 3; dy++) {
        const yy = yTop + dy;
        if (!isMaskPx(x, yy)) break;
        const i = (yy * W + x) * 4;
        const blend = dy === 0 ? 0.55 : (dy === 1 ? 0.30 : 0.15);
        out[i]     = Math.round(out[i]     * (1 - blend) + RIDGE_KISS[0] * blend);
        out[i + 1] = Math.round(out[i + 1] * (1 - blend) + RIDGE_KISS[1] * blend);
        out[i + 2] = Math.round(out[i + 2] * (1 - blend) + RIDGE_KISS[2] * blend);
        out[i + 3] = 255;
      }
    }
  }

  // Third pass: snow-cap accent — for each detected peak, paint a
  // small snow triangle (4 px tall, 6 px wide) of the brightest ramp
  // stop. This guarantees the "snow cap" hue cluster reaches the
  // brightness of pure white-ish, even on shallow peaks where the
  // ramp's top stop wouldn't otherwise be hit.
  const snow = ramp[ramp.length - 1];
  for (const [px, py] of peaks) {
    for (let dy = 0; dy < 4; dy++) {
      const yy = py + dy;
      const halfW = 4 - dy;
      for (let dx = -halfW; dx <= halfW; dx++) {
        const xx = px + dx;
        if (!isMaskPx(xx, yy)) continue;
        const i = (yy * W + xx) * 4;
        // Lerp toward snow stop with falloff so we don't lose all
        // existing hue variation in the cap region.
        const k = 1 - (dy / 4) * 0.4;
        out[i]     = Math.round(out[i]     * (1 - k) + snow[1] * k);
        out[i + 1] = Math.round(out[i + 1] * (1 - k) + snow[2] * k);
        out[i + 2] = Math.round(out[i + 2] * (1 - k) + snow[3] * k);
        out[i + 3] = 255;
      }
    }
  }

  // Fourth pass: shadow side (right of each peak, opposite of lit face)
  // — push the topmost 2 pixels toward the deepest valley_shadow stop
  // so the contrast across the ridge line is visible.
  const valley = ramp[0];
  for (let x = 1; x < W - 1; x++) {
    const yTop = topPerCol[x];
    const yNext = topPerCol[x + 1];
    if (yTop < 0 || yNext < 0) continue;
    if (yNext > yTop) {
      // We just passed a peak going right — shadow side.
      for (let dy = 0; dy < 2; dy++) {
        const yy = yTop + dy + 1;
        if (!isMaskPx(x, yy)) break;
        const i = (yy * W + x) * 4;
        const blend = dy === 0 ? 0.30 : 0.15;
        out[i]     = Math.round(out[i]     * (1 - blend) + valley[1] * blend);
        out[i + 1] = Math.round(out[i + 1] * (1 - blend) + valley[2] * blend);
        out[i + 2] = Math.round(out[i + 2] * (1 - blend) + valley[3] * blend);
        out[i + 3] = 255;
      }
    }
  }

  return { w: W, h: H, rgba: out };
}

// ── Render & save ──────────────────────────────────────────────────────────
const front = compose(RAMP_FRONT);
const back = compose(RAMP_BACK, { lighter: 0.18, desat: 0.40 });

writeFileSync(resolve(OUT_DIR, 'mountain_front.png'), encodePng(front.w, front.h, Buffer.from(front.rgba)));
writeFileSync(resolve(OUT_DIR, 'mountain_back.png'), encodePng(back.w, back.h, Buffer.from(back.rgba)));

// ── Self-check: count distinct hue clusters in the front composite ─────────
function quantize(r, g, b) {
  // Bin to 5-bits per channel (32 buckets per axis) so neighbouring
  // ramp colours collapse into the same bucket — anti-noise.
  return (r >> 4 << 8) | (g >> 4 << 4) | (b >> 4);
}
const buckets = new Set();
for (let i = 0; i < front.rgba.length; i += 4) {
  if (front.rgba[i + 3] === 0) continue;
  buckets.add(quantize(front.rgba[i], front.rgba[i + 1], front.rgba[i + 2]));
}
process.stderr.write(`[gen-mountain] front composite distinct hue buckets = ${buckets.size}\n`);
if (buckets.size < 6) {
  console.error(`[gen-mountain] FAIL: only ${buckets.size} hue buckets, need ≥6`);
  process.exit(1);
}
process.stderr.write(`[gen-mountain] wrote ${OUT_DIR}/mountain_front.png + mountain_back.png\n`);
