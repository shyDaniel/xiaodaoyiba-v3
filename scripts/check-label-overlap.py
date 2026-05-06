#!/usr/bin/env python3
"""scripts/check-label-overlap.py — S-443 pixel-level acceptance gate.

Asserts that no two name labels in a captured live-game screenshot
visually concatenate into a single horizontal text run. The t27000.png
'random.nter' regression had two distinct labels — the HOUSE
'counter' and the VISITOR character 'random' — render at adjacent
world y with zero gap, producing what reads as a single string.

Algorithm (no PIL dep — stdlib struct + zlib only, mirrors
check-aesthetic-coverage.py):

  1. Decode the PNG → flat RGBA buffer.
  2. For each row, count the number of "near-white" pixels (R,G,B
     all ≥ 220). Name labels are rendered with white fill + thin
     dark outline, so a row inside a label glyph has a high
     near-white pixel count concentrated in a narrow x-band.
  3. Threshold: a "text row" has ≥ 12 near-white pixels (a typical
     16-px font glyph has 4-6 white pixels per row × multiple
     glyphs). Empty rows have 0-5 (just sky / FX noise).
  4. Find vertically contiguous text-row CLUSTERS (≥ 6 consecutive
     text rows = one label).
  5. For every pair of clusters, ensure the GAP between
     cluster_A.bottom_y and cluster_B.top_y is ≥ 4 px. If two
     clusters are adjacent or overlapping in y, that's the
     'random.nter' regression — fail.

This runs against the t27000.png produced by
validate-game-progression.mjs. Wired in from that script so the
regression is caught the moment a future change re-introduces it.

Usage:
  python3 scripts/check-label-overlap.py /path/to/frame.png
  python3 scripts/check-label-overlap.py /path/to/frame.png --json

Exit codes:
  0 — all label clusters are vertically separated by ≥ 4 px gap
  1 — at least one adjacent label pair has < 4 px gap (concatenation)
  2 — input image missing / unreadable

The script depends ONLY on the Python stdlib (struct + zlib).
"""

from __future__ import annotations

import json
import os
import struct
import sys
import zlib
from typing import List, Tuple


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
        i += 8 + length + 4
        yield ctype, data


def decode_png(path: str) -> Tuple[int, int, bytes, int]:
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
        elif filt == 1:
            for x in range(bpp, stride):
                row[x] = (row[x] + row[x - bpp]) & 0xFF
        elif filt == 2:
            for x in range(stride):
                row[x] = (row[x] + prev_row[x]) & 0xFF
        elif filt == 3:
            for x in range(stride):
                left = row[x - bpp] if x >= bpp else 0
                row[x] = (row[x] + (left + prev_row[x]) // 2) & 0xFF
        elif filt == 4:
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


# ── Label cluster detection ────────────────────────────────────────────────
# Tightened thresholds — name-label fill is pure white (255,255,255).
# Iso path tiles have highlights with R≈240, G≈230, B≈210 which the
# 220 threshold caught as "near-white", flooding the row scan with
# false positives across the entire iso-tile region. Pure-white-only
# (≥248 on every channel) keeps the label glyphs but excludes the
# tile/grass/cloud highlights.
NEAR_WHITE_R = 248
NEAR_WHITE_G = 248
NEAR_WHITE_B = 248
TEXT_ROW_MIN_PX = 8           # ≥8 pure-white px in a row = text row candidate
CLUSTER_MIN_ROWS = 4           # ≥4 contiguous text rows = one label cluster
MIN_GAP_PX = 4                # adjacent clusters must be ≥4 px apart


def near_white_count_per_row(rgba: bytes, w: int, h: int, bpp: int) -> List[int]:
    counts = [0] * h
    for y in range(h):
        row_base = y * w * bpp
        c = 0
        for x in range(w):
            i = row_base + x * bpp
            r = rgba[i]
            g = rgba[i + 1]
            b = rgba[i + 2]
            if r >= NEAR_WHITE_R and g >= NEAR_WHITE_G and b >= NEAR_WHITE_B:
                c += 1
        counts[y] = c
    return counts


def find_text_clusters(counts: List[int]) -> List[Tuple[int, int, int]]:
    """Return list of (top_y, bottom_y, peak_count) for each text-row run."""
    clusters: List[Tuple[int, int, int]] = []
    in_run = False
    run_start = 0
    run_peak = 0
    for y, c in enumerate(counts):
        if c >= TEXT_ROW_MIN_PX:
            if not in_run:
                in_run = True
                run_start = y
                run_peak = c
            else:
                if c > run_peak:
                    run_peak = c
        else:
            if in_run:
                run_len = y - run_start
                if run_len >= CLUSTER_MIN_ROWS:
                    clusters.append((run_start, y - 1, run_peak))
                in_run = False
    if in_run:
        run_len = len(counts) - run_start
        if run_len >= CLUSTER_MIN_ROWS:
            clusters.append((run_start, len(counts) - 1, run_peak))
    return clusters


def cluster_x_band(rgba: bytes, w: int, h: int, bpp: int,
                   top_y: int, bottom_y: int) -> Tuple[int, int]:
    """Return (left_x, right_x) — the horizontal extent of near-white
    pixels across the cluster's row range. Used to skip vertically
    adjacent clusters that are clearly NOT in the same horizontal
    column (so two unrelated labels at different x ranges aren't
    flagged as a 'concatenation')."""
    leftmost = w
    rightmost = -1
    for y in range(top_y, bottom_y + 1):
        row_base = y * w * bpp
        for x in range(w):
            i = row_base + x * bpp
            r = rgba[i]
            g = rgba[i + 1]
            b = rgba[i + 2]
            if r >= NEAR_WHITE_R and g >= NEAR_WHITE_G and b >= NEAR_WHITE_B:
                if x < leftmost:
                    leftmost = x
                if x > rightmost:
                    rightmost = x
    return leftmost, rightmost


def find_x_segments(rgba: bytes, w: int, h: int, bpp: int,
                    top_y: int, bottom_y: int) -> List[Tuple[int, int]]:
    """Return list of (left_x, right_x) horizontal text runs in the
    cluster's row range. A segment is a maximal x-span where ≥ 1
    near-white pixel appears in any row of [top_y..bottom_y]. Segments
    are merged when their gap is < 6 px (intra-glyph kerning), so a
    label like 'counter' reads as ONE segment, not 7 per-glyph segments.
    Two labels concatenated horizontally show up as ONE WIDE segment;
    two labels separated by ≥ 6 px gutter show up as TWO segments."""
    # Build a per-x boolean: any near-white pixel in this column inside
    # the row range?
    per_x = [False] * w
    for y in range(top_y, bottom_y + 1):
        row_base = y * w * bpp
        for x in range(w):
            i = row_base + x * bpp
            r = rgba[i]
            g = rgba[i + 1]
            b = rgba[i + 2]
            if r >= NEAR_WHITE_R and g >= NEAR_WHITE_G and b >= NEAR_WHITE_B:
                per_x[x] = True
    # Walk the boolean array, merging gaps < 6 px.
    segments: List[Tuple[int, int]] = []
    in_run = False
    run_left = 0
    last_white = -1
    GAP_MERGE = 6
    for x in range(w):
        if per_x[x]:
            if not in_run:
                in_run = True
                run_left = x
            last_white = x
        else:
            if in_run and (x - last_white) > GAP_MERGE:
                segments.append((run_left, last_white))
                in_run = False
    if in_run:
        segments.append((run_left, last_white))
    return segments


def main(argv: List[str]) -> int:
    args = [a for a in argv[1:] if not a.startswith("-")]
    flags = [a for a in argv[1:] if a.startswith("-")]
    want_json = "--json" in flags
    if not args:
        print("usage: check-label-overlap.py <frame.png> [--json]", file=sys.stderr)
        return 2
    path = args[0]
    if not os.path.isfile(path):
        print(f"frame missing: {path}", file=sys.stderr)
        return 2
    try:
        w, h, rgba, bpp = decode_png(path)
    except Exception as e:
        print(f"decode failed: {e}", file=sys.stderr)
        return 2

    counts = near_white_count_per_row(rgba, w, h, bpp)
    clusters = find_text_clusters(counts)

    # Pair-check every cluster against every other cluster. We compare
    # ONLY clusters whose horizontal x-bands meaningfully overlap
    # (≥ 24 px shared x-extent), because two labels at different
    # players' houses sit at very different x ranges and aren't a
    # concatenation risk even when their y ranges abut.
    bands: List[Tuple[int, int, int, int]] = []  # (top, bottom, lx, rx)
    seg_per_cluster: List[List[Tuple[int, int]]] = []
    for top, bot, _ in clusters:
        lx, rx = cluster_x_band(rgba, w, h, bpp, top, bot)
        bands.append((top, bot, lx, rx))
        seg_per_cluster.append(find_x_segments(rgba, w, h, bpp, top, bot))

    failures: List[str] = []
    # Vertical-adjacency check (the original 'counter\nrandom' case).
    for i in range(len(bands)):
        for j in range(i + 1, len(bands)):
            ai = bands[i]
            aj = bands[j]
            xleft = max(ai[2], aj[2])
            xright = min(ai[3], aj[3])
            x_overlap = xright - xleft
            if x_overlap < 24:
                continue
            if ai[0] > aj[0]:
                ai, aj = aj, ai
            gap = aj[0] - ai[1] - 1
            if gap < MIN_GAP_PX:
                failures.append(
                    f"clusters at y=[{ai[0]}..{ai[1]}] and y=[{aj[0]}..{aj[1]}] "
                    f"share x-overlap={x_overlap}px with vertical gap={gap}px "
                    f"(< {MIN_GAP_PX}px). Likely 'random.nter'-style label concatenation."
                )

    # S-443 — horizontal-concatenation check. A single text cluster that
    # spans an unreasonably wide x-extent (> SINGLE_LABEL_MAX_W) is the
    # signature of 2 labels rendering on the same y row with their text
    # runs touching: 'random' + 'counter' merge into 'random.nter' as
    # one wide cluster.
    #
    # ROI guards (eliminate false positives from non-label near-white
    # pixels):
    #   - LABEL_BAND_TOP_Y / LABEL_BAND_BOT_Y: name labels live in
    #     the upper-middle of the frame (above the iso-tile centerline
    #     at ~y=400, above the hand picker at ~y=600). We restrict
    #     the segment scan to that band.
    #   - MOUNTAIN_X: the §H2.5 ambient mountain on the LEFT edge
    #     (x < 200) has snow caps that would otherwise read as a wide
    #     near-white cluster. Skip segments centred there.
    #   - BATTLE_LOG_LEFT_X: right-rail BattleLog has long CN runs;
    #     skip segments centred there.
    #   - PHASE_BANNER_Y: top-left phase banner ("第 6 回合 · 亮拳")
    #     uses near-white text on a wood plaque; skip rows above
    #     LABEL_BAND_TOP_Y already (via the band guard).
    #   - SKY_Y: the cloud sprite at the top of the frame is also
    #     near-white; the LABEL_BAND_TOP_Y guard already excludes it.
    SINGLE_LABEL_MAX_W = 110   # Character.tscn label is 100 px; +10 px slack.
    SINGLE_LABEL_MAX_H = 32    # Label is 20 px tall; +12 px slack for outline + sub-row noise.
    LABEL_BAND_TOP_Y = 100
    LABEL_BAND_BOT_Y = 350
    MOUNTAIN_X_MAX = 200
    BATTLE_LOG_LEFT_X = int(w * 0.78)
    for k, (top, bot, _) in enumerate(clusters):
        # Cluster must SIT within the label band (its top row inside).
        if top < LABEL_BAND_TOP_Y or top > LABEL_BAND_BOT_Y:
            continue
        cluster_in_label_zone = False
        for left, right in seg_per_cluster[k]:
            cx = (left + right) // 2
            if cx < MOUNTAIN_X_MAX:
                continue
            if cx >= BATTLE_LOG_LEFT_X:
                continue
            cluster_in_label_zone = True
            seg_w = right - left + 1
            if seg_w > SINGLE_LABEL_MAX_W:
                failures.append(
                    f"cluster at y=[{top}..{bot}] has x-segment "
                    f"[{left}..{right}] width={seg_w}px > {SINGLE_LABEL_MAX_W}px "
                    f"(single label max). Likely 'random.nter'-style horizontal "
                    f"concatenation of 2 labels at the same y."
                )
        # Vertical-stack-merge check: a single cluster taller than
        # SINGLE_LABEL_MAX_H px that sits in the label zone must be
        # 2+ labels merged because they're vertically too close. The
        # 'random.nter' regression had house-label 'counter' (24 px)
        # immediately abutting visitor-character-label 'random' (20 px)
        # producing a single cluster ~44 px tall.
        cluster_h = bot - top + 1
        if cluster_in_label_zone and cluster_h > SINGLE_LABEL_MAX_H:
            failures.append(
                f"cluster at y=[{top}..{bot}] has height={cluster_h}px > "
                f"{SINGLE_LABEL_MAX_H}px (single label max). Two adjacent "
                f"labels likely merged into one vertical run — the "
                f"'counter\\nrandom' → 'random.nter' regression."
            )

    summary = {
        "frame": path,
        "width": w,
        "height": h,
        "cluster_count": len(clusters),
        "clusters": [
            {"top_y": top, "bottom_y": bot, "peak": peak,
             "segments": seg_per_cluster[k]}
            for k, (top, bot, peak) in enumerate(clusters)
        ],
        "failures": failures,
        "pass": len(failures) == 0,
    }

    if want_json:
        print(json.dumps(summary))
    else:
        if summary["pass"]:
            print(f"OK label-overlap: {len(clusters)} text clusters, all gaps ≥ {MIN_GAP_PX}px")
        else:
            print(f"FAIL label-overlap: {len(failures)} adjacent-cluster gap(s) < {MIN_GAP_PX}px")
            for f in failures:
                print(f"  - {f}")
    return 0 if summary["pass"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
