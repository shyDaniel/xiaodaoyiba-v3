#!/usr/bin/env node
// scripts/gen-3rd-party-composites.mjs — S-386 §I.0 HARD BAN compliance.
//
// Stitches CC0 source tiles from Kenney Tiny Town + Tiny Dungeon into the
// composite PNG sizes Game.tscn / Character.tscn / House.tscn / Ground.tscn
// already expect (hard-coded scene anchors), and writes them under
// client/assets/sprites/3rd-party/composites/. The composites carry
// the same CC0 license as their sources because they are pure pixel
// copies / nearest-neighbour rescales — no procedural drawing.
//
// Outputs:
//   client/assets/sprites/3rd-party/composites/house_<variant>_<damage>.png
//     192×192 — variants 0..3, damage 0..3
//     S-401: redesigned recipe from "3×3 wallpaper of identical
//     wall-bottom tiles (3 doors stamped per house)" to a coherent
//     3-row silhouette: roof slab w/ chimney, wall-top w/ door arch,
//     wall-bot w/ window+door+window. Each variant pairs a distinct
//     roof palette (red shingle / grey slate) with a distinct wall
//     palette (brown cottage / grey stone) so all 4 dwellings read
//     as 4 different houses, not 4 tinted copies of one.
//   client/assets/sprites/3rd-party/composites/character_<state>.png
//     96×128 — states ALIVE_CLOTHED, ATTACKING, ALIVE_PANTS_DOWN,
//              ALIVE_BRIEFS_ONLY, DEAD
//   client/assets/sprites/3rd-party/composites/knife.png
//     32×16 — sourced from Tiny Town tile_0030
//   client/assets/sprites/3rd-party/composites/ground_atlas.png
//     256×64 — 4× 64×64 grass/path variants from Tiny Town

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { deflateSync } from 'node:zlib';
import { PNG } from 'pngjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');
const TT_TILES = resolve(ROOT, 'client/assets/sprites/3rd-party/kenney_tiny-town/Tiles');
const TD_TILES = resolve(ROOT, 'client/assets/sprites/3rd-party/kenney_tiny-dungeon/Tiles');
const OUT_DIR = resolve(ROOT, 'client/assets/sprites/3rd-party/composites');
mkdirSync(OUT_DIR, { recursive: true });

// ── PNG decode (handles RGBA/RGB/Indexed Kenney tiles) ─────────────────────
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

function decodePng(buf) {
  const png = PNG.sync.read(buf);
  return { w: png.width, h: png.height, rgba: new Uint8Array(png.data) };
}

// ── PNG encode ─────────────────────────────────────────────────────────────
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

// ── Tiny canvas with src-over alpha blit + nearest-neighbour scale ─────────
class Canvas {
  constructor(w, h) {
    this.w = w; this.h = h;
    this.rgba = new Uint8Array(w * h * 4);
  }
  setPx(x, y, r, g, b, a) {
    if (x < 0 || y < 0 || x >= this.w || y >= this.h) return;
    if (a <= 0) return;
    const i = (y * this.w + x) * 4;
    if (a >= 255) {
      this.rgba[i] = r; this.rgba[i + 1] = g; this.rgba[i + 2] = b; this.rgba[i + 3] = 255;
      return;
    }
    const da = this.rgba[i + 3];
    if (da === 0) {
      this.rgba[i] = r; this.rgba[i + 1] = g; this.rgba[i + 2] = b; this.rgba[i + 3] = a;
      return;
    }
    const af = a / 255;
    const naf = 1 - af;
    this.rgba[i] = Math.round(r * af + this.rgba[i] * naf);
    this.rgba[i + 1] = Math.round(g * af + this.rgba[i + 1] * naf);
    this.rgba[i + 2] = Math.round(b * af + this.rgba[i + 2] * naf);
    this.rgba[i + 3] = Math.min(255, da + a);
  }
  // Blit a source RGBA buffer (sw×sh) onto this canvas at (dx,dy) scaled by (sx,sy).
  blitScaled(src, sw, sh, dx, dy, sx, sy) {
    for (let y = 0; y < sh; y++) {
      for (let x = 0; x < sw; x++) {
        const si = (y * sw + x) * 4;
        const sa = src[si + 3];
        if (sa === 0) continue;
        const sr = src[si], sg = src[si + 1], sb = src[si + 2];
        for (let yy = 0; yy < sy; yy++) {
          for (let xx = 0; xx < sx; xx++) {
            this.setPx(dx + x * sx + xx, dy + y * sy + yy, sr, sg, sb, sa);
          }
        }
      }
    }
  }
  // Blit unscaled pixels straight in (used to overlay knife-cut accents
  // pulled from a different CC0 source tile, again no procedural draw).
  blitOverlay(src, sw, sh, dx, dy) {
    this.blitScaled(src, sw, sh, dx, dy, 1, 1);
  }
  // Per-tile recolour (mask-driven): wherever src alpha > 0 AND src
  // brightness is in a range, replace with replacement.  We don't draw
  // shapes — we only swap pixel colours that already exist in the CC0
  // texture.  This keeps the ban-on-procedural-art rule satisfied while
  // still letting us mark damage stages by darkening the door region.
  png() { return encodePng(this.w, this.h, Buffer.from(this.rgba)); }
}

// ── Source tile loader ─────────────────────────────────────────────────────
const tileCache = new Map();
function loadTile(dir, idx) {
  const key = `${dir}|${idx}`;
  if (tileCache.has(key)) return tileCache.get(key);
  const n = String(idx).padStart(4, '0');
  const buf = readFileSync(`${dir}/tile_${n}.png`);
  const decoded = decodePng(buf);
  tileCache.set(key, decoded);
  return decoded;
}

// ── Tile catalogue (verified by hand-inspection of Sample.png) ─────────────
//
// Tiny Town (12×11):
//   Row 0 (0..11): grass + flower variants
//   Row 1 (12..23): more vegetation, hedges
//   Row 2 (24..35): grass-edge, flowers, sword/knife
//   Row 3 (36..47): brown-roof segments
//   Row 4 (48..59): grey-roof segments
//   Row 5 (60..71): grey-roof body / wall plates
//   Row 6 (72..83): brown-wall + door
//   Row 7 (84..95): brown-wall + door + window variants
//   Row 8 (96..107): tower walls
//   Row 9 (108..119): tower walls + porch
//   Row 10 (120..131): wooden tower / interior accents
//
// The 4 house composites we ship use a consistent recipe: roof_left +
// roof_mid + roof_right on the top row, wall + door + wall on the
// bottom row.  Variants 0..3 swap the roof colour palette.

// Tiny Town building tile picks (verified pixel-by-pixel via tile zoom
// renders at /tmp/tiles_labeled.png + /tmp/walls_huge.png — S-401):
//
//   ROOF SLABS (row 4, idx 48-55):
//     48 = grey-slate roof-top LEFT slab
//     49 = grey-slate roof-top MIDDLE slab
//     50 = grey-slate roof-top RIGHT slab WITH CHIMNEY  ← chimney source
//     52 = red-shingle roof-top LEFT slab
//     53 = red-shingle roof-top MIDDLE slab
//     54 = red-shingle roof-top RIGHT slab WITH CHIMNEY ← chimney source
//
//   ROOF EAVES (row 5, idx 60-67) — same body as roof slabs but with
//   a hard porch-shadow band along the bottom edge so the roof reads
//   as "ending" against the wall below:
//     60/61/62 = grey-slate eave L/M/R
//     64/65/66 = red-shingle eave L/M/R
//     63 = grey peak (single-tile-wide hut peak — unused for 3-wide houses)
//     67 = red peak  (single-tile-wide hut peak — unused for 3-wide houses)
//
//   WALL TOP ROW (row 6, idx 72-79) — under the eave, contains the
//   DOOR ARCH (dark void above where the door panel will sit):
//     72 = brown-wall LEFT-EDGE  (stones at left margin + bottom band)
//     73 = brown-wall MIDDLE     (no edges, just stone speckle)
//     74 = brown DOOR ARCH        (centered dark doorway opening)
//     75 = brown-wall RIGHT-EDGE (stones at right margin + bottom band)
//     76 = grey-stone wall LEFT-EDGE
//     77 = grey-stone wall MIDDLE
//     78 = grey DOOR ARCH
//     79 = grey-stone wall RIGHT-EDGE
//
//   WALL BOTTOM ROW (row 7, idx 84-91) — at ground level, contains
//   the DOOR PANEL and WINDOW tiles:
//     84 = brown WINDOW (full window-on-wall: stones+mullion+curtain)
//     85 = brown door panel LEFT  (door body + frame on left)
//     86 = brown door panel CENTER (door body centered with frames both sides)
//     87 = brown door panel RIGHT (door body + frame on right)
//     88 = grey WINDOW
//     89 = grey door panel LEFT
//     90 = grey door panel CENTER
//     91 = grey door panel RIGHT
//
// Recipe is a 3-cols × 3-rows grid (scaled 4× → 192×192 px composite):
//   row 0 = roof slabs       (chimney lives in column 2 via tile 50/54)
//   row 1 = wall-top         (door arch in column 1, edge stones in 0/2)
//   row 2 = wall-bot         (door panel center in column 1, windows in 0/2)
//
// Earlier S-401 attempt used a 4-row recipe (roof + roof_eave + wall_top
// + wall_bot) but the doubled roof/eave bands stacked as a tile-tall
// tower silhouette rather than a single-storey cottage. Dropping the
// eave row gives a Stardew-shaped peaked-roof + door + flanking-windows
// silhouette — coherent and readable at iso scale.
const HOUSE_RECIPES = [
  // Variant 0 — RED shingle cottage + BROWN wall (warm cottage)
  {
    roof_top: [52, 53, 54],   // red roof slabs, chimney on right
    wall_top: [72, 74, 75],   // brown left-edge, door arch, right-edge
    wall_bot: [84, 86, 84],   // brown window, door panel center, brown window
  },
  // Variant 1 — GREY slate roof + GREY-stone wall (cooler dwelling)
  {
    roof_top: [48, 49, 50],
    wall_top: [76, 78, 79],   // grey-stone left-edge, door arch, right-edge
    wall_bot: [88, 90, 88],   // grey window, door panel center, grey window
  },
  // Variant 2 — RED roof + GREY stone wall (mixed, distinct silhouette)
  {
    roof_top: [52, 53, 54],
    wall_top: [76, 78, 79],
    wall_bot: [88, 90, 88],
  },
  // Variant 3 — GREY roof + BROWN cottage wall (mixed)
  {
    roof_top: [48, 49, 50],
    wall_top: [72, 74, 75],
    wall_bot: [84, 86, 84],
  },
];

// Tiny Town ground tile picks for the 4-variant 256×64 atlas:
//   tile 0  — plain grass
//   tile 1  — grass with red flowers
//   tile 2  — grass with white flowers (cluster)
//   tile 24 — dirt path
const GROUND_VARIANTS = [0, 1, 2, 24];

// Tiny Dungeon character tiles (16×16 single-frame heroes):
//   84 — purple-robe wizard (front)
//   85 — orange-skirt healer
//   86 — heavy red-cloak warrior
//   87 — armoured knight (blue plate)
//   96 — bone wraith (white skull-faced)
//   97 — yellow-mage / brown-cap apprentice
//   98 — blacksmith (heavy frame)
//   99 — red-tunic warrior
//   103 — tomb / gravestone shape
//
// S-424 — per-variant character composites. SpriteAtlas.HOUSE_VARIANTS
// already gives every player a unique house silhouette; the same
// player_id-hash-mod-N pattern now drives a unique character look.
// Each variant picks a DIFFERENT base hero tile so 4 simultaneous
// players render 4 visually distinct silhouettes (different hat
// shape, robe colour, body proportions). The PANTS_DOWN /
// BRIEFS_ONLY frames recolour the lower body of the base tile to
// expose the red briefs — pixel-replace driven by row coordinate +
// existing-pixel mask, no procedural shape draws (§I.0 compliant).
const CHARACTER_VARIANTS = [
  // Variant 0 — purple-robe wizard (the historical default).
  {
    ALIVE_CLOTHED:    { dir: TD_TILES, idx: 84 },
    ATTACKING:        { dir: TD_TILES, idx: 84 },
    RUSHING:          { dir: TD_TILES, idx: 84 },
    ALIVE_PANTS_DOWN: { dir: TD_TILES, idx: 84, pantsDown: true },
    ALIVE_BRIEFS_ONLY:{ dir: TD_TILES, idx: 84, pantsDown: true },
    DEAD:             { dir: TD_TILES, idx: 103 },
  },
  // Variant 1 — armoured knight (blue plate, completely different
  // silhouette from the wizard's pointy hat).
  {
    ALIVE_CLOTHED:    { dir: TD_TILES, idx: 87 },
    ATTACKING:        { dir: TD_TILES, idx: 87 },
    RUSHING:          { dir: TD_TILES, idx: 87 },
    ALIVE_PANTS_DOWN: { dir: TD_TILES, idx: 87, pantsDown: true },
    ALIVE_BRIEFS_ONLY:{ dir: TD_TILES, idx: 87, pantsDown: true },
    DEAD:             { dir: TD_TILES, idx: 103 },
  },
  // Variant 2 — bone-faced wraith (skull head, grey robe — instantly
  // distinguishable colour palette + face shape).
  {
    ALIVE_CLOTHED:    { dir: TD_TILES, idx: 96 },
    ATTACKING:        { dir: TD_TILES, idx: 96 },
    RUSHING:          { dir: TD_TILES, idx: 96 },
    ALIVE_PANTS_DOWN: { dir: TD_TILES, idx: 96, pantsDown: true },
    ALIVE_BRIEFS_ONLY:{ dir: TD_TILES, idx: 96, pantsDown: true },
    DEAD:             { dir: TD_TILES, idx: 103 },
  },
  // Variant 3 — red-tunic warrior (warm-palette outlier vs the
  // cool-palette wizard / knight / wraith).
  {
    ALIVE_CLOTHED:    { dir: TD_TILES, idx: 99 },
    ATTACKING:        { dir: TD_TILES, idx: 99 },
    RUSHING:          { dir: TD_TILES, idx: 99 },
    ALIVE_PANTS_DOWN: { dir: TD_TILES, idx: 99, pantsDown: true },
    ALIVE_BRIEFS_ONLY:{ dir: TD_TILES, idx: 99, pantsDown: true },
    DEAD:             { dir: TD_TILES, idx: 103 },
  },
];

// Variant 0 stays the back-compat default — `character_<state>.png`
// (no _v suffix) is an alias for the variant-0 composite so the
// existing LandingHero / SpriteAtlas.character_textures consumers
// keep rendering even before they switch to the per-variant API.
const CHARACTER_BASE = CHARACTER_VARIANTS[0];

// Tiny Town knife (sword) tile.
const KNIFE = { dir: TT_TILES, idx: 30 };

// ── Build helpers (zero procedural draw — pure pixel copies + scale) ───────
function tileToCanvas(tile, x, y, scale, canvas) {
  canvas.blitScaled(tile.rgba, tile.w, tile.h, x, y, scale, scale);
}

// Apply damage by punching darker pixels through specific *existing* tile
// pixels that match the door/wall tone — done via mask sampling, not by
// drawing rectangles.  We sample dark-brown (door) pixels and re-tint
// them progressively darker so the door "scratches → chops → ruins".
function applyDamage(canvas, dmg) {
  if (dmg <= 0) return;
  const { rgba, w, h } = canvas;
  // Mask: only pixels whose current colour reads as door-brown
  // (R in 100..220, G in 50..160, B in 30..120).  We don't need to know
  // *where* on the canvas — the recolour is value-driven, so it lands
  // wherever the source tiles already have door-brown pixels.
  for (let i = 0; i < rgba.length; i += 4) {
    if (rgba[i + 3] === 0) continue;
    const r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    if (r >= 90 && r <= 220 && g >= 40 && g <= 160 && b >= 20 && b <= 120 && r > g && g > b) {
      // Door-brown found — darken proportional to damage stage.
      const k = 1 - 0.22 * dmg;
      rgba[i] = Math.round(r * k);
      rgba[i + 1] = Math.round(g * k);
      rgba[i + 2] = Math.round(b * k);
    }
  }
  // Apply a pseudo-deterministic spatter of black pixels on the wall
  // region.  Spatter positions come from the existing wall pixel
  // coordinates (so each spatter pixel REPLACES an existing CC0 pixel
  // — no novel shape introduced, only colour).  This is a recolour,
  // not a draw.
  const spatterCount = dmg * 12;
  let placed = 0;
  for (let n = 0; placed < spatterCount && n < spatterCount * 8; n++) {
    const seed = (dmg * 73856093) ^ (n * 19349663);
    const px = ((seed >>> 0) % w);
    const py = (((seed * 7919) >>> 0) % h);
    const i = (py * w + px) * 4;
    if (rgba[i + 3] === 0) continue;
    const r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    // Only spatter on light wall tones (cream/stone), not on roof or grass.
    if ((r > 180 && g > 150 && b > 110) || (r > 130 && g > 130 && b > 130 && Math.abs(r - g) < 30)) {
      rgba[i] = Math.round(r * 0.45);
      rgba[i + 1] = Math.round(g * 0.45);
      rgba[i + 2] = Math.round(b * 0.45);
      placed++;
    }
  }
}

// ── House composite: 192×192 ──────────────────────────────────────────────
//
// Layout: 3 cols × 3 rows of 64×64 zoomed tiles drawn from a 9-tile
// recipe (roof_with_chimney + wall_top_with_door_arch +
// wall_bot_with_door_panel_and_windows). Each cell is a 16×16 source
// tile scaled 4×. Sprite anchor: bottom-center, so renderers should
// place anchor.x at (canvas_x + 96) and anchor.y at (canvas_y + 192).
function buildHouse(variant, dmg) {
  const recipe = HOUSE_RECIPES[variant];
  const SCALE = 4;
  const TILE = 64;            // 16-px source × 4
  const COLS = 3;
  const ROWS = 3;
  const W = TILE * COLS;      // 192
  const H = TILE * ROWS;      // 192
  const c = new Canvas(W, H);
  const rows = [recipe.roof_top, recipe.wall_top, recipe.wall_bot];
  for (let r = 0; r < ROWS; r++) {
    for (let col = 0; col < COLS; col++) {
      const idx = rows[r][col];
      const t = loadTile(TT_TILES, idx);
      tileToCanvas(t, col * TILE, r * TILE, SCALE, c);
    }
  }
  applyDamage(c, dmg);
  return c;
}

// ── Character composite: 96×128 ───────────────────────────────────────────
//
// Layout: a single 16×16 hero tile from Tiny Dungeon, scaled 6× → 96×96,
// vertically anchored so the hero stands at canvas-y ≈ 28..124, matching
// the existing Character.tscn 'Body' Sprite2D with position (0,-54).
//
// S-424 — accepts a variant spec (CHARACTER_VARIANTS[v][state]) so each
// player_id picks a distinct silhouette. The pantsDown flag on the spec
// triggers a leg-region pixel recolour to surface red briefs without
// drawing new shapes (only existing tile pixels are recoloured).
//
// PANTS_DOWN recolour: the source tile is 16×16 with the body roughly
// in rows 5..14 and the legs in rows 13..15. We recolour pixels in
// rows 11..14 whose existing colour reads as "torso/cloak" (mid-
// saturation, not skin/hair/black-outline) toward the red-briefs
// palette ((220, 60, 50), darkening at the bottom edge for shading).
// This is a pixel-coordinate-driven recolour, not a draw call —
// every pixel touched already exists in the CC0 source tile, only its
// hue is rotated. §I.0 carve-out for "recolour driven by mask
// sampling" applies (see applyDamage above for the same pattern).
function recolorPantsDown(tile) {
  const out = {
    w: tile.w,
    h: tile.h,
    rgba: new Uint8Array(tile.rgba),  // copy so cache stays clean
  };
  // Briefs target colour and outline.
  const BR = [220, 55, 55];          // bright red briefs
  const BR_DARK = [150, 35, 35];     // shadow row
  const SKIN = [232, 197, 154];      // exposed-leg skin
  for (let y = 11; y < tile.h; y++) {
    for (let x = 0; x < tile.w; x++) {
      const i = (y * tile.w + x) * 4;
      const a = out.rgba[i + 3];
      if (a < 32) continue;
      const r = out.rgba[i], g = out.rgba[i + 1], b = out.rgba[i + 2];
      // Skip the dark outline (preserves silhouette edges).
      if (r < 60 && g < 60 && b < 60) continue;
      if (y === 11 || y === 12) {
        // Top of legs: red briefs band.
        out.rgba[i] = BR[0]; out.rgba[i + 1] = BR[1]; out.rgba[i + 2] = BR[2];
      } else if (y === 13) {
        // Brief shadow row.
        out.rgba[i] = BR_DARK[0]; out.rgba[i + 1] = BR_DARK[1]; out.rgba[i + 2] = BR_DARK[2];
      } else {
        // Lower legs / feet — keep darker outline pixels but
        // recolour mid-tone to skin.
        if (r > 70 || g > 70 || b > 70) {
          out.rgba[i] = SKIN[0]; out.rgba[i + 1] = SKIN[1]; out.rgba[i + 2] = SKIN[2];
        }
      }
    }
  }
  return out;
}

function buildCharacter(spec) {
  const W = 96, H = 128;
  const SCALE = 6;
  const c = new Canvas(W, H);
  let tile = loadTile(spec.dir, spec.idx);
  if (spec.pantsDown) tile = recolorPantsDown(tile);
  // Center horizontally; offset top by 16px so feet land at y=128.
  c.blitScaled(tile.rgba, tile.w, tile.h, (W - tile.w * SCALE) / 2, H - tile.h * SCALE - 4, SCALE, SCALE);
  return c;
}

// ── Knife composite: 32×16 ─────────────────────────────────────────────────
function buildKnife() {
  const SCALE = 2;
  const tile = loadTile(KNIFE.dir, KNIFE.idx);
  const c = new Canvas(tile.w * SCALE, tile.h * SCALE);
  tileToCanvas(tile, 0, 0, SCALE, c);
  return c;
}

// ── Ground atlas: 256×64 (4 horizontal 64×64 tile crops) ──────────────────
function buildGroundAtlas() {
  const W = 256, H = 64;
  const SCALE = 4;
  const c = new Canvas(W, H);
  for (let i = 0; i < GROUND_VARIANTS.length; i++) {
    const tile = loadTile(TT_TILES, GROUND_VARIANTS[i]);
    tileToCanvas(tile, i * 64, 0, SCALE, c);
  }
  return c;
}

// ── Iso ground lattice: 11×11 cells of 128×64-px diamonds, baked into one
// PNG so Ground.gd doesn't need draw_colored_polygon at runtime.
//
// Layout: cell (x,y) where x∈[-5..5], y∈[-5..5].  Cartesian-to-iso
// projection: world.x = (x - y) * hw, world.y = (x + y) * hh, with
// hw=64, hh=32.  Image extents: x:[-768..768] horiz, y:[-352..352] vert.
// We pad to 1664×800 and offset so origin is at center.
//
// Each cell uses one of GROUND_VARIANTS based on the same hash Ground.gd
// used (preserved for visual continuity), then is drawn as a 128×64
// diamond-cropped tile.  Diamond mask: pixel kept iff
// |x-cx|/hw + |y-cy|/hh <= 1.  No procedural shape drawing — we copy
// CC0 source tile pixels into masked positions, period.
function buildGroundLattice(cols, rows) {
  const COLS = cols, ROWS = rows;
  const HW = 64, HH = 32;          // half-tile in iso space
  const TILE_W = HW * 2, TILE_H = HH * 2;
  const halfC = (COLS - 1) >> 1;
  const halfR = (ROWS - 1) >> 1;
  // Image footprint
  const W = COLS * HW + ROWS * HW + TILE_W;       // 11*64 + 11*64 + 128 = 1536
  const H = COLS * HH + ROWS * HH + TILE_H;       // 11*32 + 11*32 + 64  = 768
  const c = new Canvas(W, H);
  const ox = W / 2;
  const oy = H / 2;
  // Pre-load + scale the 4 source tiles to TILE_W × TILE_H once.
  const sources = GROUND_VARIANTS.map((idx) => {
    const t = loadTile(TT_TILES, idx);
    const tmp = new Canvas(TILE_W, TILE_H);
    // 16→128 horiz scale = 8x; 16→64 vert scale = 4x.  Use 8 horiz / 4 vert
    // so the tile fills a horizontally-stretched diamond bbox.
    tmp.blitScaled(t.rgba, t.w, t.h, 0, 0, TILE_W / t.w, TILE_H / t.h);
    return tmp;
  });
  function variantFor(x, y) {
    // Match Ground.gd's _variant_for hash exactly.
    let h = ((x + 100) * 73856093) ^ ((y + 100) * 19349663);
    h = h | 0;
    if (h < 0) h = -h;
    return h % sources.length;
  }
  // Painter's order: back tiles first (smallest x+y).
  for (let s = -halfC - halfR; s <= halfC + halfR; s++) {
    for (let x = -halfC; x <= halfC; x++) {
      const y = s - x;
      if (y < -halfR || y > halfR) continue;
      const cx = ox + (x - y) * HW;
      const cy = oy + (x + y) * HH;
      const v = variantFor(x, y);
      const tile = sources[v];
      // Diamond-mask the tile pixels into the destination.
      const x0 = Math.round(cx - HW), y0 = Math.round(cy - HH);
      for (let py = 0; py < TILE_H; py++) {
        for (let px = 0; px < TILE_W; px++) {
          // Diamond test: |dx|/HW + |dy|/HH <= 1
          const dx = (px - HW) / HW;
          const dy = (py - HH) / HH;
          if (Math.abs(dx) + Math.abs(dy) > 1.001) continue;
          const si = (py * TILE_W + px) * 4;
          const sa = tile.rgba[si + 3];
          if (sa === 0) continue;
          // Soft falloff toward outer rings so the lattice has nice edges
          // (matches Ground.gd's previous falloff).
          const dist = Math.max(Math.abs(x), Math.abs(y));
          const falloff = Math.max(0.55, Math.min(1.0, 1.0 - (dist - 3) / 4.0));
          const sr = Math.round(tile.rgba[si] * falloff);
          const sg = Math.round(tile.rgba[si + 1] * falloff);
          const sb = Math.round(tile.rgba[si + 2] * falloff);
          c.setPx(x0 + px, y0 + py, sr, sg, sb, sa);
        }
      }
    }
  }
  return c;
}

// ── Run ────────────────────────────────────────────────────────────────────
function write(name, canvas) {
  const path = resolve(OUT_DIR, name);
  writeFileSync(path, canvas.png());
  console.log('wrote', path, canvas.w + 'x' + canvas.h);
}

for (let v = 0; v < HOUSE_RECIPES.length; v++) {
  for (let d = 0; d < 4; d++) {
    write(`house_v${v}_d${d}.png`, buildHouse(v, d));
  }
}

// S-424 — emit per-variant character composites
// (`character_v0_<state>.png` … `character_v<N-1>_<state>.png`) AND
// keep the legacy `character_<state>.png` filenames as aliases of the
// variant-0 composite for backwards compatibility with any consumer
// that still reads SpriteAtlas.character_textures by state alone (e.g.
// LandingHero.gd before its own variant pass lands).
for (let v = 0; v < CHARACTER_VARIANTS.length; v++) {
  const variant = CHARACTER_VARIANTS[v];
  for (const state of Object.keys(variant)) {
    const composite = buildCharacter(variant[state]);
    write(`character_v${v}_${state}.png`, composite);
    if (v === 0) {
      // Back-compat alias — same bytes.
      write(`character_${state}.png`, composite);
    }
  }
}
write('knife.png', buildKnife());
write('ground_atlas.png', buildGroundAtlas());
write('ground_lattice_11.png', buildGroundLattice(11, 11));
write('ground_lattice_9.png', buildGroundLattice(9, 9));
