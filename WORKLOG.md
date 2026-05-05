# Worklog

Append-only iteration log for xiaodaoyiba v3. Newest entries on top.

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
