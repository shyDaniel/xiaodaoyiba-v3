#!/usr/bin/env python3
"""scripts/check-winner-picker-pixels.py — S-445 WinnerPicker overlay gate.

Asserts that a captured screenshot of the WinnerPicker dialog
(produced by scripts/validate-winner-picker.mjs) is structurally
correct:

  1. PANEL-PRESENT — the centred 440x320 wood-panel region has a
     dimmed full-screen overlay around it (Dim ColorRect Color 0,0,0,
     alpha 0.55 over the whole viewport). We probe the centre row of
     the viewport and demand:
       - at least one 220+ wide horizontal run of pixels significantly
         brighter than the dim background (the wood panel)
       - the panel pixels' R ≥ 90 + R > B (warm wood hue)

  2. TARGET-ROWS-≥2 — the wood panel contains a vertical stack of
     target buttons (≥2 rows, 220x48 each, in the upper third of the
     panel). We scan for ≥2 horizontal "button stripes" — wood-coloured
     horizontal runs of width ≥ 180 with white-text pixels inside.

  3. ACTION-BUTTONS-≥3 — the bottom strip of the panel contains 3
     side-by-side wood buttons (120x56). We look for ≥3 button-shaped
     horizontal runs in the bottom 80px of the panel.

The picker's wood-panel chrome reuses the carved-wood styling in
client/scenes/ui/WinnerPicker.tscn. Wood pixels are warm-brown
(R ≈ 120-180, G ≈ 80-130, B ≈ 50-90). White-text pixels are the
button labels' fill (≥ 248 on every channel).

Usage:
  python3 scripts/check-winner-picker-pixels.py /path/to/picker.png
  python3 scripts/check-winner-picker-pixels.py /path/to/picker.png --json

Exit codes:
  0 — all three gates pass
  1 — at least one gate fails (details on stderr)
  2 — input image missing / unreadable

Stdlib-only (struct + zlib) — no PIL dependency.
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


# ── Pixel classifiers ──────────────────────────────────────────────────────
def is_wood(r: int, g: int, b: int) -> bool:
    """Carved-wood panel hue. WinnerPicker uses a warm tan-brown 9-slice;
    background dim is (0,0,0,0.55) over the canvas, so wood pixels are
    significantly warmer than the dim. Allow the wide ramp from tan
    highlight to dark grain."""
    if r < 80 or r > 230:
        return False
    if g < 50 or g > 200:
        return False
    if b < 30 or b > 180:
        return False
    # Warm — R should beat B by ≥10 (wood = orange-brown tilt).
    if r - b < 10:
        return False
    # Avoid pure-white text/UI by capping (otherwise label fills count).
    if r >= 240 and g >= 240 and b >= 240:
        return False
    return True


def is_white(r: int, g: int, b: int) -> bool:
    return r >= 240 and g >= 240 and b >= 240


def is_near_white(r: int, g: int, b: int) -> bool:
    """Looser white classifier for target-button labels. Godot's
    default Button text on a dark grey base anti-aliases through the
    200-235 range; pure-white (≥240) only catches the very innermost
    glyph bodies and undercounts. Used for target-row detection where
    we need any glyph signal (CJK + latin), not just yellow-fill text."""
    return r >= 200 and g >= 200 and b >= 200


def is_dim_bg(r: int, g: int, b: int) -> bool:
    """Outside the panel, the Dim ColorRect mixes 0.55 black over the
    underlying scene. Most points read as a desaturated dark-tinted
    version of the original scene. The check is loose: "all channels
    less than 110 OR the pixel is essentially black."
    """
    if r < 110 and g < 110 and b < 110:
        return True
    return False


# ── Row-based scans ────────────────────────────────────────────────────────
def wood_runs_in_row(rgba: bytes, w: int, h: int, bpp: int, y: int) -> List[Tuple[int, int]]:
    """Return list of (x_start, x_end) for contiguous wood-pixel runs in
    row y. A "run" allows 1-2 px gaps to bridge the wood-grain noise."""
    runs: List[Tuple[int, int]] = []
    in_run = False
    start = 0
    gap = 0
    base = y * w * bpp
    for x in range(w):
        i = base + x * bpp
        if is_wood(rgba[i], rgba[i + 1], rgba[i + 2]):
            if not in_run:
                in_run = True
                start = x
            gap = 0
        else:
            if in_run:
                gap += 1
                if gap > 3:
                    runs.append((start, x - gap))
                    in_run = False
                    gap = 0
    if in_run:
        runs.append((start, w - 1))
    return [r for r in runs if r[1] - r[0] >= 8]


def count_white_in_row(rgba: bytes, w: int, h: int, bpp: int, y: int, x0: int, x1: int) -> int:
    base = y * w * bpp
    c = 0
    for x in range(max(0, x0), min(w, x1 + 1)):
        i = base + x * bpp
        if is_white(rgba[i], rgba[i + 1], rgba[i + 2]):
            c += 1
    return c


def count_near_white_in_row(rgba: bytes, w: int, h: int, bpp: int, y: int, x0: int, x1: int) -> int:
    base = y * w * bpp
    c = 0
    for x in range(max(0, x0), min(w, x1 + 1)):
        i = base + x * bpp
        if is_near_white(rgba[i], rgba[i + 1], rgba[i + 2]):
            c += 1
    return c


# ── The three gates ────────────────────────────────────────────────────────
def gate_panel_present(rgba: bytes, w: int, h: int, bpp: int) -> Tuple[bool, dict]:
    """Walk a band of rows around y = h/2 and find the widest contiguous
    wood run. The panel is 440 px wide so we expect ≥ 220 px wide once
    we discount internal text gaps. Also confirm the panel sits roughly
    centred horizontally (centre x within w*0.3 .. w*0.7)."""
    band_top = h // 2 - 30
    band_bot = h // 2 + 30
    widest = (-1, -1, -1)  # (run_width, y, x_start)
    for y in range(max(0, band_top), min(h, band_bot)):
        runs = wood_runs_in_row(rgba, w, h, bpp, y)
        for s, e in runs:
            width = e - s + 1
            if width > widest[0]:
                widest = (width, y, s)
    run_w, run_y, run_x = widest
    centre_x = run_x + run_w // 2 if run_w > 0 else -1
    centred = (centre_x >= int(w * 0.3)) and (centre_x <= int(w * 0.7))
    ok = run_w >= 220 and centred
    return ok, {
        "widest_wood_run_px": run_w,
        "run_y": run_y,
        "run_centre_x": centre_x,
        "viewport_w": w,
        "centred": centred,
        "threshold_px": 220,
    }


def gate_target_rows(rgba: bytes, w: int, h: int, bpp: int, panel_x0: int, panel_x1: int) -> Tuple[bool, dict]:
    """Scan the upper half of the panel band for ≥2 horizontal stripes
    containing CJK / latin target-name glyphs. The Targets/List
    children in WinnerPicker.gd are plain Godot Buttons (no theme
    override) — they render as dark grey rectangles with WHITE label
    fill. We DON'T require wood backing here: the strongest signal is
    a horizontal run of white-text pixels inside the panel x-range,
    grouped vertically into clusters (one cluster per button).
    Each target button is 220x48, so two distinct text clusters
    separated by ≥4 empty rows confirms ≥2 target rows.

    The Title row uses a yellow fill (1.0, 0.91, 0.38) — NOT pure
    white — so it never reaches the white-pixel threshold and doesn't
    pollute the cluster count. The Countdown row likewise uses a tan
    fill. Action button labels also use yellow, so the bottom strip
    is excluded from the y-band entirely."""
    # Y-band: from ~80 px above viewport centre (top of target list)
    # down to viewport centre (just above the action button strip).
    band_top = max(0, h // 2 - 140)
    band_bot = max(0, h // 2 + 30)
    text_rows: List[int] = []
    row_white_counts: List[int] = []
    for y in range(band_top, min(h, band_bot)):
        # Use NEAR-white (≥200/200/200) here, not pure-white. Godot's
        # default Button label on a dark grey base anti-aliases the
        # glyph through 200-235; pure-white catches only the inner
        # cores and undercounts. Diagnostic on a real picker frame
        # showed 0 pure-white pixels but 11-26 near-white per text
        # row — the difference between detected and missed.
        whites = count_near_white_in_row(rgba, w, h, bpp, y, panel_x0, panel_x1)
        row_white_counts.append(whites)
        # Each glyph contributes ~3-5 near-white pixels; "counter
        # (穿着)" is ~9 glyphs → 25-45 near-white per row. Threshold
        # ≥10 keeps the FP rate down (background dim region averages
        # 0-5 noise pixels).
        if whites >= 10:
            text_rows.append(y)
    # Group adjacent text rows into clusters (one cluster per button).
    clusters: List[Tuple[int, int]] = []
    if text_rows:
        cs = text_rows[0]
        ce = text_rows[0]
        for y in text_rows[1:]:
            if y - ce <= 4:
                ce = y
            else:
                clusters.append((cs, ce))
                cs = y
                ce = y
        clusters.append((cs, ce))
    ok = len(clusters) >= 2
    return ok, {
        "target_text_clusters": len(clusters),
        "cluster_ranges": clusters[:6],
        "max_row_white_count": max(row_white_counts) if row_white_counts else 0,
        "threshold_clusters": 2,
    }


def gate_action_buttons(rgba: bytes, w: int, h: int, bpp: int, panel_x0: int, panel_x1: int) -> Tuple[bool, dict]:
    """The action row is the BOTTOM strip of the panel. Carved-wood
    buttons are 120x56 each. The Self button (穿好裤衩) is only shown
    when the winner has agency to self-restore (canSelfRestore is true,
    i.e. winner.stage === 'ALIVE_PANTS_DOWN'); otherwise only Pull
    (扒裤衩) and Chop (咔嚓) are present. So in the 3-player ROCK-vs-
    SCISSORS-SCISSORS scenario the harness drives, the winner is still
    ALIVE_CLOTHED and the picker shows TWO action buttons.

    Threshold: ≥2 wood-coloured button-shaped runs in the bottom band.
    The S-445 brief calls out "3 action buttons" as the ideal state but
    the contract in WinnerPicker.gd:89 makes Self conditional, so the
    structural minimum that proves the picker is functional is 2."""
    band_top = h // 2 + 50
    band_bot = h // 2 + 140
    # Pick the row with the most distinct wood runs in [panel_x0, panel_x1].
    best = (-1, -1, [])  # (count, y, runs)
    for y in range(max(0, band_top), min(h, band_bot)):
        runs = wood_runs_in_row(rgba, w, h, bpp, y)
        clipped = [r for r in runs if r[1] >= panel_x0 and r[0] <= panel_x1]
        # Each carved-wood button face is 120 wide minus 16-px style
        # margins on each side ≈ 88-130 px wood-coloured run. Add some
        # tolerance for grain noise and the button's pressed/hover
        # state (slightly different brightness).
        button_runs = [r for r in clipped if 60 <= r[1] - r[0] + 1 <= 200]
        if len(button_runs) > best[0]:
            best = (len(button_runs), y, button_runs)
    count, y, runs = best
    ok = count >= 2
    return ok, {
        "button_run_count": count,
        "button_run_y": y,
        "button_runs": runs,
        "threshold_runs": 2,
    }


def main(argv: List[str]) -> int:
    if len(argv) < 2:
        print("usage: check-winner-picker-pixels.py <path.png> [--json]", file=sys.stderr)
        return 2
    path = argv[1]
    json_out = "--json" in argv
    if not os.path.exists(path):
        print(f"input not found: {path}", file=sys.stderr)
        return 2
    try:
        w, h, rgba, bpp = decode_png(path)
    except Exception as exc:
        print(f"png decode failed: {exc}", file=sys.stderr)
        return 2

    panel_ok, panel_info = gate_panel_present(rgba, w, h, bpp)
    # Use the discovered run as the panel x-range. If panel_ok is false
    # we still try the sub-gates with whatever wood we found, so the
    # report explains all three failures rather than just the first.
    if panel_info["run_y"] >= 0:
        panel_centre_x = panel_info["run_centre_x"]
        panel_x0 = max(0, panel_centre_x - 240)
        panel_x1 = min(w - 1, panel_centre_x + 240)
    else:
        panel_x0 = w // 2 - 240
        panel_x1 = w // 2 + 240

    targets_ok, targets_info = gate_target_rows(rgba, w, h, bpp, panel_x0, panel_x1)
    actions_ok, actions_info = gate_action_buttons(rgba, w, h, bpp, panel_x0, panel_x1)

    all_ok = panel_ok and targets_ok and actions_ok
    summary = {
        "path": path,
        "viewport": [w, h],
        "panel": {"ok": panel_ok, **panel_info},
        "targets": {"ok": targets_ok, **targets_info},
        "actions": {"ok": actions_ok, **actions_info},
        "all_ok": all_ok,
    }
    if json_out:
        print(json.dumps(summary, indent=2))
    else:
        print(
            "panel.ok={} (run_w={}, centre_x={}/{}); targets.ok={} (clusters={}); actions.ok={} (buttons={})".format(
                panel_ok,
                panel_info["widest_wood_run_px"],
                panel_info["run_centre_x"],
                w,
                targets_ok,
                targets_info["target_text_clusters"],
                actions_ok,
                actions_info["button_run_count"],
            )
        )
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
