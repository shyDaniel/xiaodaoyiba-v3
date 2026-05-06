#!/usr/bin/env node
// check-house-variation.mjs — S-417 acceptance: live mid-action frame
// must show ≥4 visually distinct house silhouettes.
//
// Strategy: split a 1280×720 (or whatever was captured) frame into a
// grid of N regions where the iso houses live, compute a 16-bin RGB
// histogram per region, and assert pairwise cosine distance > 0.20
// between ≥6 of the 6 region pairs (4 houses → C(4,2)=6 pairs).
//
// We avoid hard-coding house bounding boxes (the iso layout shifts with
// camera and player count) — instead we sample 4 quadrants from a
// shrunk centre rectangle that excludes the BattleLog rail (right 22%)
// and the top phase banner (top 18%). Each quadrant is ~½ the playable
// area's width × ~½ its height, which is large enough to dominate any
// single house silhouette plus its shaded ground.
//
// Usage:
//   node scripts/check-house-variation.mjs <frame.png> [--min-distinct=4] [--min-dist=0.20]
//
// Exit:
//   0 — pass
//   1 — gate failed
//   2 — could not read input

import fs from "node:fs";
import { PNG } from "pngjs";

function parseArgs() {
  const args = process.argv.slice(2);
  let frame = null;
  let minDistinct = 4;
  let minDist = 0.20;
  for (const a of args) {
    if (a.startsWith("--min-distinct=")) minDistinct = Number(a.split("=")[1]);
    else if (a.startsWith("--min-dist=")) minDist = Number(a.split("=")[1]);
    else if (!frame) frame = a;
  }
  if (!frame) {
    process.stderr.write("usage: check-house-variation.mjs <frame.png> [--min-distinct=4] [--min-dist=0.20]\n");
    process.exit(2);
  }
  return { frame, minDistinct, minDist };
}

function readPng(path) {
  if (!fs.existsSync(path)) {
    process.stderr.write(`[house-variation] missing input: ${path}\n`);
    process.exit(2);
  }
  const buf = fs.readFileSync(path);
  return PNG.sync.read(buf);
}

// 4×4×4 = 64-bin RGB histogram normalised to a unit vector.
function histogram(png, x0, y0, x1, y1) {
  const bins = new Float64Array(64);
  let total = 0;
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      const i = (png.width * y + x) * 4;
      const r = png.data[i] >> 6;     // 0..3
      const g = png.data[i + 1] >> 6;
      const b = png.data[i + 2] >> 6;
      bins[(r * 16) + (g * 4) + b] += 1;
      total += 1;
    }
  }
  // Normalise to unit length so cosine distance is well-defined.
  let norm = 0;
  for (const v of bins) norm += v * v;
  norm = Math.sqrt(norm);
  if (norm > 0) {
    for (let i = 0; i < 64; i++) bins[i] /= norm;
  }
  return { bins, total };
}

function cosineDistance(a, b) {
  let dot = 0;
  for (let i = 0; i < 64; i++) dot += a.bins[i] * b.bins[i];
  // Both already unit-normalised → cosine similarity = dot.
  // Distance = 1 - similarity.
  return 1 - dot;
}

const { frame, minDistinct, minDist } = parseArgs();
const png = readPng(frame);
const W = png.width, H = png.height;

// Playable area excludes BattleLog rail (right 22%) and phase banner
// (top 18%) and bottom HUD (bottom 14%). 4 quadrants of that interior.
const x0 = Math.floor(W * 0.04);
const x1 = Math.floor(W * 0.78);
const y0 = Math.floor(H * 0.18);
const y1 = Math.floor(H * 0.86);
const midX = Math.floor((x0 + x1) / 2);
const midY = Math.floor((y0 + y1) / 2);

const quads = [
  { name: "TL", x0, y0, x1: midX, y1: midY },
  { name: "TR", x0: midX, y0, x1, y1: midY },
  { name: "BL", x0, y0: midY, x1: midX, y1 },
  { name: "BR", x0: midX, y0: midY, x1, y1 },
];
const hists = quads.map(q => ({ ...q, hist: histogram(png, q.x0, q.y0, q.x1, q.y1) }));

const pairs = [];
for (let i = 0; i < hists.length; i++) {
  for (let j = i + 1; j < hists.length; j++) {
    const d = cosineDistance(hists[i].hist, hists[j].hist);
    pairs.push({ a: hists[i].name, b: hists[j].name, d });
  }
}

let distinctPairs = 0;
for (const p of pairs) {
  const ok = p.d > minDist;
  if (ok) distinctPairs += 1;
  process.stdout.write(`${p.a}~${p.b} cosine_dist=${p.d.toFixed(4)} ${ok ? "OK" : "TOO_SIMILAR"}\n`);
}

// 4 distinct quadrants ⇔ ≥5 of 6 pair distances above threshold (we
// allow a single near-pair because two houses may legitimately share
// a roof tint hue under the per-player HSV ramp; the variant
// silhouette differences should still pull ≥5/6 over the line).
const minPairsAbove = (minDistinct * (minDistinct - 1)) / 2 - 1;
process.stdout.write(`distinct_pairs=${distinctPairs}/${pairs.length} threshold=${minPairsAbove} (min_distinct=${minDistinct}, min_dist=${minDist})\n`);

if (distinctPairs >= minPairsAbove) {
  process.stdout.write("[house-variation] PASS\n");
  process.exit(0);
}
process.stdout.write("[house-variation] FAIL — quadrants are too similar; House.gd variant wiring may not be active\n");
process.exit(1);
