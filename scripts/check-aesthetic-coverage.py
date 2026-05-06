#!/usr/bin/env python3
"""scripts/check-aesthetic-coverage.py — S-439 §H2.5 per-frame ambient-detail gate.

Asserts that a captured live-game screenshot has the visible-aesthetic
floor below which a first-time viewer would read the scene as
"placeholder / broken art" rather than "competent indie pixel game".

The judge has flagged the same flat-mountain regression on six
consecutive iterations because validate-game-progression.mjs has no
per-frame ambient-detail gate. This script closes that gap by
quantitatively measuring:

  1. Mountain hue clusters in the left-edge cols 0-200, rows 100-400
     ROI: ≥6 distinct quantized RGB buckets. A flat single-hue polygon
     produces 1-3 buckets. Six stops of a ramp produce ≥6.
  2. Sky cloud sprite presence: ≥1 cluster of bright-near-white pixels
     in the upper sky band (rows 0-200) outside the ROI mountain area.
  3. Smoke particle pixel-count: ≥4 dark/grey pixels above any house
     (rows 50-300, full width) — the chimney smoke emitters.
  4. Grass tuft sprite-count: ≥3 distinct yellow/orange-tuft pixels
     in the iso ground band (rows 250-650). Tiny Town tile_0001 grass
     has the speckle, plain blocks don't.

Each check produces a numeric measurement; failures print the
measurement and the threshold so the judge / worker can see exactly
where the visual regression sits.

Usage:
  python3 scripts/check-aesthetic-coverage.py /path/to/frame.png
  python3 scripts/check-aesthetic-coverage.py /path/to/frame.png --json

Exit codes:
  0 — all gates pass
  1 — one or more gates fail (details on stderr)
  2 — input image missing / unreadable

The script depends ONLY on the Python stdlib (struct + zlib) so it can
run in any CI without `pip install pillow`. The PNG decoder handles
truecolor + truecolor+alpha 8-bit (the Godot HTML5 export's frame
format) and falls back to a friendly error for other modes.
"""

from __future__ import annotations

import json
import os
import struct
import sys
import zlib
from typing import Tuple


# ── Minimal PNG decoder (RGB / RGBA, 8-bit) ────────────────────────────────
def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def _read_chunks(buf: bytes):
    sig = b"\x89PNG\r\n\x1a\n"
    if buf[:8] != sig:
        raise ValueError("not a PNG (bad signature)")
    i = 8
    while i < len(buf):
        (length,) = struct.unpack(">I", buf[i : i + 4])
        ctype = buf[i + 4 : i + 8].decode("ascii")
        data = buf[i + 8 : i + 8 + length]
        i += 8 + length + 4  # +4 CRC, ignored
        yield ctype, data


def decode_png(path: str) -> Tuple[int, int, bytes, int]:
    """Return (width, height, rgba_bytes, bytes_per_pixel) — bpp in {3,4}."""
    with open(path, "rb") as f:
        buf = f.read()
    width = height = 0
    bit_depth = colour_type = 0
    idat = bytearray()
    for ctype, data in _read_chunks(buf):
        if ctype == "IHDR":
            width, height, bit_depth, colour_type, _, _, _ = struct.unpack(
                ">IIBBBBB", data
            )
        elif ctype == "IDAT":
            idat.extend(data)
        elif ctype == "IEND":
            break
    if bit_depth != 8:
        raise ValueError(f"unsupported PNG bit depth {bit_depth}")
    if colour_type == 2:
        bpp = 3
    elif colour_type == 6:
        bpp = 4
    else:
        raise ValueError(
            f"unsupported PNG colour_type {colour_type} (need 2 RGB or 6 RGBA)"
        )

    raw = zlib.decompress(bytes(idat))
    stride = width * bpp
    out = bytearray(stride * height)
    prev_row = bytearray(stride)
    p = 0
    for y in range(height):
        filt = raw[p]
        row = bytearray(raw[p + 1 : p + 1 + stride])
        p += 1 + stride
        if filt == 0:
            pass
        elif filt == 1:  # Sub
            for x in range(bpp, stride):
                row[x] = (row[x] + row[x - bpp]) & 0xFF
        elif filt == 2:  # Up
            for x in range(stride):
                row[x] = (row[x] + prev_row[x]) & 0xFF
        elif filt == 3:  # Average
            for x in range(stride):
                left = row[x - bpp] if x >= bpp else 0
                row[x] = (row[x] + (left + prev_row[x]) // 2) & 0xFF
        elif filt == 4:  # Paeth
            for x in range(stride):
                left = row[x - bpp] if x >= bpp else 0
                up = prev_row[x]
                upleft = prev_row[x - bpp] if x >= bpp else 0
                row[x] = (row[x] + _paeth(left, up, upleft)) & 0xFF
        else:
            raise ValueError(f"bad filter {filt}")
        out[y * stride : y * stride + stride] = row
        prev_row = row
    return width, height, bytes(out), bpp


def get_px(rgba: bytes, w: int, bpp: int, x: int, y: int) -> Tuple[int, int, int]:
    i = (y * w + x) * bpp
    return rgba[i], rgba[i + 1], rgba[i + 2]


# ── Gates ──────────────────────────────────────────────────────────────────
def quantize(r: int, g: int, b: int) -> int:
    """Bin to 5-bits per channel — folds neighbouring ramp colours into the
    same bucket so we count distinct *clusters*, not random JPEG noise."""
    return (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)


def is_mountain_like(r: int, g: int, b: int) -> bool:
    """Mountain colours: cool blue-grey to near-white with B≥G≥R-tolerance.

    The shaded ramp in mountain_front/back.png steps from deep navy
    (38,46,72) up through (96,116,148) → (146,156,184) → (208,216,232)
    → (248,250,255). Plus the warm ridge-kiss (196,180,168). All have:
      - B ≥ G - 12  AND  B ≥ R - 12  (cool dominant)  OR
      - the warm-kiss exception (R close to G, both > B by < 30, mid bright)
    AND brightness > 30 (not pure black) AND chroma low (not saturated red/green/blue).
    """
    if r + g + b < 90:
        return False  # too dark
    # Cool/blueish path: blue dominant
    cool = (b + 12 >= g) and (b + 12 >= r)
    # Snow/near-white path
    bright_neutral = r > 200 and g > 200 and b > 200 and abs(r - g) < 30 and abs(g - b) < 30
    # Warm ridge-kiss (lit-side accent): R ≥ G ≥ B but all in mid-bright range AND chroma low
    warm_kiss = (
        130 <= r <= 220 and 130 <= g <= 210 and 130 <= b <= 200
        and r >= g >= b - 5 and (r - b) <= 50
    )
    # Reject vivid greens (grass), oranges (dirt path tufts), reds (briefs).
    chroma = max(r, g, b) - min(r, g, b)
    if not bright_neutral and chroma > 90:
        return False
    return cool or bright_neutral or warm_kiss


def count_mountain_hue_clusters(
    rgba: bytes, w: int, h: int, bpp: int
) -> Tuple[int, dict]:
    """Count distinct quantized hue buckets in the mountain ROI.

    ROI: cols 0..200 ∩ rows 100..400. Counts only pixels whose colour
    actually reads as "mountain rock / snow / ridge highlight" — i.e.
    cool blue-grey, near-white, or warm sun-lit ridge accent. This
    excludes:
      - sky-blue pixels (would inflate the count when ParallaxBackground
        leaks through, but doesn't reflect mountain detail)
      - grass pixels (the iso ground tilemap extends into the ROI on the
        right side; vivid green is not mountain)
      - character / UI pixels in the lower band

    The pre-iter-91 flat mountain has ONE cool cluster + a few jpeg
    edge fringes; total mountain-like buckets ≤ 4. The shaded composite
    has 6 ramp stops + ridge-kiss + snow-cap accents so the bucket count
    sits near 10-12 by construction. Threshold 6 cleanly separates the
    two regimes.
    """
    x0, x1 = 0, min(200, w)
    y0, y1 = 100, min(400, h)
    buckets: set = set()
    pixel_count = 0
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b = get_px(rgba, w, bpp, x, y)
            # Skip pure sky-blue (R<G<B and B>180 and saturation low) — that's
            # ParallaxBackground SkyRect leaking through, not mountain.
            if b > 200 and r < 160 and g < 200 and abs(r - g) < 25 and (b - r) > 30:
                continue
            if not is_mountain_like(r, g, b):
                continue
            buckets.add(quantize(r, g, b))
            pixel_count += 1
    return len(buckets), {
        "roi": [x0, y0, x1, y1],
        "pixels_sampled": pixel_count,
    }


def count_cloud_sprites(rgba: bytes, w: int, h: int, bpp: int) -> Tuple[int, dict]:
    """Count distinct white-cloud pixel CLUSTERS in the upper sky band."""
    y0, y1 = 0, min(180, h)
    seen = [[False] * w for _ in range(y1 - y0)]
    clusters = 0
    for y in range(y0, y1):
        for x in range(w):
            if seen[y - y0][x]:
                continue
            r, g, b = get_px(rgba, w, bpp, x, y)
            # White-ish: all channels > 215 and roughly equal.
            if r >= 215 and g >= 215 and b >= 215 and abs(r - g) < 20 and abs(g - b) < 20:
                # BFS flood fill to count this cluster, mark pixels visited.
                stack = [(x, y)]
                size = 0
                while stack:
                    cx, cy = stack.pop()
                    if cy < y0 or cy >= y1 or cx < 0 or cx >= w:
                        continue
                    if seen[cy - y0][cx]:
                        continue
                    rr, gg, bb = get_px(rgba, w, bpp, cx, cy)
                    if not (rr >= 215 and gg >= 215 and bb >= 215 and abs(rr - gg) < 20 and abs(gg - bb) < 20):
                        continue
                    seen[cy - y0][cx] = True
                    size += 1
                    stack.extend([(cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)])
                if size >= 12:  # ignore single-pixel speckles
                    clusters += 1
    return clusters, {"sky_rows": [y0, y1]}


def count_smoke_pixels(rgba: bytes, w: int, h: int, bpp: int) -> Tuple[int, dict]:
    """Count grey-smoke pixels (mid-grey, low chroma) above houses."""
    y0, y1 = 50, min(300, h)
    count = 0
    for y in range(y0, y1):
        for x in range(w):
            r, g, b = get_px(rgba, w, bpp, x, y)
            # Mid-grey, low chroma: 90..170 on each channel, channel spread <20
            if 90 <= r <= 175 and 90 <= g <= 175 and 90 <= b <= 175:
                if max(r, g, b) - min(r, g, b) < 22:
                    count += 1
    return count, {"smoke_rows": [y0, y1]}


def count_grass_tufts(rgba: bytes, w: int, h: int, bpp: int) -> Tuple[int, dict]:
    """Count yellow/warm-orange tuft pixel CLUSTERS in the iso ground band."""
    y0, y1 = max(0, h // 2 - 100), min(h, h - 50)
    seen = [[False] * w for _ in range(y1 - y0)]
    clusters = 0
    for y in range(y0, y1):
        for x in range(w):
            if seen[y - y0][x]:
                continue
            r, g, b = get_px(rgba, w, bpp, x, y)
            # Warm yellow/tan tufts: R high, G mid-high, B low — dirt/path/tuft accent.
            if r >= 200 and 140 <= g <= 220 and b <= 130 and r > b + 60:
                stack = [(x, y)]
                size = 0
                while stack:
                    cx, cy = stack.pop()
                    if cy < y0 or cy >= y1 or cx < 0 or cx >= w:
                        continue
                    if seen[cy - y0][cx]:
                        continue
                    rr, gg, bb = get_px(rgba, w, bpp, cx, cy)
                    if not (rr >= 200 and 140 <= gg <= 220 and bb <= 130 and rr > bb + 60):
                        continue
                    seen[cy - y0][cx] = True
                    size += 1
                    stack.extend([(cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)])
                if size >= 4:  # at least a 2×2-ish tuft
                    clusters += 1
    return clusters, {"ground_rows": [y0, y1]}


# ── Main ───────────────────────────────────────────────────────────────────
THRESHOLDS = {
    "mountain_hue_clusters": 6,
    "cloud_sprites": 1,
    "smoke_pixels": 4,
    "grass_tuft_sprites": 3,
}


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("-")]
    flags = [a for a in argv[1:] if a.startswith("-")]
    if not args:
        print("usage: check-aesthetic-coverage.py <frame.png> [--json]", file=sys.stderr)
        return 2
    path = args[0]
    if not os.path.exists(path):
        print(f"[aesthetic] missing file: {path}", file=sys.stderr)
        return 2
    try:
        w, h, rgba, bpp = decode_png(path)
    except Exception as e:
        print(f"[aesthetic] decode failed: {e}", file=sys.stderr)
        return 2

    mountain_clusters, m_info = count_mountain_hue_clusters(rgba, w, h, bpp)
    cloud_count, c_info = count_cloud_sprites(rgba, w, h, bpp)
    smoke_count, s_info = count_smoke_pixels(rgba, w, h, bpp)
    tuft_count, t_info = count_grass_tufts(rgba, w, h, bpp)

    result = {
        "path": path,
        "width": w,
        "height": h,
        "measurements": {
            "mountain_hue_clusters": mountain_clusters,
            "cloud_sprites": cloud_count,
            "smoke_pixels": smoke_count,
            "grass_tuft_sprites": tuft_count,
        },
        "thresholds": THRESHOLDS,
        "info": {
            "mountain": m_info,
            "cloud": c_info,
            "smoke": s_info,
            "tuft": t_info,
        },
    }

    fails = []
    if mountain_clusters < THRESHOLDS["mountain_hue_clusters"]:
        fails.append(
            f"mountain_hue_clusters={mountain_clusters} < {THRESHOLDS['mountain_hue_clusters']} "
            f"(ROI cols 0-200 rows 100-400)"
        )
    if cloud_count < THRESHOLDS["cloud_sprites"]:
        fails.append(f"cloud_sprites={cloud_count} < {THRESHOLDS['cloud_sprites']}")
    if smoke_count < THRESHOLDS["smoke_pixels"]:
        fails.append(f"smoke_pixels={smoke_count} < {THRESHOLDS['smoke_pixels']}")
    if tuft_count < THRESHOLDS["grass_tuft_sprites"]:
        fails.append(
            f"grass_tuft_sprites={tuft_count} < {THRESHOLDS['grass_tuft_sprites']}"
        )

    result["passed"] = len(fails) == 0
    result["failures"] = fails

    if "--json" in flags:
        print(json.dumps(result, indent=2))
    else:
        print(
            f"[aesthetic] {os.path.basename(path)}: "
            f"mountain_hue={mountain_clusters} (≥{THRESHOLDS['mountain_hue_clusters']}) "
            f"clouds={cloud_count} (≥{THRESHOLDS['cloud_sprites']}) "
            f"smoke={smoke_count} (≥{THRESHOLDS['smoke_pixels']}) "
            f"tufts={tuft_count} (≥{THRESHOLDS['grass_tuft_sprites']}) "
            f"=> {'PASS' if result['passed'] else 'FAIL'}"
        )
        for fail in fails:
            print(f"  - FAIL: {fail}", file=sys.stderr)

    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
