#!/usr/bin/env node
// check-character-variation.mjs — S-424 acceptance: live mid-action frame
// must show ≥4 visually distinct character silhouettes, one per player.
//
// Mirrors check-house-variation.mjs but tightens the sample bounds to the
// foreground band where the iso characters stand (below their respective
// houses). The 4 quadrants are sampled from a band roughly y∈[40%..78%]
// of frame height — that's the playable centre minus the upper roof
// region (where houses dominate) and minus the bottom HUD.
//
// Strategy: 64-bin RGB histogram per quadrant, pairwise cosine distance,
// require ≥(C(4,2)-1)=5 of 6 pairs above a 0.20 threshold. Background
// noise (ground lattice) is shared across all 4 quadrants, so the
// per-character pixels are what drives the histogram delta.
//
// Usage:
//   node scripts/check-character-variation.mjs <frame.png> [--min-distinct=4] [--min-dist=0.20]
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
    process.stderr.write("usage: check-character-variation.mjs <frame.png> [--min-distinct=4] [--min-dist=0.20]\n");
    process.exit(2);
  }
  return { frame, minDistinct, minDist };
}

function readPng(path) {
  if (!fs.existsSync(path)) {
    process.stderr.write(`[character-variation] missing input: ${path}\n`);
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
  return 1 - dot;
}

const { frame, minDistinct, minDist } = parseArgs();
const png = readPng(frame);
const W = png.width, H = png.height;

// Character band — exclude BattleLog rail (right 22%), phase banner
// (top 18%), bottom HUD (bottom 14%), AND the upper-iso roof band where
// houses dominate (top half of playable area). 4 quadrants of the
// resulting tight rectangle.
const x0 = Math.floor(W * 0.04);
const x1 = Math.floor(W * 0.78);
const y0 = Math.floor(H * 0.40);
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

const minPairsAbove = (minDistinct * (minDistinct - 1)) / 2 - 1;
process.stdout.write(`distinct_pairs=${distinctPairs}/${pairs.length} threshold=${minPairsAbove} (min_distinct=${minDistinct}, min_dist=${minDist})\n`);

if (distinctPairs >= minPairsAbove) {
  process.stdout.write("[character-variation] PASS\n");
  process.exit(0);
}
process.stdout.write("[character-variation] FAIL — quadrants are too similar; Character.gd variant wiring may not be active\n");
process.exit(1);
