# Worklog

Append-only iteration log for xiaodaoyiba v3. Newest entries on top.

## Iteration 16 — S-176 — §C8 nickname pills land in the README hero (no more silent CJK fallback)

**Bug:** iter-15 (S-169) replaced the in-roof Label with a hand-rolled
5×7 ASCII bitmap font that has no CJK glyphs. The committed
`docs/screenshots/action.png` showed BattleLog body lines in English
("Ming preps", "Hong's pants") but **zero nicknames** anywhere on the
four houses — 机器人甲 / 小明 / 小红 / 机器人乙 hit the missing-glyph
fallback and dropped silently. The §C8 "per-player stable name colors"
acceptance went from low-contrast purple-on-cream to absent entirely.

**Fix (option c from the brief — anglicise nicknames in the static
mock):** added a `name` + `name_color` field per `PLAYERS` entry in
`client/tests/render_action_static.gd` with Latin-only nicks
**Bot-A / Bot-B / Hong / Ming** that the embedded ASCII bitmap font
*can* render. Each house now gets a `_blit_nickname_pill()` call that
draws a 33-px-tall dark rounded rect (`Color(0.06, 0.07, 0.10, 0.85)`)
above the roof peak with a 1-px stroke in the player's stable
name-color and the nickname rendered in white scale-3 bitmap glyphs
(21 px tall × 5-pixel-wide letters, well above the 12-px legibility
floor). Pill width auto-sizes to `_measure_text(name, 3) + 20px`
padding so the layout stays clean for both 4-char ("Bot-A") and
4-char ("Hong"/"Ming") names. Updated the README hero alt-text to
match the now-Latin nicks (was: "knife in 小明's hand, persistent
shame on 机器人甲", now: "Bot-A, Bot-B, Hong, Ming, knife in Bot-A's
hand, persistent red briefs on Hong"). The runtime Godot client
continues to use the original CJK names via system Noto Sans CJK
fallback — only the static mock is anglicised, and the rationale is
documented in a leading comment block on `PLAYERS`.

**Acceptance test (verbatim from S-176 brief) — passes:**
- `docs/screenshots/action.png` contains 4 distinct legible nicknames
  (Bot-A / Bot-B / Hong / Ming), each rendered at scale=3 → 21 px
  tall (≥ 12 px floor ✓) ✓
- Contrast ≥ 4.5:1: white-on-(0.06, 0.07, 0.10, 0.85) effective
  background → ≈ 16.7:1 ✓ (well above floor)
- `render_action_static.gd` no longer silently drops player names
  (every entry in `PLAYERS` is rendered through `_blit_nickname_pill`,
  not the missing-glyph code path) ✓
- `pnpm test` → **90/90 green** (79 shared + 11 server) ✓
- Re-rendered `docs/screenshots/action.png` opened with Read shows
  all 4 nickname pills with colored strokes matching their roof
  hues ✓

**Visual evidence:** opened the regenerated 1280×720 PNG with the Read
tool — Bot-A pill (red stroke, top-left over pink-roof house), Bot-B
pill (blue stroke, top-right over blue-roof house), Hong pill (green
stroke, mid-left near green-roof house with red briefs on character),
Ming pill (yellow stroke, mid-right near yellow-roof house). All four
labels are crisp, dark-pilled, and unambiguous.

## Iteration 13 — S-155 — §F1 README rewrite: status reflects shipped iterations 1–12

**Bug:** README.md:60-64 still read "Iteration 1 (S-001) scaffolded the
pnpm workspace root. The Godot client, the v2 server port, and the
headless sim are pending in subsequent subtasks." That was true at
iteration 1 but flatly false by iteration 12 — pnpm test 90/90 green,
sim healthy, Godot HTML5 build present, audio shipped, CI workflow
landed, codegen-timing drift gate live. A first-time HN visitor reading
the README would conclude the project is a half-built scaffold.

**Fix:**
1. Copied `/tmp/xdyb_action.png` (rendered by `client/tests/render_game.gd`
   against the committed Godot project) to `docs/screenshots/action.png`
   and embedded it as a hero image right under the pitch paragraph so
   anyone scrolling the README sees what the game actually looks like
   without cloning.
2. Replaced the stale Status section with six paragraphs enumerating
   exactly what's shipped: TS shared+server (90 tests, S-002/S-003),
   headless sim CLI with the canonical seed=42 acceptance numbers
   (tie_rate 0.260, max winner 0.40, PULL_OWN_PANTS_UP ≥ 1, S-004),
   Godot HTML5 client (iso ground, procedural sprite atlas, knife
   sprite, NotoColorEmoji-rendered ✊✋✌, persistent shame, winner
   picker, S-005/S-098/S-109/S-119), 8 SFX + 3 BGM cross-fade audio
   bus (S-148), full §E5 CI workflow + codegen-drift gate (S-129/S-139),
   and the codegen-timing single-source-of-truth wiring (S-129).
3. Added a small "Outstanding" section that points to the open §C11
   viral-aesthetic / animation-trace / ZOOM_IN-IN-effects items so the
   reader knows what's in flight without pretending it's done.
4. Refreshed the Quickstart and Repo-layout blocks to surface
   `pnpm codegen:timing`, `pnpm codegen:audio`, `docs/screenshots/`,
   `shared/scripts/codegen-timing.ts`, and `.github/workflows/`.

**Acceptance test (verbatim from S-155 brief) — passes:**
- `grep -c 'Iteration 1 (S-001)' README.md` → **0** ✓
- `grep -c 'pending in subsequent' README.md` → **0** ✓
- README contains `![...](./docs/screenshots/action.png)` ✓
- `docs/screenshots/action.png` is a committed 80 KB PNG ✓
- `pnpm test` → **90/90 green** (79 shared + 11 server) in <1s ✓

No source-code changes; docs-only iteration.

## Iteration 12 — S-148 — §D1/§D2 audio: 8 SFX + 3 BGM WAVs from offline ZzFX

**Bug:** `client/assets/audio/sfx/` and `client/assets/audio/bgm/` were
empty; `Audio.gd._try_load_sfx`/`_try_load_bgm` returned null and
`play_sfx()` silently no-op'd. The full gameplay loop
(REVEAL → ACTION → IMPACT → VICTORY) shipped silent — failed the
FINAL_GOAL §D1/§D2 viral aesthetic gate ("every action must have a SFX").

**Fix:** Added `scripts/codegen-audio.mjs` — an offline Node port of
the v2 ZzFX 1.3.2 micro-renderer (from
`xiaodaoyiba-v2/packages/client/src/audio/zzfx.ts`) that synthesizes
44.1 kHz / 16-bit / mono PCM WAVs at build time. The 19-parameter ZzFX
voice model is preserved verbatim; the only delta vs. v2 is that
`Math.random()` is replaced by a `mulberry32` PRNG seeded by the
preset name so build output is byte-deterministic (no CI churn).

Generated assets per FINAL_GOAL §D1/§D2:

- `client/assets/audio/sfx/{tap,reveal,pull,chop,dodge,thud,victory,defeat}.wav`
  (8 slots, 130-1040 ms each; multi-voice presets `pull`, `victory`,
  `defeat` mix layered ZzFX calls at the original v2 setTimeout offsets).
- `client/assets/audio/bgm/{lobby,battle,victory}.wav` (3 variants,
  ~10-13 s each — 4 bars × 16 steps of the v2 pentatonic-on-C tracks
  so cross-fades stay musically continuous).

The script also writes Godot `.import` sidecars per file with
`edit/loop_mode=2` (Forward) for BGM and `edit/loop_mode=1` (Disabled)
for SFX — Godot 4.3 ResourceImporterWAV enum per PR #59170. Without
this, generated WAVs (no `smpl` chunk) default to "Detect → Disabled"
and BGM ends after one play; runtime can't override.

Wiring: `pnpm codegen:audio` task added; `scripts/build.sh` runs it
before `godot --import`; `.github/workflows/ci.yml` runs it before the
Godot import step and adds a new `tests/audio_smoke.gd` headless gate
that asserts every named SFX slot and BGM variant resolves to a
non-null `AudioStreamWAV` and that BGM loop_mode == LOOP_FORWARD.

**Local verification:**
- `pnpm test` → 90/90 green (79 shared + 11 server) in ~0.9 s.
- `node scripts/codegen-audio.mjs` → 8 SFX + 3 BGM written
  (3.2 MB total — well under §E3 6 MB cap).
- `godot --headless --path client --import` → exit 0, all 11 WAVs
  imported to `res://.godot/imported/<name>-*.sample`.
- `godot --headless --path client --script tests/audio_smoke.gd
  --quit` → all 11 streams load, BGM loop_mode=1 (LOOP_FORWARD)
  → "audio_smoke: PASS (8 sfx + 3 bgm)".
- Signal levels sanity-checked: `chop.wav` RMS 0.106 peak 0.29,
  `lobby.wav` RMS 0.017 peak 0.10 — well above noise floor, with
  headroom for Audio.gd's -6 dB nominal bus.

**Acceptance gate (subtask brief):**
- `ls client/assets/audio/sfx/*.wav | wc -l` → **8** ✓
- `ls client/assets/audio/bgm/*.{ogg,wav} | wc -l` → **3** ✓
- `godot --headless --path client --import` → 0 errors ✓
- 4 distinct SFX (tap/reveal/pull/chop) + 3 BGM cross-fade variants
  load via `Audio.gd`'s exact `ResourceLoader.exists` path ✓.

## Iteration 11 — S-139 — §E5 full CI workflow

**Bug:** `.github/workflows/` contained only the narrow `codegen-drift.yml`
gate from S-129. FINAL_GOAL §E5 demands a per-push CI job that installs
Godot 4.3-stable and runs `pnpm install && pnpm test && pnpm sim
--players 4 --bots counter,random,iron,mirror --winner-strategy
random-target+random-action --rounds 50 --seed 42 --strict && godot
--headless --path client --import`. None of those four steps were
gating PRs — drift in tests, RPS distributions, or the Godot project
import would land silently.

**Fix:** Added `.github/workflows/ci.yml` (job name `ci`) running the
exact four-step pipeline from §E5 on every push and PR:

1. `pnpm install --frozen-lockfile` (pnpm 9 + Node 20 + lockfile cache).
2. `pnpm test` (vitest, currently 90 tests across `shared/` + `server/`).
3. `pnpm sim` with the canonical S-129 args + `--strict` (seed=42, 50
   rounds, 4 players, mixed bot strategies, random-target+random-action
   winner picker — exercises the §A3 `PULL_OWN_PANTS_UP` agency code
   path and the §A2 distribution budget).
4. Hermetic Godot 4.3-stable install via `curl` of the pinned GitHub
   release tarball (`Godot_v4.3-stable_linux.x86_64.zip`) followed by
   `godot --headless --path client --import` (Godot 4.x's standard
   Linux binary supports `--headless` natively, so no separate
   "headless build" is needed). `concurrency.cancel-in-progress`
   prevents stacked runs from a single branch.

**Local verification before commit:**
- `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"`
  → ok.
- `pnpm test` → 90/90 green (79 shared + 11 server) in ~0.7s.
- `pnpm sim ... --strict` → exit 0, tie_rate 0.260, no winner > 0.40,
  `PULL_OWN_PANTS_UP` fires (game 6 round 2), §A2/§A3 budgets clean.
- The Godot import step is exercised in CI itself; locally `godot
  --headless --path client --import` is the same invocation the prior
  iterations have used to validate the project tree, and `pnpm
  godot:import` already wraps it.

The narrow `codegen-drift.yml` from S-129 stays — it runs in parallel
on the same triggers and remains the single source of truth for §A4
drift detection.

## Iteration 10 — S-129 — §A4 ship `pnpm codegen:timing` + drift CI

**Bug:** `pnpm codegen:timing` exited `ERR_MODULE_NOT_FOUND` because the
script it pointed at, `shared/scripts/codegen-timing.ts`, did not exist.
Meanwhile `client/scripts/generated/Timing.gd` claimed in its banner to be
"regenerated by `pnpm codegen:timing`" but was being hand-maintained, and
carried six constants (`ZOOM_IN_DUR_MS`, `ZOOM_HOLD_MS`, `ZOOM_OUT_DUR_MS`,
`ZOOM_TARGET`, `WINNER_CHOICE_BUDGET_MS`, `PICKER_AUTO_PICK_MS`) that had
no source in `shared/src/game/timing.ts`. Drift detection in CI was
impossible.

**Fix:**
1. Promoted the six GD-only constants to `shared/src/game/timing.ts` so
   it is genuinely the single source of truth per §A4.
2. Wrote `shared/scripts/codegen-timing.ts` — imports those constants
   and writes `client/scripts/generated/Timing.gd` byte-for-byte
   matching the committed file (verified by `sha256sum` and `git diff
   --exit-code` after a clean `rm`+regen).
3. Refactored `server/src/rooms/Room.ts` to import
   `WINNER_CHOICE_BUDGET_MS` from `@xdyb/shared` instead of declaring
   its own `9000` literal — eliminating the last drift surface.
4. Added `.github/workflows/codegen-drift.yml` (a narrow CI gate that
   re-runs `pnpm codegen:timing` and fails if the regenerated file
   differs from what was committed). Full §E5 CI lives in a separate
   bullet.

**Acceptance test (verbatim from S-129 brief) — passes:**
```
$ rm client/scripts/generated/Timing.gd && pnpm codegen:timing && \
    git diff --exit-code client/scripts/generated/Timing.gd
codegen:timing → .../client/scripts/generated/Timing.gd
ACCEPTANCE PASS                # exit 0
```

`pnpm test` → 90/90 green (79 shared + 11 server, unchanged). Typecheck
clean. No behavior change for the running game — only a wiring fix that
makes drift detectable.

## Iteration 9 — S-119 — VIRAL AESTHETIC GATE (§C11): procedural sprite atlas + knife

**Bug:** Iteration 8 fixed the throw glyphs but every character was still
a 4-rect Polygon2D stack (legs/torso/head/optional briefs) and every house
was 5 polygons (walls/roof/door/2 windows). The product is literally named
"小刀一把冲到你家" yet there was **no knife sprite anywhere**. §C11 says
"would you screenshot this and send to a friend" — first render: no.

**Strategy:** procedurally generate a pixel-art bitmap atlas at boot via
offscreen `Image.create()` rather than dropping PNGs (FINAL_GOAL §G says
the project must self-bootstrap with no binary asset uploads beyond
fonts).

**Added** `client/scripts/globals/SpriteAtlas.gd` (~600 lines, autoload).
Renders into `ImageTexture`s at startup:
- `character_textures` — 96×128 sprites for each of 5 states
  (`ALIVE_CLOTHED`, `ALIVE_PANTS_DOWN`, `RUSHING`, `ATTACKING`, `DEAD`)
  with shaded body parts, hair cap, per-state face features (eyes, mouth,
  X-eyes for DEAD), shoes, ground shadow ellipse, single-pixel outline.
- `house_textures` — 192×160 sprites across 4 damage stages with peaked
  shaded roof, chimney, framed windows with cross-bars, door + knob,
  jagged crack lines and a destroyed door at stage 3.
- `knife_texture` — 56×20 with handle, guard, tapered blade with bevel
  highlight.
- Throw FX dot sprites (R / P / S accent particles).

**Rewired** `Character.tscn` to a single `Body: Sprite2D` + `Knife:
Sprite2D` child (offset pivots blade rotation around the handle).
`Character.gd._refresh_visual()` now reads the texture from the atlas by
state-name string and modulates with a per-player hue tint
(`Color.from_hsv(color_hue, 0.45, 1.0)` lerped at 45% so skin/hair stay
readable). `_swing_knife()` runs a 3-stage tween: cocked back (-1.6 rad)
→ chop forward (1.0 rad) → rest (-0.4 rad).

**Rewired** `House.tscn` to `Body: Sprite2D` + `RoofTint` overlay.
`House.gd.show_damage()` now advances `_stage` (0..3) and swaps the
underlying texture, so the door visibly chops up across rounds.

**Layout fixes:**
- `GameStage.gd`: character now placed at `house_pos + Vector2(0, 64)`
  (was `+8`) so it stands in front of, not inside, the house. House
  position no longer offset by `Vector2(0, -32)`; the sprite's own
  internal offset (Body at `Vector2(0, -38)`) handles ground anchoring.
- `Background.tscn`: replaced the harsh "sun-glow" yellow rectangle
  with a subtle warm-horizon band (`Color(0.95, 0.78, 0.55, 0.45)` at
  y=280..420) and brightened the sky to `Color(0.50, 0.68, 0.82)`.
  Mountain polygons repositioned so the silhouettes sit at/above the
  iso horizon.
- `BattleLog.tscn` / `Game.tscn`: rail narrowed `280×460 → 220×360` and
  shifted from `(980, 20)` to `(1050, 70)` so it no longer covers
  小明's house in 1280×720 builds.

**GDScript-4.3 traps hit:**
- `var foo := max(...)` infers `Variant` and refuses to compile under
  strict mode. Replaced with typed `mini` / `maxi` / `absi` / `clampi`
  / `maxf` everywhere in `SpriteAtlas.gd`.
- Bare autoload identifier `SpriteAtlas.x` doesn't always resolve at
  parse time depending on load order. Added `_atlas() -> Node` helper
  in both `Character.gd` and `House.gd` returning
  `get_node_or_null("/root/SpriteAtlas")`.
- `set_player_color()` is called from `GameStage._spawn_player()`
  **before** the House has run `_ready()`, so `@onready var _body`
  was still null and assigning to `.texture` crashed. Added an early
  null-guard in `_apply_textures()`; `_ready()` re-invokes it once
  onready vars resolve.

**Test:** `tests/render_game.gd` now also drives p1 (小明) into the
`ATTACKING` state before screenshotting so the captured frame proves
the knife sprite is rendered. PASS — `/tmp/xdyb_action.png` shows 4
characters with discernible faces, knife in 小明's hand, red briefs on
机器人甲 (persistent shame), all 3 ✊✋✌ glyphs above heads + on
HandPicker buttons, mountains on the horizon, no flat ≥48px monochrome
rectangles. `pnpm test` still 90/90 (79 shared + 11 server).

## Iteration 8 — S-109 — render ✊✋✌ via NotoColorEmoji CBDT/CBLC font (§C9)

**Bug:** §C9 says "REVEAL phase shows every alive player's throw glyph
(✊ ROCK / ✋ PAPER / ✌️ SCISSORS, ≥ 64px) above their character" and
the HandPicker offers the same three glyphs as buttons. Both rendered
as ▢ missing-glyph boxes because Godot's default theme font has no
emoji codepoints. Same root cause for both surfaces.

**Fix (font asset):** dropped
`client/assets/fonts/NotoColorEmoji.ttf` (9.8MB,
`NotoColorEmoji-noflags.ttf` from googlefonts/noto-emoji main).
Selected the CBDT/CBLC embedded-bitmap variant rather than the
COLR/CPAL or SVG variants because Godot 4.3's font renderer
ships first-class CBDT/CBLC support; COLR/CPAL is silently
unsupported, and Godot's SVG-in-OT path has known incomplete
coverage. The accompanying `.import` sidecar overrides
**`disable_embedded_bitmaps=false`** (Godot's default is `true`,
which would suppress the very bitmap strikes that draw the colour
glyph) and sets `allow_system_fallback=true` so the OS-level Noto
Sans CJK still serves the Chinese labels.

**Fix (gitignore):** removed the `*.import` wildcard from
`.gitignore`. The `.import` sidecar is what carries the
`disable_embedded_bitmaps=false` override; if it isn't in git, a
fresh clone would re-import with the Godot default and silently
break emoji rendering. Per-machine cache stays ignored
(`client/.godot/`, `client/.import/`).

**Fix (HandPicker.tscn):** the buttons used to read "✊ 石头" /
"✋ 布" / "✌ 剪刀" in a single text run, which mixed CJK and emoji
on one font slot. Restructured to a two-layer layout: button face
shows pure emoji ("✊"/"✋"/"✌") at `font_size=64` with the emoji
font; a child Label anchored to the bottom of each button shows
the CJK label ("石头"/"布"/"剪刀") at `font_size=16` with the
default theme font. Buttons are now `180×100` so the emoji has
breathing room.

**Fix (Character.tscn):** added the emoji FontFile as
`ext_resource id=2_emoji` and applied it to the existing
`ThrowGlyph` Label as `theme_override_fonts/font` with
`theme_override_font_sizes/font_size = 64`. Repositioned the
label to `offset_top = -160 / offset_bottom = -96` so the glyph
floats clearly above the 96-px character sprite. Also added a
black outline (`outline_size=6`) so the glyph reads against any
background tile.

**Verified:**
- `pnpm test` → 90 tests passed (79 shared + 11 server) — no
  regressions in the gameplay engine from the asset add.
- `godot --path client --import` succeeds; the `.fontdata` cache
  populates under `client/.godot/imported/`.
- `godot --path client --script res://tests/render_game.gd
  --quit-after 30` (no `--headless`; uses WSLg X11 + Mesa
  llvmpipe so `get_viewport().get_texture()` actually allocates)
  writes `/tmp/xdyb_action.png`. The PNG shows all four
  characters spawned (机器人乙, 小明, 机器人甲, 小红), each
  carrying its assigned reveal glyph in full colour above its
  head: ✊ over 机器人乙 + 小明, ✋ over 小红, ✌ over
  机器人甲. The HandPicker strip below shows the three buttons
  as ✊石头 / ✋布 / ✌剪刀, emoji in colour at 64 px, CJK in
  white at 16 px. 机器人甲's `ALIVE_PANTS_DOWN` red briefs
  render correctly. PhaseBanner reads `R1 · REVEAL`.
  BattleLog rail shows the 战斗日志 header.

**Test added:** `client/tests/render_game.gd` injects a 4-player
REVEAL snapshot into `GameState`, instantiates `Game.tscn`, calls
`Character.show_throw(glyph)` per-player to bypass the auto-hide
timer baked into `GameStage.show_rps_reveal()`, then dumps
`/tmp/xdyb_action.png`. Asserts `n_chars >= 4` and that
HandPicker has 3 buttons before exit-0.

**Outstanding (next iteration candidates):** §C11 viral aesthetic
gate (sprites still procedural); §A4 codegen-timing.ts; §E5
GitHub Actions workflow; characters still render inside house
walls in Game.tscn at certain zoom levels; parallax mountain
band sometimes clips off-viewport top.

## Iteration 5 — S-005 — scaffold the Godot 4.3 client tree

**Did:** Built the entire `client/` Godot project tree from empty.
That's `project.godot` (with autoloads `Timing`, `Net`, `GameState`,
`Audio`, GL Compatibility renderer, 1280×720 viewport), a procedurally-
drawn `icon.svg`, an `export_presets.cfg` Web preset with thread
support and PWA-style COOP/COEP headers, four GDScript autoloads
(`Net.gd` speaks Engine.IO v4 / Socket.IO v4 directly over
`WebSocketPeer` — no addon — emitting/consuming `room:*` events;
`GameState.gd` keeps the room snapshot and routes `room:effects` /
`room:winnerChoice`; `Audio.gd` is the SFX/BGM bus with mute
persisted to `user://settings.cfg`; `Timing.gd` is the codegen
target with the ms constants from `shared/src/game/timing.ts`),
five gameplay scripts (`Camera.gd` runs three-stage cinematic
zoom-pan-zoom for §C2; `EffectPlayer.gd` schedules `Effect[]`
dispatches by `atMs`; `GameStage.gd` owns the iso world and
characters; `Ground.gd` paints the iso diamond lattice via
`_draw()` because a `TileMap` would require an atlas texture;
`House.gd` is the player station), `Character.gd` (state machine
ALIVE_CLOTHED | ALIVE_PANTS_DOWN | RUSHING | ATTACKING | DEAD,
with `set_persistent_pants_down()` for §C7 persistent shame), six
UI scripts (Main router, Landing, Lobby, BattleLog right-rail,
HandPicker, WinnerPicker §H3 agency dialog), and 16 `.tscn` scene
files including four `GPUParticles2D` emitters
(Dust/Cloth/WoodChip/Confetti). Every visual is procedural (no PNG
or WAV) so the project boots without art uploads per FINAL_GOAL §G.

**Verified (acceptance for S-005):**
- `godot --headless --path client --import` populates `client/.godot/`
  (script class cache, UID cache, imported icon) without errors. A
  follow-up smoke script that `load(...)` + `instantiate()`s every
  one of the 16 `.tscn` files prints `OK` for all and exits 0,
  proving the entire scene graph parses cleanly with the strict
  GDScript Variant-inference checks Godot 4.3 enforces.
- `godot --headless --path client --export-release "Web" build/index.html`
  produces `client/build/{index.html, index.js (378K), index.wasm
  (33M), index.pck (84K), index.png, index.audio.worklet.js,
  index.worker.js}`. The .pck bundles all 16 scenes + 16 scripts
  +`.import/global_script_class_cache.cfg` + `project.binary`.
- `pnpm serve` (scripts/serve-html5.sh) listens on :5173 with COOP/
  COEP/CORP headers; `curl -I` shows `Cross-Origin-Opener-Policy:
  same-origin` and `Cross-Origin-Embedder-Policy: require-corp`.
  `curl` of every bundle file (index.html, index.js, index.wasm,
  index.pck, index.png) returns 200 with non-zero size.
- The `index.html` bootstrap matches the canonical Godot 4.3 HTML5
  template (status splash, `#canvas`, no external CDN deps).

**What's NOT verified in this iteration:** Browser-driven
end-to-end via Playwright / chrome-devtools MCP. The Chromium
binary at `~/.cache/ms-playwright/chromium-1217/chrome-linux64/chrome`
fails with `error while loading shared libraries: libnspr4.so:
cannot open shared object file` — `libnspr4` isn't installed and
this WSL2 sandbox doesn't grant `sudo apt install`. The MCP-managed
chrome-devtools instance also closes target on launch attempt for
the same reason. The build is structurally sound (HTTP 200 on every
asset, valid Godot 4.3 HTML5 boilerplate, COOP/COEP headers correct)
but a human or a CI runner with `libnspr4 libnss3 libasound2`
installed needs to confirm the Landing → Lobby → Game traversal
visually. This is an environment limitation, not a code defect.

**HTML5 bundle size:** 33 MB (dominated by 33 MB `index.wasm` —
that's the Godot 4.3 thread-enabled wasm template baseline).
Exceeds the 6 MB **soft** target in FINAL_GOAL §E3. Mitigations
(none blocking S-005): switch to no-threads template, custom
Godot build with modules stripped, or accept the size — wasm
gzips to ~9 MB on the wire. Documented in ARCHITECTURE.md
"HTML5 bundle".

**Notes for next iteration:** S-006 (`shared/scripts/codegen-timing.ts`)
should still land — `client/scripts/generated/Timing.gd` was
written manually mirroring the current ms values, but a real
codegen script enforces drift detection in CI per FINAL_GOAL §A4.
Also: the procedural-everything approach means hand-drawn art
(FINAL_GOAL §C4 "characters ≈ 96 px tall, houses ≈ 192 px") slots
in by replacing `Polygon2D` shapes with `Sprite2D` + `AtlasTexture`
references — no scene-graph rewiring needed.

## Iteration 4 — S-004 — port server/sim.ts headless CLI verbatim from v2

**Did:** Replaced the 3-line `console.log` placeholder at `server/src/sim.ts` with the verbatim port from `xiaodaoyiba-v2/packages/server/src/sim.ts` (738 lines). Also ported `server/src/sim.test.ts` (136 lines, 7 vitest specs covering the strict-mode exit-code policy + the canonical seed=42 / 4-bot acceptance run + the known-bad mirror-only exit-1 guard). Every symbol the sim imports from `@xdyb/shared` (`ACTION_TOTAL_MS`, `PHASE_T_REVEAL`, `ROUND_TOTAL_MS`, `BOT_STRATEGIES`, `getBotStrategy`, `isBotKind`, `resetBotCaches`, `resolveRound`, `resolveRps`, `seededRng`, `SHARED_PACKAGE_VERSION`, `ActionKind`, `BotContext`, `BotKind`, `BotStrategy`, `Effect`, `PlayerState`, `RoundHistoryEntry`, `RoundInputs`, `Rng`, `RpsChoice`) is already exported by the S-002 barrel — the port compiled clean with zero shimming.

**Verified (acceptance for S-004 = FINAL_GOAL §A1–A4):**
- `pnpm sim --players 4 --bots counter,random,iron,mirror --winner-strategy random-target+random-action --rounds 50 --seed 42` → **5 games, 50 rounds, 13 ties, tie_rate=0.260, max winner share = 2/5 = 0.40, PULL_OWN_PANTS_UP fires twice (rounds 28 & 48), duration_ms=8** (≪ 2000ms budget). All §A2 budgets pass: tie_rate < 0.30 ✓, no winner > 0.60 ✓, PULL_OWN_PANTS_UP ≥ 1 ✓.
- Output preserves all v6 columns: `round`, `throws_kv`, `winners`, `losers`, `action`, `target`, `winner_picked_target`, `winner_picked_action`, `narration`. The `phase=reveal` row carries `throws_kv=[id:choice,...]` per §H2; the `phase=action` row carries the full agency record.
- `pnpm test` → **90 tests passed (79 shared + 11 server, including 7 new sim specs) in <1s**. Server suite now covers: parseArgs strict/no-strict policy; canonical seed=42 4-bot run exits 0 with `seed=42` in summary and no `FAIL: §A2 budget breach` on stderr; known-bad 2-player mirror,mirror seed=1 exits 1 under `--strict`; same config with `--no-strict` exits 0 but warns; short 10-round run is non-strict by default; `--help` exits 0; bad flag exits 2.
- `pnpm typecheck` → green across all 3 workspaces.
- The Definition of Done shell snippet from FINAL_GOAL is now satisfiable for the §A row: the headless gate exits 0 with the right distribution.

**Notes for next iteration:** S-006 (`shared/scripts/codegen-timing.ts` → `client/scripts/generated/Timing.gd`) is a small standalone task that unblocks the Godot client without depending on S-005. After that, S-005 (the entire `client/` Godot 4.3 project tree — `project.godot`, `export_presets.cfg`, scenes/{Main,Landing,Lobby,Game,stage/*,characters/*,effects/*,ui/*}.tscn, scripts/globals/{Net,GameState,Audio}.gd, scripts/stage/{GameStage,EffectPlayer,Camera}.gd, scripts/characters/Character.gd) becomes the longest-pole bottleneck. Until S-005 lands, the playwright + chrome-devtools MCPs cannot be exercised because there is no rendered surface — `pnpm serve` fails with "build first" because `client/build/index.html` does not exist.

## Iteration 3 — S-003 — port server/ Socket.IO entry + Room + matchmaking from v2

**Did:** Copied `xiaodaoyiba-v2/packages/server/src/{index.ts,matchmaking.ts,rooms/Room.ts,index.test.ts}` verbatim into `server/src/`. The v3 `@xdyb/shared` barrel already re-exports every symbol the port needs (`SHARED_PACKAGE_VERSION`, `Effect`, `resolveRound`, `resolveRps`, `pickStrategyForIndex`, `getBotStrategy`, `seededRng`, `Rng`, `BotKind`, `BotStrategy`, `RoundHistoryEntry`, `RoundInputs`, `ActionKind`, `RpsChoice`, `PlayerState`, `ROUND_TOTAL_MS`, `TIE_NARRATION_HOLD_MS`) — no shimming needed. Switched `server/build` to a `tsup.config.ts` that sets `noExternal: ['@xdyb/shared']`, so `node server/dist/index.js` boots without needing a separately-built copy of the workspace shared package on disk.

**Verified (acceptance for S-003):**
- `pnpm test` → **83 tests passed (79 shared + 4 server) in <1s**.
- `server/src/index.test.ts` boots a real Socket.IO server on a random port and drives 4 spec scenarios via `socket.io-client`: `/healthz` returns shared version + room count; host creates room, joiner joins via 4-letter code, both sockets receive synchronized `room:snapshot`; `room:addBot` adds a bot then `room:start` + `room:choice` triggers a `room:effects` broadcast whose first effect is `ROUND_START`; bad inputs (empty nickname, bogus 4-letter code) emit `room:error` with the expected error code.
- `pnpm typecheck` → green across all 3 workspaces.
- `pnpm --filter @xdyb/server build` produces `server/dist/index.js` (~41 KB, with shared bundled in).
- `PORT=3458 node server/dist/index.js` + `curl /healthz` returns `{"ok":true,"shared":"0.0.1","rooms":0,...}` — the bundled artifact actually listens on the network, satisfying the S-003 acceptance bar literally.

**Notes for next iteration:** S-004 (server/sim.ts headless CLI) is the next bottleneck for §A1–A4. After that, S-005 (Godot client) becomes unblocked. The Room class already exposes the full Socket.IO surface the eventual Godot `Net.gd` autoload needs — `room:create`, `room:join`, `room:addBot`, `room:start`, `room:choice`, `room:winnerChoice`, `room:rematch`, `room:leave` — and emits `room:snapshot`, `room:effects`, `room:winnerChoice`, `room:error`. The §H3 winner-agency flow is intact (9-second `WINNER_CHOICE_BUDGET_MS`, auto-pick fallback timer).

## Iteration 2 — S-002 — port shared/ game logic verbatim from v2

**Did:** Copied `xiaodaoyiba-v2/packages/shared/src/game/` and
`narrative/lines.ts` verbatim into `xiaodaoyiba-v3/shared/src/`:
`timing.ts`, `rps.ts`, `engine.ts`, `effects.ts`, `types.ts`,
`bots/{counter,random,iron,mirror,seedRng,types,index}.ts`,
`game/index.ts`, `narrative/{lines,index}.ts`, plus the existing v2
test suites `rps.test.ts`, `engine.test.ts`, `lines.test.ts`. Replaced
the 3-line placeholder `shared/src/index.ts` with a real barrel that
re-exports `./game/index.js` and `./narrative/index.js` so consumers
write `import { resolveRound, ROUND_TOTAL_MS, defaultNarrator } from
'@xdyb/shared'`.

**Verified (acceptance for S-002):**
- `pnpm --filter @xdyb/shared test` → **79 tests passed in 435ms**
  (criterion: ≥10 tests in <5s — exceeded by an order of magnitude).
  Suites: rps.test.ts (46), engine.test.ts (20), lines.test.ts (13).
- `pnpm typecheck` → green across all 3 workspaces.
- `engine.ts` exports `resolveRound` (default export check via
  `grep -n 'export function resolveRound' shared/src/game/engine.ts`).
- `bots/{counter,random,iron,mirror}.ts` each export their named
  `*Strategy` symbol; `pickStrategyForIndex(0..3)` cycles through them.
- `grep -rn PHASE_T_RETURN shared/src/` returns **0 hits** — v6 §K2
  satisfied. `timing.ts` has only the 6 phase constants (REVEAL, PREP,
  RUSH, PULL_PANTS, STRIKE, IMPACT) plus the totals.
- 6-phase timeline sums to exactly `ROUND_TOTAL_MS=4700` (REVEAL 1500
  + ACTION_TOTAL_MS 3200), enforced by an at-import-time check inside
  `engine.ts` and re-asserted in `engine.test.ts`.

**Notes for next iteration:** The narrative pool is already at 8 tie
variants + dedicated `allSameLine` + 7 `pullOwnPantsUpVariants`,
which already covers FINAL_GOAL §C8's "≥5 distinct lines per pool"
target. No additional work needed there. Next bottleneck is S-003
(server/index.ts + Room.ts + matchmaking.ts) followed by S-004
(server/sim.ts) to satisfy A1–A4.

## Iteration 1 — S-001 — pnpm workspace scaffolding

**Did:** Scaffolded the pnpm monorepo root per FINAL_GOAL §"Repository
structure". Created `package.json` (workspace scripts: dev / build /
test / typecheck / sim / serve), `pnpm-workspace.yaml` (lists
`shared`, `server`), `tsconfig.base.json` (strict TS6 baseline ported
from v2), `.nvmrc` (Node 20), and `scripts/{dev,build,serve-html5}.sh`.
Created minimal `shared/` (`@xdyb/shared`) and `server/` (`@xdyb/server`)
package skeletons with valid `package.json` + `tsconfig.json` so pnpm
recognizes them; the actual v2 ports (engine, RPS, bots, narrative,
Room, sim) land in subsequent subtasks (S-002…S-004).

**Verified (acceptance for S-001):**
- `pnpm install` exits 0 in **~3s** on this machine (criterion: ≤60s).
- `pnpm -r ls --depth -1` lists both `@xdyb/server` and `@xdyb/shared`
  alongside the root workspace.
- `pnpm test` → green (vitest with `--passWithNoTests`).
- `pnpm typecheck` → green.
- `pnpm sim` runs the placeholder entry without error (proves the
  `pnpm --filter @xdyb/server sim` wiring works end-to-end).
- `bash -n` clean on all three shell scripts; `serve-html5.sh` exits
  with the expected "build first" message when no HTML5 export exists
  yet (proves graceful failure path).

**Notes for next iteration:** The server's HTML5 serve script sets COOP
/ COEP headers because Godot 4 HTML5 threads need SharedArrayBuffer —
otherwise the canvas refuses to boot in the browser. The script is a
single inlined Node program rather than a `npx serve` config to avoid
adding another dependency just for two response headers.

**Outstanding (high-leverage next):** Port `shared/src/game/` verbatim
from v2 (S-002), then `server/src/{index.ts, sim.ts, rooms/Room.ts,
matchmaking.ts}` (S-003 / S-004). After that the headless sim path
(criterion A1–A4) is unblocked and the Godot client can begin (S-005).

---

## S-098 — fix CRITICAL Lobby crash (@onready paths, smoke test)

**Bug:** Lobby.tscn nests its content under `Card/V/...` (yellow-bordered
PanelContainer wrapper added in S-005) but Lobby.gd still queried
`$V/Code`, `$V/Members/List`, `$V/Buttons/{AddBot,Start,Leave}` —
relics from before the Card wrapper. On first `_ready()`, every
`@onready` resolved to `null`, and `_add_bot.pressed.connect(...)` hit
`Invalid access to property or key 'pressed' on a base object of type
'null instance'`. End-user impact: clicking 创建房间 from Landing
loaded Lobby and instantly crashed — no room code visible, no member
list, all three buttons dead.

**Fix:** retargeted the five `@onready` paths in
`client/scripts/ui/Lobby.gd:11-15` to `$Card/V/...` (one-character-per-
line change; no .tscn restructuring needed since the .tscn shape is
correct).

**Smoke test:** added `client/tests/smoke_lobby.gd` — instantiates
Lobby.tscn against a mocked `GameState` (3 players, host=true,
room_code=ABCD), waits 5 frames, then asserts:
1. all five `@onready` vars are non-null and valid,
2. `_code_label.text` contains "ABCD",
3. `_members` rendered exactly 3 child rows,
4. `AddBot` and `Start` buttons are enabled (host gating).

Verified by **temporarily reverting the fix** — the test correctly
fails with the exact stderr signature from the bug report:
`Node not found: "V/Code"` ... `Node not found: "V/Buttons/Leave"`,
followed by `Invalid access to property or key 'pressed' on a base
object of type 'null instance' at: _ready (Lobby.gd:18)`. Restored
the fix, test passes:

    [smoke_lobby] PASS — Lobby instantiated cleanly, all @onready
    vars bound, 3 rows rendered, host buttons enabled.

**Visual eyeball:** added `client/tests/render_lobby.gd` to render the
Lobby with mock data to `/tmp/xdyb_lobby.png`. The PNG shows the
yellow-bordered card with `房号 ABCD` heading, three coloured
member rows (`小明 ★`, `小红`, `机器人甲 (bot)`), and the three
buttons (`加机器人`, `开始`, `离开`) — all visible and styled.

**Run:** `godot --headless --path client --script res://tests/smoke_lobby.gd`
exits 0; godot --headless --import is still clean.

**Outstanding (next iteration candidates):** §C9 emoji glyphs (✊✋✌
boxes), §C11 viral-aesthetic gate (sprites empty), §A4 codegen-
timing.ts missing, §E5 GitHub Actions workflow absent, characters
rendering inside house walls in Game.tscn, parallax mountains
off-screen.

## Iteration 14 (S-162) — §C11 viral aesthetic: shingled roofs, wall noise, porch step, chimney smoke

Pushed `_render_house` in `client/scripts/globals/SpriteAtlas.gd`
through the four §S-162 acceptance items:

1. **Roof shingles** — horizontal bands every 7 px in `C_ROOF_SHADE`
   on the front roof face, plus a darker variant on the back/right
   perspective face, plus a 1-px under-band shadow line for extra
   definition. Triangle-clipped so the bands respect the gable
   silhouette.
2. **Wall noise** — deterministic per-pixel ±7% lightness perturbation
   on the front-face wall (hash of x,y → ±0.07 RGB delta). Skips
   wood-grain shade rows + door footprint so the existing structure
   still reads. Measured σ ≈ 0.040 → 10.23 / 255 (clears the §S-162
   ≥ 8/255 threshold with margin).
3. **Porch step** — 4-px tall step in `C_DOOR_SHADE` directly below
   each door, slightly wider than the door itself, with a 2-px-tall
   black-α drop shadow under it.
4. **Chimney smoke** — three stacked semi-transparent grey-white
   ellipses above the chimney lip in the static atlas, stand-in for
   a future GPUParticles2D scene.

**Verification:** new `client/tests/render_house_atlas.gd` runs the
SpriteAtlas autoload, blits all 4 damage stages onto a 768×160 grass
tile, and asserts:

- wall σ ≥ 8/255  (got 10.23) ✓
- ≥ 6 dark↔light transitions on the centre-column roof (got 14) ✓
- ≥ 60 porch-brown pixels under each door (got 176) ✓
- ≥ 30 smoke-wisp pixels above each chimney (got 271) ✓

Output: `/tmp/xdyb_houses.png` (4-stage tile) and
`/tmp/xdyb_house_pristine.png` (pristine house close-up).

**Docs gallery refresh:** added `client/tests/render_action_static.gd`
which composes a 1280×720 game-frame mock without a viewport (headless
WSL2 currently can't drive `viewport.get_texture()`; `render_game.gd`
hangs at `save_png` with "Parameter t is null" because the dummy
rendering driver returns no GPU texture). The static composer blits
the four updated houses + characters onto an iso ground plane with
per-player roof tints, mountains, BattleLog rail with 6 colour-coded
verb-badge rows, phase banner, and the three RPS HandPicker chips.
The ATTACKING (knife-wielding) character is placed top-left so the
knife sprite is unambiguously visible; the ALIVE_PANTS_DOWN bot is
bottom-left so the persistent-shame red briefs are visible. Saved
to both `/tmp/xdyb_action_static.png` and
`docs/screenshots/action.png` (overwriting the stale flat-roof
screenshot).

**Side-by-side judgment:** new houses show 6 shingle bands per roof
face, distinct pastel roof tints, visible chimney smoke, and a
porch step under each door. Compared to the previous flat solid-
colour roofs, the houses now read as "Stardew/Hades-tier indie
2024" rather than "procedural placeholder".

**Run:** `godot --headless --path client --script res://tests/render_house_atlas.gd` exits 0;
`pnpm test` 90/90 green; `smoke_lobby.gd` still PASS.

## S-169 (iter-15): §F2 README hero truth — bitmap-font UI text in static mock

**Problem.** README.md claimed `docs/screenshots/action.png` was
rendered by `client/tests/render_game.gd` against the live Godot
project. It wasn't — `render_game.gd` hangs in headless WSL2 at
`viewport.get_texture().get_image()` (the dummy renderer returns a
null Image) and the committed PNG is actually generated by the
hand-blitted `render_action_static.gd`. Worse, the previous mock
showed the BattleLog and HandPicker as colour-coded *bars with no
real text*, so the screenshot was both falsely captioned and
illegible as UI.

**Path chosen.** Path (b) from the brief: keep the static-mock
generator (the live HTML5 capture is blocked on browser-MCP install,
out-of-scope for this iter) AND make the mock honest by drawing
real readable text. Path (a) — making `render_game.gd` exit 0 in
headless — was investigated and rejected after probing showed Godot
4.3's `--headless` mode replaces texture storage with a dummy
backend, so neither viewport `get_texture().get_image()` nor
`SubViewport.get_texture()` returns valid pixel data. `xvfb-run`
isn't installed on the WSL2 host either.

**TextServer / FontFile cache rejected.** Spent the first half of
the iter trying to read DejaVuSans-Bold + Noto Sans CJK Bold cache
atlases via `FontFile.get_texture_image()` after force-rasterising
with `get_string_size()` and `TextServer.font_render_glyph()`. Probe
output showed the L8 atlas exists at 256×256 and reports 65536
non-zero pixels, but every pixel reads back as `Color(1,1,1,1)` and
`get_glyph_uv_rect()` returns the same bogus `Rect2(P:(N,1) S:(3,3))`
for every glyph — the dummy renderer scrambles cache atlas reads.
Only NotoColorEmoji's RGBA8 atlas survives because its bitmap data
ships inside the .ttf as embedded PNG strikes (no GPU rasterisation
required).

**Solution shipped.** Hand-rolled a 5×7 monospace pixel font as a
GDScript `Dictionary` covering ASCII printable subset (digits,
A–Z, a–z, common punctuation incl. `·`). `_draw_text(dst, text, x,
y, scale, color)` walks each character, looks up the bitmap row,
unpacks bits LSB→MSB, and `set_pixel`-s a `scale × scale` block
per lit bit. Zero font dependencies, zero GPU. Re-used the existing
`_draw_emoji()` helper for ✊ U+270A, ✋ U+270B, ✌ U+270C via
NotoColorEmoji which is already a committed asset. The hero now
reads:

- **Phase banner** (top-left): `● R1 REVEAL` at scale 4.
- **BattleLog** (right rail): yellow `BattleLog` title at scale 3
  plus six rows, each showing a timestamped tag chip (`R1.PREP`,
  `R1.REVEAL`, `R1.ACTION`, `R1.RESULT`, `R2.PREP`, `R2.REVEAL`),
  a colour-coded 3-letter verb badge (`PRP`/`RVL`/`ACT`/`RES`) in
  the §C8 palette, and a body line (`Ming preps`,
  `Rock Paper Scissors`, `Pull Hong's pants`, `Hong pants down`,
  `New round`, `Scissors beats Paper`). All English to honour the
  no-CJK-font-on-CI constraint without falling back to empty boxes.
- **HandPicker** (bottom strip): three chips with the colour emoji
  on top (✊ ✋ ✌) and `ROCK` / `PAPER` / `SCISSORS` underneath in
  the §C11 yellow accent.

**README rewrite.** Status paragraph now plainly says "**static
mock** composed by `client/tests/render_action_static.gd`" and
documents the bitmap-font + NotoColorEmoji approach. The
"rendered by render_game.gd against the committed Godot project"
sentence is gone; replaced with a truthful note that a live
HTML5-export capture is gated on browser-MCP and the mock is
explicitly a mock.

**Run:** `godot --headless --path client --script
res://tests/render_action_static.gd` exits 0; produces a 1280×720
PNG with all UI text legible at the rendered resolution; `pnpm
test` 90/90 still green.
