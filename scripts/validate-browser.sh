#!/usr/bin/env bash
# scripts/validate-browser.sh — boot a real Chromium against the served
# HTML5 build and capture screenshots/live-landing.png.
#
# Why this script exists:
#   The judge / autopilot loop needs to drive the live Godot HTML5 build
#   end-to-end through a browser, but this WSL2 sandbox lacks sudo and
#   the playwright/chrome-devtools MCPs both fail to launch chromium
#   because libnspr4/libnss3/libasound are not installed system-wide.
#   We work around that by:
#     1. Reusing the chromium-headless-shell binary that
#        `npx playwright install` already dropped under
#        ~/.cache/ms-playwright/chromium_headless_shell-1217/.
#     2. Pointing LD_LIBRARY_PATH at user-space copies of the
#        missing .so files in ~/.local/chrome-libs/ (apt-get
#        download'd without sudo, no install required).
#     3. Driving the browser via `playwright-core` (npm-pack'd into
#        a per-user cache once, ~2.5MB) instead of Chrome's
#        `--screenshot` flag — `--virtual-time-budget` short-
#        circuits the Web Worker boot Godot needs ("loading-workers"
#        dependency hangs forever), but real CDP + waitForFunction
#        gives us a deterministic "canvas has rendered N frames"
#        signal.
#
# Usage:
#   scripts/validate-browser.sh                      # default: localhost:5173, screenshots/live-landing.png, 8s settle
#   URL=... OUT=... SETTLE_MS=... scripts/validate-browser.sh
#
# Acceptance:
#   exit 0 + the output PNG must contain >MIN_PIXELS non-black pixels (verified
#   in-process via a tiny Node script), proving the Godot canvas booted.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

URL="${URL:-http://localhost:5173/}"
OUT="${OUT:-screenshots/live-landing.png}"
SETTLE_MS="${SETTLE_MS:-8000}"
WIDTH="${WIDTH:-1280}"
HEIGHT="${HEIGHT:-720}"
MIN_PIXELS="${MIN_PIXELS:-10000}"

CHROME_LIBS="${CHROME_LIBS:-$HOME/.local/chrome-libs/usr/lib/x86_64-linux-gnu}"
HEADLESS_SHELL="${HEADLESS_SHELL:-$HOME/.cache/ms-playwright/chromium_headless_shell-1217/chrome-headless-shell-linux64/chrome-headless-shell}"
PW_CACHE="${PW_CACHE:-$HOME/.cache/xdyb-playwright-core}"
PW_VERSION="${PW_VERSION:-1.59.1}"

if [[ ! -x "$HEADLESS_SHELL" ]]; then
  echo "[validate-browser] missing chrome-headless-shell at: $HEADLESS_SHELL" >&2
  echo "[validate-browser] run: npx playwright install chromium" >&2
  exit 2
fi
if [[ ! -d "$CHROME_LIBS" ]]; then
  echo "[validate-browser] missing user-space chrome libs at: $CHROME_LIBS" >&2
  cat >&2 <<'EOM'
[validate-browser] no sudo? bootstrap them user-locally:

  TMP=$(mktemp -d) && cd "$TMP" && \
    apt-get download libnspr4 libnss3 libnssutil3 libasound2t64 \
      libatk1.0-0t64 libatk-bridge2.0-0t64 libcups2t64 libxcomposite1 \
      libxdamage1 libxrandr2 libxkbcommon0 libpango-1.0-0 libcairo2 libgbm1 && \
    for d in *.deb; do dpkg-deb -x "$d" "$HOME/.local/chrome-libs"; done

EOM
  exit 2
fi

# One-time playwright-core fetch (no project dependency added).
PW_DIR="$PW_CACHE/$PW_VERSION"
if [[ ! -f "$PW_DIR/package/index.mjs" ]]; then
  echo "[validate-browser] fetching playwright-core@${PW_VERSION} into $PW_DIR ..." >&2
  mkdir -p "$PW_DIR"
  ( cd "$PW_DIR" && npm pack "playwright-core@${PW_VERSION}" >/dev/null 2>&1 \
      && tar xzf "playwright-core-${PW_VERSION}.tgz" \
      && rm -f "playwright-core-${PW_VERSION}.tgz" )
fi
if [[ ! -f "$PW_DIR/package/index.mjs" ]]; then
  echo "[validate-browser] failed to install playwright-core to $PW_DIR" >&2
  exit 2
fi

mkdir -p "$(dirname "$OUT")"
ABS_OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"

# Sanity: the URL is reachable (server must be up).
if ! curl -sSf --max-time 3 -o /dev/null "$URL"; then
  echo "[validate-browser] URL not reachable: $URL" >&2
  echo "[validate-browser] start the dev server first:  pnpm serve &" >&2
  exit 3
fi

echo "[validate-browser] driving headless chromium against $URL"
echo "[validate-browser] settle=${SETTLE_MS}ms  viewport=${WIDTH}x${HEIGHT}  out=$ABS_OUT"

LD_LIBRARY_PATH="$CHROME_LIBS" \
PW_CHROMIUM_PATH="$HEADLESS_SHELL" \
PW_PACKAGE_DIR="$PW_DIR/package" \
URL="$URL" OUT="$ABS_OUT" \
SETTLE_MS="$SETTLE_MS" WIDTH="$WIDTH" HEIGHT="$HEIGHT" \
node --input-type=module -e '
const { chromium } = await import(process.env.PW_PACKAGE_DIR + "/index.mjs");

const url       = process.env.URL;
const out       = process.env.OUT;
const settleMs  = Number(process.env.SETTLE_MS);
const viewport  = { width: Number(process.env.WIDTH), height: Number(process.env.HEIGHT) };

const browser = await chromium.launch({
  executablePath: process.env.PW_CHROMIUM_PATH,
  args: [
    "--no-sandbox",
    // Godot HTML5 needs WebGL2; chrome-headless-shell normally has no
    // GPU, so route GL through the SwiftShader software rasterizer.
    "--use-gl=angle",
    "--use-angle=swiftshader",
    "--enable-unsafe-swiftshader",
    "--disable-dev-shm-usage",
  ],
});
try {
  const ctx = await browser.newContext({ viewport });
  const page = await ctx.newPage();
  page.on("console", m => process.stderr.write("[chrome:" + m.type() + "] " + m.text() + "\n"));
  page.on("pageerror", e => process.stderr.write("[chrome:pageerror] " + e.message + "\n"));
  await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30000 });
  // Godot writes to <canvas#canvas>; wait for it to mount AND become
  // non-zero size — that means the engine handed off to the scene tree.
  await page.waitForFunction(() => {
    const c = document.querySelector("canvas");
    return c && c.width > 0 && c.height > 0;
  }, { timeout: 30000 });
  // Then wait the requested settle so animations / first frames paint.
  await page.waitForTimeout(settleMs);
  await page.screenshot({ path: out, fullPage: false });
} finally {
  await browser.close();
}
' 2>/tmp/validate-browser.log || {
  echo "[validate-browser] node driver failed. Tail of log:" >&2
  tail -40 /tmp/validate-browser.log >&2
  exit 4
}

if [[ ! -s "$ABS_OUT" ]]; then
  echo "[validate-browser] screenshot was not written: $ABS_OUT" >&2
  exit 5
fi

# Verify the screenshot has >= MIN_PIXELS non-black pixels. Pure-Node, no
# image-decoding deps — we decode the PNG by hand (zlib + paeth).
NON_BLACK="$(MIN_PIXELS="$MIN_PIXELS" node -e '
const fs = require("fs");
const path = process.argv[1];
const buf = fs.readFileSync(path);
if (buf.length < 8 || buf.readUInt32BE(0) !== 0x89504e47) {
  console.error("not a PNG"); process.exit(1);
}
const w = buf.readUInt32BE(16), h = buf.readUInt32BE(20);
process.stderr.write("png " + w + "x" + h + "\n");
const bitDepth = buf[24], colorType = buf[25];
if (bitDepth !== 8 || (colorType !== 2 && colorType !== 6)) {
  console.error("unsupported png " + bitDepth + "/" + colorType); process.exit(2);
}
const bpp = (colorType === 6) ? 4 : 3;
let off = 8;
const idatChunks = [];
while (off < buf.length) {
  const len = buf.readUInt32BE(off);
  const type = buf.toString("ascii", off + 4, off + 8);
  if (type === "IDAT") idatChunks.push(buf.slice(off + 8, off + 8 + len));
  if (type === "IEND") break;
  off += 12 + len;
}
const raw = require("zlib").inflateSync(Buffer.concat(idatChunks));
const sl = w * bpp;
const out = Buffer.alloc(h * sl);
let prev = Buffer.alloc(sl);
let inOff = 0;
for (let y = 0; y < h; y++) {
  const filter = raw[inOff]; inOff++;
  const dst = Buffer.alloc(sl);
  for (let x = 0; x < sl; x++) {
    const a = x >= bpp ? dst[x - bpp] : 0;
    const b = prev[x];
    const c = x >= bpp ? prev[x - bpp] : 0;
    let v;
    switch (filter) {
      case 0: v = raw[inOff + x]; break;
      case 1: v = (raw[inOff + x] + a) & 0xff; break;
      case 2: v = (raw[inOff + x] + b) & 0xff; break;
      case 3: v = (raw[inOff + x] + ((a + b) >> 1)) & 0xff; break;
      case 4: {
        const p = a + b - c;
        const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
        const pred = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c);
        v = (raw[inOff + x] + pred) & 0xff; break;
      }
      default: console.error("bad filter " + filter); process.exit(3);
    }
    dst[x] = v;
  }
  inOff += sl;
  dst.copy(out, y * sl);
  prev = dst;
}
let nonBlack = 0;
for (let i = 0; i < out.length; i += bpp) {
  if (out[i] + out[i+1] + out[i+2] > 24) nonBlack++;
}
process.stdout.write(String(nonBlack));
' "$ABS_OUT")"

if [[ -z "$NON_BLACK" || "$NON_BLACK" -lt "$MIN_PIXELS" ]]; then
  echo "[validate-browser] FAIL: only $NON_BLACK non-black pixels (need >= $MIN_PIXELS)" >&2
  echo "[validate-browser] screenshot at $ABS_OUT — Godot canvas likely did not boot." >&2
  echo "[validate-browser] try a longer settle:  SETTLE_MS=15000 scripts/validate-browser.sh" >&2
  exit 6
fi

echo "[validate-browser] PASS: $NON_BLACK non-black pixels  ->  $ABS_OUT"
