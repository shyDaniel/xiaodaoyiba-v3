#!/usr/bin/env node
// scripts/codegen-audio.mjs — offline ZzFX → WAV synthesizer.
//
// FINAL_GOAL §D1/§D2: Godot has no localStorage / Web Audio API, so the v2
// browser-side ZzFX presets cannot be played directly. Instead this script
// runs once at build time, renders each preset (and a small BGM loop) to a
// 16-bit PCM mono WAV at 44.1 kHz, and writes the files into
// client/assets/audio/{sfx,bgm}/. Audio.gd then loads them via
// ResourceLoader at runtime.
//
// The renderer is a faithful port of v2's xiaodaoyiba-v2/packages/client/
// src/audio/zzfx.ts (which is itself the upstream Frank Force ZzFX 1.3.2
// micro-renderer). The 19 numeric parameters describe a tiny synth voice:
//   volume, randomness, frequency, attack, sustain, release, shape,
//   shapeCurve, slide, deltaSlide, pitchJump, pitchJumpTime, repeatTime,
//   noise, modulation, bitCrush, delay, sustainVolume, decay, tremolo,
//   filter
//
// Determinism: the upstream renderer uses Math.random() inside the per-
// sample loop for the `randomness` (k) parameter only. To make the build
// reproducible (so CI doesn't churn on every run), we reseed Math.random
// with a mulberry32 PRNG keyed by a hash of the preset name before each
// render. Builds are byte-identical across machines as long as the preset
// table doesn't change.
//
// Usage:  node scripts/codegen-audio.mjs
// Idempotent. Overwrites existing files.

import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');
const SFX_DIR = resolve(ROOT, 'client/assets/audio/sfx');
const BGM_DIR = resolve(ROOT, 'client/assets/audio/bgm');

const SAMPLE_RATE = 44100;
const VOLUME = 0.3; // matches v2 zzfx.ts global volume

// ── Deterministic PRNG ────────────────────────────────────────────────────
// mulberry32 — small, fast, deterministic. Seeded per preset.
function mulberry32(seed) {
  let t = seed >>> 0;
  return function () {
    t = (t + 0x6d2b79f5) >>> 0;
    let r = t;
    r = Math.imul(r ^ (r >>> 15), r | 1);
    r ^= r + Math.imul(r ^ (r >>> 7), r | 61);
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
}

function seedFromName(name) {
  let h = 2166136261 >>> 0;
  for (let i = 0; i < name.length; i++) {
    h ^= name.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

// ── ZzFX renderer (port of v2 zzfx.ts renderZzfx) ─────────────────────────
// Faithful — math is intentionally identical to the upstream 1KB lambda.
// The single change vs. v2 is that Math.random() is replaced with a per-
// preset deterministic PRNG so build output is reproducible.
/* eslint-disable */
function renderZzfx(params, rand) {
  const [
    p = 1, k = 0.05, b = 220, e = 0, r = 0, t = 0.1, q = 0, D = 1, u = 0, y = 0,
    v = 0, z = 0, l = 0, E = 0, A = 0, F = 0, c = 0, w = 1, m = 0, B = 0, N = 0,
  ] = params;
  const M = Math;
  const d = 2 * M.PI;
  const R = SAMPLE_RATE;
  const arr = [];
  let bb = b;
  let uu = u;
  let ee = e;
  let mm = m;
  let rr = r;
  let tt = t;
  let cc = c;
  let yy = y;
  let AA = A;
  let vv = v;
  let zz = z;
  let ll = l;
  let pp = p;
  let G = uu * 500 * d / R / R;
  uu = G;
  bb = bb * (1 - k + 2 * k * rand()) * d / R;
  let C = bb;
  let g = 0;
  let H = 0;
  let a = 0;
  let n = 1;
  let I = 0;
  let J = 0;
  let f = 0;
  const h0 = N < 0 ? -1 : 1;
  const x0 = d * h0 * N * 2 / R;
  const L = M.cos(x0);
  const Z = M.sin;
  const K = Z(x0) / 4;
  const O = 1 + K;
  const X = -2 * L / O;
  const Y = (1 - K) / O;
  let P = (1 + h0 * L) / 2 / O;
  let Q = -(h0 + L) / O;
  let S = P;
  let T = 0;
  let U = 0;
  let V = 0;
  let W = 0;
  ee = R * ee + 9;
  mm *= R;
  rr *= R;
  tt *= R;
  cc *= R;
  yy *= 500 * d / R ** 3;
  AA *= d / R;
  vv *= d / R;
  zz *= R;
  ll = (R * ll) | 0;
  pp *= VOLUME;
  const h = (ee + mm + rr + tt + cc) | 0;
  let s = 0;
  while (a < h) {
    if (!(++J % ((100 * F) | 0 || 1))) {
      f = q
        ? 1 < q
          ? 2 < q
            ? 3 < q
              ? 4 < q
                ? ((g / d) % 1 < D / 2 ? 1 : 0) * 2 - 1
                : Z(g ** 3)
              : M.max(M.min(M.tan(g), 1), -1)
            : 1 - ((2 * g / d) % 2 + 2) % 2
          : 1 - 4 * M.abs(M.round(g / d) - g / d)
        : Z(g);
      f =
        (ll ? 1 - B + B * Z((d * a) / ll) : 1) *
        (4 < q ? s : (f < 0 ? -1 : 1) * M.abs(f) ** D) *
        (a < ee
          ? a / ee
          : a < ee + mm
            ? 1 - ((a - ee) / mm) * (1 - w)
            : a < ee + mm + rr
              ? w
              : a < h - cc
                ? ((h - a - cc) / tt) * w
                : 0);
      f = cc
        ? f / 2 +
          (cc > a ? 0 : ((a < h - cc ? 1 : (h - a) / cc) * arr[(a - cc) | 0]) / 2 / pp)
        : f;
      if (N) {
        W = S * T + Q * (T = U) + P * (U = f) - Y * V - X * (V = W);
        f = W;
      }
    }
    const x = bb * M.cos(AA * H++);
    g += x + x * E * Z(a ** 5);
    if (n && ++n > zz) {
      bb += vv;
      C += vv;
      n = 0;
    }
    if (!ll || ++I % ll) {
      bb = C;
      uu = G;
      n = n || 1;
    }
    arr[a++] = f * pp;
  }
  return Float32Array.from(arr);
}
/* eslint-enable */

// ── Mixing helpers ────────────────────────────────────────────────────────

/** Render a preset definition (which may be a single voice or a sequence
 *  of timed voices) into a Float32Array. */
function renderPreset(name, voices) {
  // voices: Array<{ delayMs?: number, params: number[] }>
  const rand = mulberry32(seedFromName(name));
  const layers = voices.map((v) => ({
    offset: Math.round(((v.delayMs ?? 0) / 1000) * SAMPLE_RATE),
    samples: renderZzfx(v.params, rand),
  }));
  const total = layers.reduce(
    (n, l) => Math.max(n, l.offset + l.samples.length),
    0,
  );
  const out = new Float32Array(total);
  for (const layer of layers) {
    for (let i = 0; i < layer.samples.length; i++) {
      out[layer.offset + i] += layer.samples[i];
    }
  }
  return out;
}

/** Concatenate a sequence of Float32Arrays at the given step interval (in
 *  ms). Used to build BGM patterns. */
function sequence(name, stepMs, steps) {
  // steps: Array<voices | null>  voices = Array<{ delayMs?, params }> or null
  const rand = mulberry32(seedFromName(name));
  const stride = Math.round((stepMs / 1000) * SAMPLE_RATE);
  // Render every step's voices first to know total length.
  const rendered = steps.map((step) => {
    if (step == null) return new Float32Array(0);
    const layers = step.map((v) => ({
      offset: Math.round(((v.delayMs ?? 0) / 1000) * SAMPLE_RATE),
      samples: renderZzfx(v.params, rand),
    }));
    const len = layers.reduce(
      (n, l) => Math.max(n, l.offset + l.samples.length),
      0,
    );
    const buf = new Float32Array(len);
    for (const layer of layers) {
      for (let i = 0; i < layer.samples.length; i++) {
        buf[layer.offset + i] += layer.samples[i];
      }
    }
    return buf;
  });
  // Total = max(stepIdx * stride + rendered.length).
  let total = 0;
  for (let i = 0; i < rendered.length; i++) {
    total = Math.max(total, i * stride + rendered[i].length);
  }
  // Pad to whole-bar length so the loop tile is clean.
  total = Math.max(total, steps.length * stride);
  const out = new Float32Array(total);
  for (let i = 0; i < rendered.length; i++) {
    const base = i * stride;
    for (let j = 0; j < rendered[i].length; j++) {
      out[base + j] += rendered[i][j];
    }
  }
  return out;
}

// ── WAV encoder (16-bit PCM mono) ─────────────────────────────────────────

function encodeWav(samples) {
  // Hard-clip then quantize to int16. Apply a mild peak-normalize so soft
  // presets are still audible without blowing past digital full-scale.
  let peak = 0;
  for (let i = 0; i < samples.length; i++) {
    const a = Math.abs(samples[i]);
    if (a > peak) peak = a;
  }
  // If the preset would clip, scale down to 0.95 FS. Don't boost quiet
  // presets — leave headroom for Godot bus volume_db (-6 dB nominal).
  const scale = peak > 0.95 ? 0.95 / peak : 1;

  const numSamples = samples.length;
  const byteLength = 44 + numSamples * 2;
  const buf = Buffer.alloc(byteLength);
  let p = 0;

  buf.write('RIFF', p); p += 4;
  buf.writeUInt32LE(byteLength - 8, p); p += 4;
  buf.write('WAVE', p); p += 4;
  buf.write('fmt ', p); p += 4;
  buf.writeUInt32LE(16, p); p += 4;             // PCM chunk size
  buf.writeUInt16LE(1, p); p += 2;              // format = PCM
  buf.writeUInt16LE(1, p); p += 2;              // num channels = mono
  buf.writeUInt32LE(SAMPLE_RATE, p); p += 4;
  buf.writeUInt32LE(SAMPLE_RATE * 2, p); p += 4; // byte rate (mono * 2 bytes)
  buf.writeUInt16LE(2, p); p += 2;              // block align
  buf.writeUInt16LE(16, p); p += 2;             // bits per sample
  buf.write('data', p); p += 4;
  buf.writeUInt32LE(numSamples * 2, p); p += 4;

  for (let i = 0; i < numSamples; i++) {
    let s = samples[i] * scale;
    if (s > 1) s = 1;
    if (s < -1) s = -1;
    const v = (s * 0x7fff) | 0;
    buf.writeInt16LE(v, p);
    p += 2;
  }
  return buf;
}

// ── SFX preset table (8 slots — FINAL_GOAL §D1) ──────────────────────────
// Ported from v2 packages/client/src/audio/presets.ts.
// Multi-voice presets (clothTear, victory, defeat) keep the original
// setTimeout offsets as `delayMs`.

const SFX_PRESETS = {
  // UI tap — short coin-blip on hand pick.
  tap: [
    { params: [1, 0, 380, 0.01, 0.04, 0.06, 1, 1.7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.7, 0.02] },
  ],
  // Big "reveal" gong-ish — used when an action round resolves.
  reveal: [
    { params: [1, 0.05, 110, 0.02, 0.08, 0.5, 2, 1.4, 0, 0, 0, 0, 0.05, 0.2, 0, 0.1, 0, 0.7, 0.1] },
  ],
  // Pull-pants — slidey whoop + cloth-tear texture (gasp omitted to keep
  // the slot to a single file; clothTear and gasp from v2 are folded in
  // here for an audible "yank" composite).
  pull: [
    { params: [1, 0.05, 290, 0.01, 0.12, 0.18, 1, 1.4, -8, 0, 0, 0, 0, 0, 12, 0, 0, 0.8, 0.04] },
    { delayMs: 30, params: [0.9, 0.2, 220, 0.005, 0.08, 0.18, 4, 1.1, -2, 0, 0, 0, 0, 2.4, 0, 0.6, 0, 0.7, 0.04] },
    { delayMs: 110, params: [0.7, 0.1, 180, 0, 0.04, 0.14, 3, 0.9, -10, 0, 0, 0, 0, 1.6, 0, 0.4, 0, 0.6, 0.05] },
  ],
  // Chop — sharp metallic tick. Plays at STRIKE start.
  chop: [
    { params: [1, 0.05, 1200, 0, 0.02, 0.16, 4, 1.6, 0, 0, 0, 0, 0, 0.6, 0, 0.2, 0, 0.8, 0.02] },
  ],
  // Dodge — quick rising blip.
  dodge: [
    { params: [1, 0.02, 520, 0.01, 0.05, 0.08, 0, 1.2, 18, 0, 0, 0, 0, 0, 0, 0, 0, 0.7, 0.02] },
  ],
  // House damage — low thud. Plays at IMPACT phase.
  thud: [
    { params: [1, 0.05, 80, 0.02, 0.04, 0.22, 3, 0.8, 0, 0, 0, 0, 0, 1.5, 0, 0.4, 0, 0.7, 0.05] },
  ],
  // Victory — C-E-G-C rising arpeggio + bass warmth + flourish.
  victory: [
    { params: [1, 0, 523, 0.02, 0.1, 0.18, 0, 1.4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.8, 0.02] },
    { delayMs: 120, params: [1, 0, 659, 0.02, 0.1, 0.18, 0, 1.4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.8, 0.02] },
    { delayMs: 240, params: [1, 0, 784, 0.02, 0.1, 0.18, 0, 1.4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.8, 0.02] },
    { delayMs: 360, params: [1, 0, 1047, 0.02, 0.18, 0.42, 0, 1.5, 0, 0, 0, 0, 0, 0.05, 0, 0, 0, 0.9, 0.04] },
    { delayMs: 360, params: [0.7, 0, 261, 0.02, 0.2, 0.4, 2, 1.2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.8, 0.05] },
    { delayMs: 620, params: [0.6, 0, 1568, 0.01, 0.08, 0.3, 0, 1.6, 0, 0, 0, 0, 0, 0.02, 0, 0, 0, 0.9, 0.03] },
  ],
  // Defeat — falling minor third.
  defeat: [
    { params: [1, 0, 392, 0.02, 0.1, 0.2, 1, 1.3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.7, 0.04] },
    { delayMs: 180, params: [1, 0, 311, 0.02, 0.16, 0.3, 1, 1.3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.7, 0.06] },
  ],
  // S-370 §H2.7 — Hover button: soft Stardew-style wood-tap. Brief
  // (~40ms), low volume, triangle wave so it doesn't intrude when the
  // cursor sweeps across menus.
  hover: [
    { params: [0.45, 0.05, 880, 0.005, 0.02, 0.04, 1, 1.2, -1, 0, 0, 0, 0, 0.05, 0, 0.1, 0, 0.6, 0.02] },
  ],
  // S-370 §H2.7 — Click button: layered wood-knock + paper-rustle so a
  // press has both impact (low thud) and texture (noisy scrape). Deeper
  // and slightly longer than hover so the player feels the press land.
  click: [
    { params: [0.85, 0.05, 220, 0.005, 0.04, 0.10, 3, 0.9, -2, 0, 0, 0, 0, 0.4, 0, 0.3, 0, 0.7, 0.04] },
    { delayMs: 12, params: [0.55, 0.4, 1400, 0, 0.02, 0.06, 4, 1.1, -10, 0, 0, 0, 0, 1.6, 0, 0.5, 0, 0.5, 0.03] },
  ],
};

// ── BGM tracks (3 variants — FINAL_GOAL §D2) ─────────────────────────────
// Pentatonic-on-C across all three variants so cross-fades are musically
// continuous. Ported from v2 packages/client/src/audio/bgm.ts.

const C3 = 130.81;
const G3 = 196.0;
const A3 = 220.0;
const C4 = 261.63;
const D4 = 293.66;
const E4 = 329.63;
const G4 = 392.0;
const A4 = 440.0;
const C5 = 523.25;
const D5 = 587.33;
const E5 = 659.25;
const G5 = 783.99;

/** lead voice envelope. shape = leadShape (0=sin,1=tri,2=saw,3=tan). */
function leadVoice(freq, vol, shape) {
  // [vol, k, freq, attack, sustain, release, shape, shapeCurve, slide,
  //  deltaSlide, pitchJump, pitchJumpTime, repeatTime, noise, modulation,
  //  bitCrush, delay, sustainVolume, decay]
  return [vol, 0.02, freq, 0.01, 0.07, 0.12, shape, 1.4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.7, 0.03];
}
function bassVoice(freq, vol) {
  return [vol, 0.02, freq, 0.01, 0.12, 0.18, 2, 1.2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.8, 0.06];
}

function makeBgmSteps(track) {
  // track: { lead: [freq|null]*16, bass: [freq|null]*16,
  //          leadVol, bassVol, leadShape }
  const out = [];
  for (let i = 0; i < track.lead.length; i++) {
    const voices = [];
    if (track.lead[i] != null) {
      voices.push({ params: leadVoice(track.lead[i], track.leadVol, track.leadShape) });
    }
    if (track.bass[i] != null) {
      voices.push({ params: bassVoice(track.bass[i], track.bassVol) });
    }
    out.push(voices.length ? voices : null);
  }
  return out;
}

const BGM_TRACKS = {
  lobby: {
    stepMs: 200,
    leadVol: 0.20,
    bassVol: 0.14,
    leadShape: 1,
    lead: [
      C5, null, G4, null, E4, null, G4, null,
      A4, null, E5, null, D5, null, G4, null,
    ],
    bass: [
      C4, null, null, null, G4, null, null, null,
      A4, null, null, null, D4, null, null, null,
    ],
  },
  battle: {
    stepMs: 150,
    leadVol: 0.22,
    bassVol: 0.18,
    leadShape: 2,
    lead: [
      C5, E5, G5, E5, A4, C5, E5, G4,
      G5, E5, C5, A4, G4, A4, C5, D5,
    ],
    bass: [
      C3, null, G3, null, A3, null, G3, null,
      C3, null, A3, null, G3, null, C3, null,
    ],
  },
  victory: {
    stepMs: 160,
    leadVol: 0.24,
    bassVol: 0.20,
    leadShape: 0,
    lead: [
      G4, C5, E5, G5, C5, E5, G5, null,
      A4, C5, E5, G5, C5, null, G5, null,
    ],
    bass: [
      C3, null, null, null, G3, null, null, null,
      A3, null, null, null, C3, null, G3, null,
    ],
  },
};

// ── Main ──────────────────────────────────────────────────────────────────

function ensureDir(p) {
  mkdirSync(p, { recursive: true });
}

function writeWav(path, samples) {
  writeFileSync(path, encodeWav(samples));
  const ms = ((samples.length / SAMPLE_RATE) * 1000).toFixed(0);
  console.log(`  wrote ${path}  (${samples.length} samples, ${ms} ms)`);
}

/** Pre-author the Godot `.import` sidecar so generated WAVs come back as
 *  the right kind of AudioStreamWAV without manual editor interaction.
 *
 *  Critical for BGM: without `edit/loop_mode=1`, Godot defaults to no-loop
 *  and BGM stops after one play. We can't set this from runtime
 *  (AudioStreamWAV.loop_mode is only writable on the imported resource),
 *  so we control it via the .import file the importer reads on next
 *  `godot --import`. */
function writeImportSidecar(wavAbsPath, opts) {
  const { loop } = opts;
  const sidecarPath = `${wavAbsPath}.import`;
  // Convert absolute path to res:// path. wavAbsPath is e.g.
  // /home/.../client/assets/audio/sfx/tap.wav → assets/audio/sfx/tap.wav.
  const idx = wavAbsPath.indexOf('/client/');
  const resPath = wavAbsPath.slice(idx + '/client/'.length);
  const lines = [
    '[remap]',
    '',
    'importer="wav"',
    'type="AudioStreamWAV"',
    '',
    '[deps]',
    '',
    `source_file="res://${resPath}"`,
    '',
    '[params]',
    '',
    'force/8_bit=false',
    'force/mono=false',
    'force/max_rate=false',
    'force/max_rate_hz=44100',
    'edit/trim=false',
    'edit/normalize=false',
    // Importer enum (per Godot 4.3 ResourceImporterWAV / PR #59170):
    //   0=Detect from WAV header, 1=Disabled, 2=Forward,
    //   3=Ping-Pong, 4=Backward.
    // Generated WAVs have no `smpl` chunk, so Detect would resolve to
    // disabled — pick Forward explicitly for BGM, Disabled for SFX.
    `edit/loop_mode=${loop ? 2 : 1}`,
    'edit/loop_begin=0',
    'edit/loop_end=-1',
    'compress/mode=0',
    '',
  ];
  writeFileSync(sidecarPath, lines.join('\n'));
}

function main() {
  ensureDir(SFX_DIR);
  ensureDir(BGM_DIR);

  console.log('[codegen-audio] rendering 8 SFX presets...');
  for (const [name, voices] of Object.entries(SFX_PRESETS)) {
    const samples = renderPreset(name, voices);
    const wavPath = resolve(SFX_DIR, `${name}.wav`);
    writeWav(wavPath, samples);
    writeImportSidecar(wavPath, { loop: false });
  }

  console.log('[codegen-audio] rendering 3 BGM tracks...');
  // Render 4 bars of each track so the loop is long enough to feel like
  // music (~12-13 s per variant) without ballooning the HTML5 bundle.
  // 16 steps * stepMs * 4 bars.
  const BARS = 4;
  for (const [name, track] of Object.entries(BGM_TRACKS)) {
    const steps = makeBgmSteps(track);
    const looped = [];
    for (let bar = 0; bar < BARS; bar++) looped.push(...steps);
    const samples = sequence(name, track.stepMs, looped);
    const wavPath = resolve(BGM_DIR, `${name}.wav`);
    writeWav(wavPath, samples);
    writeImportSidecar(wavPath, { loop: true });
  }

  console.log('[codegen-audio] done.');
}

main();
