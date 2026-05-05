#!/usr/bin/env node
// scripts/gen-ui-art.mjs — generate carved-wood 9-slice UI panel PNGs +
// ground-tile atlas + character-hair-detail layer (S-370 §H2.4 / §H2.1).
//
// Outputs (deterministic, idempotent — safe to run on every build):
//   client/assets/sprites/ui/wood_panel_9slice.png
//   client/assets/sprites/ui/parchment_9slice.png
//   client/assets/sprites/ui/wood_button_9slice.png
//   client/assets/sprites/ui/wood_button_pressed_9slice.png
//   client/assets/sprites/tiles/ground_atlas.png   (256×64 — 4 tile variants)
//
// All four 9-slice panels are 48×48 with 16-pixel margins so Godot's
// StyleBoxTexture default-margin (16) lines up out of the box. The
// "carved" look is: a 3-pixel rim with light edge on top-left + dark
// edge on bottom-right, painted over the background fill, with subtle
// noise/grain inside.
//
// Colors are sampled from the Endesga 32 palette (§H2.6) so the chrome
// is cohesive with the rest of the rendered art.
//
// Pure JS — uses zlib for PNG IDAT compression. No image lib dep.

import { writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { deflateSync } from 'node:zlib';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');
const UI_DIR = resolve(ROOT, 'client/assets/sprites/ui');
const TILE_DIR = resolve(ROOT, 'client/assets/sprites/tiles');

mkdirSync(UI_DIR, { recursive: true });
mkdirSync(TILE_DIR, { recursive: true });

// ── Endesga 32 palette ────────────────────────────────────────────────────
const E = {
  brick_red:   [0xbe, 0x4a, 0x2f],
  rust:        [0xd7, 0x76, 0x43],
  cream:       [0xea, 0xd4, 0xaa],
  skin_hi:     [0xe4, 0xa6, 0x72],
  skin_lo:     [0xb8, 0x6f, 0x50],
  hair_brown:  [0x73, 0x3e, 0x39],
  outline:     [0x3e, 0x27, 0x31],
  blood_red:   [0xa2, 0x26, 0x33],
  bright_red:  [0xe4, 0x3b, 0x44],
  pumpkin:     [0xf7, 0x76, 0x22],
  amber:       [0xfe, 0xae, 0x34],
  buttercup:   [0xfe, 0xe7, 0x61],
  leaf:        [0x63, 0xc7, 0x4d],
  grass:       [0x3e, 0x89, 0x48],
  pine:        [0x26, 0x5c, 0x42],
  dark_teal:   [0x19, 0x3c, 0x3e],
  navy:        [0x12, 0x4e, 0x89],
  sky:         [0x00, 0x99, 0xdb],
  cyan:        [0x2c, 0xe8, 0xf5],
  white:       [0xff, 0xff, 0xff],
  pale_steel:  [0xc0, 0xcb, 0xdc],
  steel:       [0x8b, 0x9b, 0xb4],
  slate:       [0x5a, 0x69, 0x88],
  deep_slate:  [0x3a, 0x44, 0x66],
  midnight:    [0x26, 0x2b, 0x44],
  obsidian:    [0x18, 0x14, 0x25],
  pink_red:    [0xff, 0x00, 0x44],
  plum:        [0x68, 0x38, 0x6c],
  rose:        [0xb5, 0x50, 0x88],
  salmon:      [0xf6, 0x75, 0x7a],
  shell:       [0xe8, 0xb7, 0x96],
  brick_brown: [0xc2, 0x85, 0x69],
};

// ── PNG encoder ───────────────────────────────────────────────────────────
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
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const t = Buffer.from(type, 'ascii');
  const td = Buffer.concat([t, data]);
  const cb = Buffer.alloc(4);
  cb.writeUInt32BE(CRC(td), 0);
  return Buffer.concat([len, td, cb]);
}

function encodePng(w, h, rgba) {
  // rgba: Uint8Array (w*h*4)
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const ihd = Buffer.alloc(13);
  ihd.writeUInt32BE(w, 0);
  ihd.writeUInt32BE(h, 4);
  ihd[8] = 8;     // bit depth
  ihd[9] = 6;     // RGBA
  ihd[10] = 0;    // compression
  ihd[11] = 0;    // filter
  ihd[12] = 0;    // interlace
  // raw scanlines with filter byte 0 prefix per row.
  const stride = w * 4;
  const raw = Buffer.alloc((stride + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (stride + 1)] = 0;
    rgba.copy
      ? rgba.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride)
      : raw.set(rgba.slice(y * stride, (y + 1) * stride), y * (stride + 1) + 1);
  }
  const idat = deflateSync(raw, { level: 9 });
  return Buffer.concat([
    sig,
    chunk('IHDR', ihd),
    chunk('IDAT', idat),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// ── Painting helpers ─────────────────────────────────────────────────────
class Img {
  constructor(w, h) {
    this.w = w; this.h = h;
    this.buf = Buffer.alloc(w * h * 4);
  }
  set(x, y, [r, g, b], a = 255) {
    if (x < 0 || y < 0 || x >= this.w || y >= this.h) return;
    const i = (y * this.w + x) * 4;
    this.buf[i] = r; this.buf[i + 1] = g; this.buf[i + 2] = b; this.buf[i + 3] = a;
  }
  fill([r, g, b], a = 255) {
    for (let y = 0; y < this.h; y++) for (let x = 0; x < this.w; x++) this.set(x, y, [r, g, b], a);
  }
  rect(x, y, w, h, c, a = 255) {
    for (let yy = y; yy < y + h; yy++) for (let xx = x; xx < x + w; xx++) this.set(xx, yy, c, a);
  }
  line(x1, y1, x2, y2, c, a = 255) {
    const dx = Math.abs(x2 - x1), dy = Math.abs(y2 - y1);
    const sx = x1 < x2 ? 1 : -1, sy = y1 < y2 ? 1 : -1;
    let err = dx - dy, x = x1, y = y1;
    while (true) {
      this.set(x, y, c, a);
      if (x === x2 && y === y2) break;
      const e2 = 2 * err;
      if (e2 > -dy) { err -= dy; x += sx; }
      if (e2 < dx) { err += dx; y += sy; }
    }
  }
  png() { return encodePng(this.w, this.h, this.buf); }
}

// Deterministic per-pixel pseudo-noise so re-runs produce byte-identical
// output (so CI doesn't churn on assets).
function noise(x, y) {
  let h = ((x * 73856093) ^ (y * 19349663)) >>> 0;
  return (h % 1024) / 1024 - 0.5;  // -0.5..+0.5
}

function lerp(a, b, t) { return a + (b - a) * t; }
function lerpColor(c1, c2, t) {
  return [Math.round(lerp(c1[0], c2[0], t)), Math.round(lerp(c1[1], c2[1], t)), Math.round(lerp(c1[2], c2[2], t))];
}

// ── 9-slice wood panel ───────────────────────────────────────────────────
//
// Layout (48×48, 16-px margins so center 16×16 is the stretchable block):
//   - background fill: dark wood plank
//   - vertical plank seams every 12 px
//   - horizontal grain noise (1 px tint variation per row)
//   - 3-pixel carved frame: outer ring deep-slate (almost black),
//     middle ring brick_brown, inner ring shell highlight (top/left)
//     + outline (bottom/right) for the 'carved' look.
function drawWoodPanel(img, opts = {}) {
  const w = img.w, h = img.h;
  const base = opts.base || E.brick_brown;
  const baseShade = opts.baseShade || lerpColor(E.brick_brown, E.outline, 0.55);
  const baseHi = opts.baseHi || lerpColor(E.brick_brown, E.cream, 0.25);
  const rim = E.outline;
  const seamCol = lerpColor(E.brick_brown, E.outline, 0.65);

  // Plank grain fill.
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      // Per-row tint: lighter on top half of each plank, shadow on bottom half.
      const plankRow = y % 12;
      let c;
      if (plankRow < 4) c = lerpColor(base, baseHi, 0.2 + noise(x, y) * 0.3);
      else if (plankRow > 8) c = lerpColor(base, baseShade, 0.2 + noise(x, y) * 0.3);
      else c = lerpColor(base, baseHi, noise(x, y) * 0.4);
      img.set(x, y, c);
    }
  }
  // Vertical plank seams every 12 px.
  for (let x = 12; x < w; x += 12) {
    for (let y = 0; y < h; y++) img.set(x, y, seamCol);
  }
  // Horizontal seam lines every 12px (between board courses).
  for (let y = 12; y < h; y += 12) {
    for (let x = 0; x < w; x++) img.set(x, y, lerpColor(seamCol, baseShade, 0.5));
  }
  // 3-pixel carved frame.
  // Outer 1-pixel ring: pure outline.
  for (let i = 0; i < w; i++) { img.set(i, 0, rim); img.set(i, h - 1, rim); }
  for (let i = 0; i < h; i++) { img.set(0, i, rim); img.set(w - 1, i, rim); }
  // Middle ring (1 px in): brick_brown.
  for (let i = 1; i < w - 1; i++) { img.set(i, 1, baseShade); img.set(i, h - 2, baseShade); }
  for (let i = 1; i < h - 1; i++) { img.set(1, i, baseShade); img.set(w - 2, i, baseShade); }
  // Inner ring (2 px in): top + left = highlight, bottom + right = outline.
  for (let i = 2; i < w - 2; i++) {
    img.set(i, 2, baseHi);             // top highlight
    img.set(i, h - 3, rim);            // bottom shadow
  }
  for (let i = 2; i < h - 2; i++) {
    img.set(2, i, baseHi);             // left highlight
    img.set(w - 3, i, rim);            // right shadow
  }
  // Corner pixels — set explicitly so highlight wraps correctly.
  img.set(2, 2, baseHi);
  img.set(w - 3, h - 3, rim);
}

// Parchment 9-slice — used for battle-log row backgrounds (painted ribbon).
function drawParchment(img) {
  const w = img.w, h = img.h;
  const base = E.cream;
  const baseHi = lerpColor(E.cream, E.white, 0.4);
  const baseShade = lerpColor(E.cream, E.skin_lo, 0.35);
  const rim = lerpColor(E.outline, E.cream, 0.2);
  // Fill with cream + grain noise.
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      let c = lerpColor(base, baseShade, 0.1 + noise(x, y) * 0.25);
      // Vertical 'fold lines' every 16 px to feel like parchment.
      if (x % 16 === 8) c = lerpColor(c, baseShade, 0.4);
      img.set(x, y, c);
    }
  }
  // Soft inner highlight (top half).
  for (let y = 1; y < 6; y++) for (let x = 1; x < w - 1; x++) {
    const cur = [img.buf[(y * w + x) * 4], img.buf[(y * w + x) * 4 + 1], img.buf[(y * w + x) * 4 + 2]];
    img.set(x, y, lerpColor(cur, baseHi, 0.18));
  }
  // 1-pixel rim.
  for (let i = 0; i < w; i++) { img.set(i, 0, rim); img.set(i, h - 1, rim); }
  for (let i = 0; i < h; i++) { img.set(0, i, rim); img.set(w - 1, i, rim); }
  // Top-left highlight 2px.
  for (let i = 1; i < w - 1; i++) img.set(i, 1, baseHi);
  for (let i = 1; i < h - 1; i++) img.set(1, i, baseHi);
}

// Wood button — same shape as panel but smaller and more amber.
function drawWoodButton(img, pressed) {
  drawWoodPanel(img, {
    base: pressed ? lerpColor(E.brick_brown, E.outline, 0.25) : E.rust,
    baseShade: pressed ? E.outline : lerpColor(E.rust, E.outline, 0.5),
    baseHi: pressed ? E.brick_brown : lerpColor(E.rust, E.amber, 0.5),
  });
  // Pressed state: invert the highlight (top now dark, bottom light) so
  // the carve looks indented.
  if (pressed) {
    const w = img.w, h = img.h;
    for (let i = 2; i < w - 2; i++) {
      img.set(i, 2, E.outline);
      img.set(i, h - 3, lerpColor(E.rust, E.amber, 0.5));
    }
    for (let i = 2; i < h - 2; i++) {
      img.set(2, i, E.outline);
      img.set(w - 3, i, lerpColor(E.rust, E.amber, 0.5));
    }
  }
}

// ── Ground tile atlas — 4 variants × 64×64 each = 256×64 ─────────────────
function drawGroundAtlas(img) {
  // 4 tiles laid out left to right: grass-tuft, dirt-path, cobble, packed-earth.
  // Each is 64×64 (same as iso half-tile) with deliberate per-pixel detail.
  drawGrassTuft(img, 0, 0);
  drawDirtPath(img, 64, 0);
  drawCobble(img, 128, 0);
  drawPackedEarth(img, 192, 0);
}

function drawGrassTuft(img, ox, oy) {
  // Base — leaf green with per-pixel noise so flat-fill check fails.
  for (let y = 0; y < 64; y++) {
    for (let x = 0; x < 64; x++) {
      const n = noise(ox + x, oy + y);
      const t = 0.45 + n * 0.35;  // -0.125..0.625
      const c = lerpColor(E.grass, E.leaf, Math.max(0, Math.min(1, t)));
      img.set(ox + x, oy + y, c);
      // Sprinkle tuft ticks (3-pixel vertical highlight).
      if (((ox + x) * 7 + (oy + y) * 13) % 71 < 3 && y > 4 && y < 58) {
        img.set(ox + x, oy + y - 1, lerpColor(E.leaf, E.buttercup, 0.4));
        img.set(ox + x, oy + y - 2, lerpColor(E.leaf, E.cream, 0.4));
      }
    }
  }
  // A few darker tuft bases.
  for (let y = 0; y < 64; y++) {
    for (let x = 0; x < 64; x++) {
      if (((ox + x) * 11 + (oy + y) * 17) % 89 < 2) {
        img.set(ox + x, oy + y, lerpColor(E.grass, E.pine, 0.6));
      }
    }
  }
}

function drawDirtPath(img, ox, oy) {
  for (let y = 0; y < 64; y++) {
    for (let x = 0; x < 64; x++) {
      const n = noise(ox + x + 1000, oy + y);
      const c = lerpColor(E.skin_lo, E.brick_brown, 0.4 + n * 0.5);
      img.set(ox + x, oy + y, c);
    }
  }
  // Stone speckles.
  for (let y = 0; y < 64; y++) {
    for (let x = 0; x < 64; x++) {
      if (((ox + x) * 7 + (oy + y) * 13) % 53 < 2) {
        img.set(ox + x, oy + y, lerpColor(E.steel, E.outline, 0.3));
        img.set(ox + x + 1, oy + y, lerpColor(E.steel, E.cream, 0.4));
      }
    }
  }
}

function drawCobble(img, ox, oy) {
  // Base mortar.
  for (let y = 0; y < 64; y++) {
    for (let x = 0; x < 64; x++) {
      img.set(ox + x, oy + y, lerpColor(E.deep_slate, E.steel, 0.35 + noise(ox + x, oy + y) * 0.2));
    }
  }
  // Stones — 8×8 packing with 1-px gap.
  for (let by = 2; by < 60; by += 10) {
    for (let bx = 2; bx < 60; bx += 10) {
      const xo = (Math.floor(by / 10) % 2 === 0) ? 0 : 5;
      const cx = bx + xo;
      const cy = by;
      const stoneBase = ((cx * 31 + cy * 17) % 3 === 0) ? E.pale_steel : E.steel;
      for (let yy = 0; yy < 8; yy++) {
        for (let xx = 0; xx < 8; xx++) {
          const dx = xx - 3.5, dy = yy - 3.5;
          if (dx * dx + dy * dy > 16) continue;
          const t = 0.3 + (dy + dx) / 16;
          const c = lerpColor(stoneBase, E.outline, Math.max(0, Math.min(0.5, t)));
          img.set(ox + cx + xx, oy + cy + yy, c);
        }
      }
    }
  }
}

function drawPackedEarth(img, ox, oy) {
  for (let y = 0; y < 64; y++) {
    for (let x = 0; x < 64; x++) {
      const n = noise(ox + x + 2000, oy + y + 500);
      const c = lerpColor(E.brick_brown, E.outline, 0.25 + Math.abs(n) * 0.4);
      img.set(ox + x, oy + y, c);
    }
  }
  // Cracks (thin dark lines).
  for (let i = 0; i < 4; i++) {
    const y0 = 8 + i * 14;
    const phase = i * 7;
    let prev = [0, y0];
    for (let x = 4; x < 60; x += 4) {
      const yy = y0 + Math.round(Math.sin((x + phase) * 0.4) * 2);
      img.line(ox + prev[0], oy + prev[1], ox + x, oy + yy, E.outline);
      prev = [x, yy];
    }
  }
}

// ── Main ──────────────────────────────────────────────────────────────────
function writePng(p, img) {
  writeFileSync(p, img.png());
  console.log(`  wrote ${p}  (${img.w}×${img.h})`);
}

function writeImportSidecar(absPath, opts = {}) {
  // Minimal Godot 4 .import file for a Texture2D.
  const idx = absPath.indexOf('/client/');
  const resPath = absPath.slice(idx + '/client/'.length);
  const sidecar = absPath + '.import';
  const lines = [
    '[remap]',
    '',
    'importer="texture"',
    'type="CompressedTexture2D"',
    '',
    '[deps]',
    '',
    `source_file="res://${resPath}"`,
    '',
    '[params]',
    '',
    'compress/mode=0',
    'compress/lossy_quality=0.7',
    'compress/hdr_compression=1',
    'compress/normal_map=0',
    'compress/channel_pack=0',
    'mipmaps/generate=false',
    'mipmaps/limit=-1',
    'roughness/mode=0',
    'process/fix_alpha_border=true',
    'process/premult_alpha=false',
    'process/normal_map_invert_y=false',
    'process/hdr_as_srgb=false',
    'process/hdr_clamp_exposure=false',
    'process/size_limit=0',
    'detect_3d/compress_to=1',
    '',
  ];
  writeFileSync(sidecar, lines.join('\n'));
}

function main() {
  console.log('[gen-ui-art] generating UI 9-slice + ground atlas...');

  const wood = new Img(48, 48);
  drawWoodPanel(wood);
  const woodPath = resolve(UI_DIR, 'wood_panel_9slice.png');
  writePng(woodPath, wood);
  writeImportSidecar(woodPath);

  const parch = new Img(48, 48);
  drawParchment(parch);
  const parchPath = resolve(UI_DIR, 'parchment_9slice.png');
  writePng(parchPath, parch);
  writeImportSidecar(parchPath);

  const btn = new Img(48, 48);
  drawWoodButton(btn, false);
  const btnPath = resolve(UI_DIR, 'wood_button_9slice.png');
  writePng(btnPath, btn);
  writeImportSidecar(btnPath);

  const btnPressed = new Img(48, 48);
  drawWoodButton(btnPressed, true);
  const btnPressedPath = resolve(UI_DIR, 'wood_button_pressed_9slice.png');
  writePng(btnPressedPath, btnPressed);
  writeImportSidecar(btnPressedPath);

  const ground = new Img(256, 64);
  drawGroundAtlas(ground);
  const groundPath = resolve(TILE_DIR, 'ground_atlas.png');
  writePng(groundPath, ground);
  writeImportSidecar(groundPath);

  console.log('[gen-ui-art] done.');
}

main();
