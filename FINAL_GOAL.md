# FINAL_GOAL.md — xiaodaoyiba v3 (Godot 4 rewrite)

## What this project is

小刀一把 (xiaodaoyiba) is a casual web multiplayer game based on the Chinese
nursery rhyme **"小刀一把，来到你家，扒你裤衩，直接咔嚓！"** (one little knife,
come to your house, pull down your pants, chop!). 2-6 players in a room
throw rock-paper-scissors; winners pick a loser, rush to their house, pull
their pants down, then chop their door. Eliminations until one player
remains.

## Why a third rewrite

v0 (DOM/CSS, https://github.com/shyDaniel/xiaodaoyiba) hit an aesthetic
ceiling at 32×32 scaled pixel-art. v2 (PixiJS canvas,
https://github.com/shyDaniel/xiaodaoyiba-v2) shipped a much better game —
particle FX, parallax, persistent shame, winner pickers, headless agency
sim — but **the renderer is still a hand-rolled stack on top of a low-
level 2D library**. The user played v5/v6 and identified four structural
gaps that PixiJS can technically support but Godot ships as first-class
nodes:

1. **Top-down 45° / isometric view.** PixiJS: build the projection by
   hand. Godot: `TileMap` with `TileSetAtlasSource.tile_shape =
   ISOMETRIC` + `Camera2D` with rotation/zoom built in.
2. **Cinematic zoom-pan-zoom on action moments.** PixiJS: write a
   tween system. Godot: `Tween` node + `Camera2D.zoom`/`offset`
   animation tracks in `AnimationPlayer`.
3. **Animation choreography (5-phase action timeline).** PixiJS: thread
   timing through the EffectPlayer state machine by hand. Godot:
   `AnimationPlayer` with keyframe tracks per scene, scrubable in the
   editor, exported to runtime.
4. **Character + house art workflow.** PixiJS: `OffscreenCanvas` +
   procedural sprite generator. Godot: drop PNGs into `res://assets/`,
   use `Sprite2D` / `AnimatedSprite2D` / `AtlasTexture`, hot-reload in
   editor, keyframe animations against the timeline.

Plus the things Godot just gives us that PixiJS doesn't:
- `GPUParticles2D` for proper physics-driven particles
- Scene composition with `.tscn` text files (diff-friendly, mergeable)
- Built-in `AudioStreamPlayer` with bus routing
- Free desktop preview via the editor while iterating
- HTML5 export so the game still runs in a browser

v3 is a full client rewrite in Godot 4. **The TypeScript multiplayer
server from v2 stays** — Socket.IO over WebSocket — because the
multiplayer engine, RPS resolution for N≥3, diversified bot
strategies, narrative variants, and the headless sim all work. Throwing
that away is reinvention.

## Tech stack (deliberate)

- **Game client: Godot 4.3 stable**, GDScript primary language. Native
  `WebSocketPeer` to talk to the server. **HTML5 export** as the
  primary distribution target so the game plays at `localhost:5173` in
  a browser like v2 did, and the autopilot eval skill can drive it
  with the Playwright MCP.
- **Multiplayer server: Node ≥ 20 + Socket.IO + TypeScript**, ported
  verbatim from v2's `packages/server/` and `packages/shared/`.
- **Headless sim: TypeScript**, ported verbatim from v2's `pnpm sim`
  CLI. Game-logic correctness lives in pure TS — no Godot needed for
  the agency-aware simulation that the v5/v6 acceptance gates rely on.
- **Editor**: Godot 4.3 (`/home/hanyu/bin/godot`).
- **Build**: `godot --headless --import` for first-time asset import,
  `godot --headless --export-release "Web" build/index.html` for HTML5
  build. CI runs `godot --headless --check-only` and `godot --headless
  --quit-after 10 --script tests/run_tests.gd` for test runs (gut or
  WAT framework — autopilot picks).
- **Assets**: PNG / JPG / WAV in `res://assets/`. User will drop hand-
  drawn art here later; loader prefers user assets, falls back to
  procedurally-generated placeholders so the game ships playable
  without uploads.

## Repository structure

```
xiaodaoyiba-v3/
├── README.md
├── ARCHITECTURE.md
├── WORKLOG.md
├── FINAL_GOAL.md                  (this file)
├── client/                        (Godot 4 project)
│   ├── project.godot
│   ├── icon.svg
│   ├── scenes/
│   │   ├── Main.tscn              (root scene — landing/lobby/game state machine)
│   │   ├── Landing.tscn
│   │   ├── Lobby.tscn
│   │   ├── Game.tscn              (iso stage + houses + characters + camera)
│   │   ├── stage/
│   │   │   ├── Ground.tscn        (TileMap with isometric tiles)
│   │   │   ├── House.tscn         (sprite + roof tinting + damage marks)
│   │   │   └── Background.tscn    (parallax sky + mountains, ParallaxBackground node)
│   │   ├── characters/
│   │   │   ├── Character.tscn     (AnimatedSprite2D + state machine)
│   │   │   └── Pants.tscn         (independent ankle-briefs sprite)
│   │   ├── effects/
│   │   │   ├── DustEmitter.tscn   (GPUParticles2D)
│   │   │   ├── ClothEmitter.tscn
│   │   │   ├── WoodChipEmitter.tscn
│   │   │   └── ConfettiEmitter.tscn
│   │   └── ui/
│   │       ├── BattleLog.tscn     (right-rail panel)
│   │       ├── HandPicker.tscn    (rock/paper/scissors row)
│   │       └── WinnerPicker.tscn  (target + action picker dialog)
│   ├── scripts/
│   │   ├── globals/
│   │   │   ├── Net.gd             (Socket.IO-style WebSocket client; autoload)
│   │   │   ├── GameState.gd       (room snapshot store; autoload)
│   │   │   └── Audio.gd           (SFX + BGM bus; autoload)
│   │   ├── stage/
│   │   │   ├── GameStage.gd       (drives Main scene state)
│   │   │   ├── EffectPlayer.gd    (consumes Effect[] from server, dispatches scene tree calls)
│   │   │   └── Camera.gd          (zoom-pan-zoom controller)
│   │   └── characters/
│   │       └── Character.gd       (animation state machine)
│   ├── assets/
│   │   ├── sprites/characters/    (PNGs — user art hot-swap slot, falls back to procedural)
│   │   ├── sprites/houses/
│   │   ├── sprites/effects/
│   │   ├── audio/
│   │   │   ├── sfx/               (WAVs ported from v2 ZzFX presets)
│   │   │   └── bgm/               (lobby / battle / victory variants)
│   │   └── fonts/
│   ├── tests/
│   │   └── *.gd                   (gut or WAT test framework)
│   └── export_presets.cfg         (HTML5 + Linux desktop presets)
├── server/                        (Node + Socket.IO, ported from v2)
│   ├── package.json
│   ├── tsconfig.json
│   └── src/
│       ├── index.ts               (Socket.IO entry)
│       ├── rooms/Room.ts          (porting from v2)
│       ├── matchmaking.ts
│       └── sim.ts                 (headless CLI — keeps v5/v6 §H5 acceptance)
├── shared/                        (pure TS game logic, ported from v2)
│   ├── package.json
│   ├── tsconfig.json
│   └── src/
│       ├── game/
│       │   ├── timing.ts          (single source of truth — no PHASE_T_RETURN per v6 §K2)
│       │   ├── rps.ts             (multi-player resolution, fixed for N≥3)
│       │   ├── engine.ts          (resolveRound, accepts inputs.targets + inputs.actions)
│       │   ├── bots/              (counter, random, iron, mirror — diversified, seeded RNG)
│       │   ├── effects.ts         (Effect[] choreography protocol — adds RPS_REVEAL, ZOOM_IN/OUT)
│       │   └── types.ts
│       └── narrative/
│           └── lines.ts           (tie variant pool, action narration)
├── package.json                   (workspace root for server + shared)
├── pnpm-workspace.yaml
└── scripts/
    ├── dev.sh                     (concurrent: pnpm dev (server) + godot --editor (client))
    ├── build.sh                   (pnpm build && godot --headless --export-release "Web" build/)
    └── serve-html5.sh             (vite serve build/ for browser play at :5173)
```

## Acceptance criteria

### A. Game logic correctness (server + headless)

**A1.** Headless sim CLI `pnpm sim` works as in v5/v6. The TypeScript
sim is the canonical fast-feedback channel. 50 rounds × 4 players in
< 2 seconds. Output preserves the v6 columns:
`round, throws_kv, winners, losers, action, target, winner_picked_target,
winner_picked_action, narration`.

**A2.** RPS for N≥3 still produces non-degenerate distributions:
tie rate < 30%, no single player wins > 60%, distinct shapes don't
auto-tie.

**A3.** `--winner-strategy random-target+random-action` exercises the
agency code path. `PULL_OWN_PANTS_UP` fires ≥ 1× over 50 rounds.

**A4.** All timing constants live in `shared/src/game/timing.ts` (no
RETURN phase per v6 §K2). Both Godot client and Node server import
the values as JSON via a build-time codegen step (Godot doesn't read
TypeScript natively — emit `client/scripts/generated/Timing.gd` from
`shared/src/game/timing.ts` during build).

### B. Headless / dev velocity

**B1.** `pnpm test` runs all TS tests in < 5s.

**B2.** `pnpm sim` is the canonical AI-debugging tool. Output grep-able.

**B3.** `pnpm dev` runs server + Godot HTML5-served client concurrently
with hot reload of the server. Godot client must be re-exported on
demand via `pnpm dev:godot:rebuild` (Godot doesn't have JS-level HMR;
the rebuild is one command).

**B4.** `pnpm sim` and the live game **share** `shared/src/game/`. No
divergence. Bot strategies, RPS rules, narrative pool, timing — all
single-source.

### C. Renderer / game feel (the reason for the rewrite)

**C1. Isometric 45° view.** Stage uses Godot `TileMap` with
`TileSetAtlasSource.tile_shape = ISOMETRIC`. Houses and characters
render in iso-coords. Camera2D rotation 0°, but the ground tile
lattice is iso. A first-time viewer immediately reads "this is a
top-down game", not "this is a flat side-view".

**C2. Camera with zoom-pan-zoom on action moments.** During PULL_PANTS
and CHOP, `AnimationPlayer` runs a pre-authored cinematic track:
- Pre-PULL_PANTS: `Camera2D.zoom` 1.0 → 1.6 over 600ms (`TRANS_QUART
  EASE_OUT`), `position` lerps to (actor + target)/2.
- Hold at 1.6× for the 800ms shame frame.
- Post-IMPACT: zoom 1.6 → 1.0 over 400ms (`EASE_IN`), position
  recenters on stage middle.
- For CHOP: same shape but focal on target's house door.

**C3. Stay at target's house — no return-home phase.** Engine drops
`PHASE_T_RETURN` (per v6 §K2). After ACTION resolves, actor sprite
remains parented to target's house anchor until next PREP. No walk-
back.

**C4. Smaller scale.** Character sprites ≈ 96×96 native (v6 §K5).
Houses ≈ 192×192 native. Camera zoom holds player's house at ~20% of
viewport height. World feels bigger than character.

**C5. Particle FX via `GPUParticles2D`.** Dust on rush, cloth on
PULL_PANTS, wood chips on CHOP, confetti on victory. Each is a `.tscn`
particle scene with physics (gravity, drag, fade).

**C6. AnimationPlayer-driven character states.** ALIVE_CLOTHED,
ALIVE_PANTS_DOWN, RUSHING, ATTACKING, DEAD — each has an animation
track defined in the editor against a sprite sheet. Sprite sheets can
be procedurally generated (placeholder) or user-supplied (PNG drop
into `assets/sprites/characters/`).

**C7. Persistent shame across rounds.** When `player.stage ==
ALIVE_PANTS_DOWN`, the character's sprite state machine renders the
red-ankle-briefs frame in EVERY phase, every round, until restored
(via PULL_OWN_PANTS_UP self-action) or DEAD. The v5/v6 non-negotiable.

**C8. BattleLog right-rail (UI Control node, not iso layer).** Same
shape as v6: timestamped `R{N}.{phase}` rows, color-coded verb
badges (扒 yellow, 砍 red, 闪 cyan, 平 gray, 死 purple, 穿 cyan-blue
for PULL_OWN_PANTS_UP), per-player stable name colors, glowing-on-
arrival, scrollable.

**C9. REVEAL phase shows every player's throw.** Per v5 §H2, after
RPS commits and before action, a 1500ms phase displays every alive
player's throw glyph (✊ ROCK / ✋ PAPER / ✌️ SCISSORS, ≥ 64px) above
their character. Player can intuitively count distribution.

**C10. Winner picker — target + action.** Per v5 §H3 + v6 §K4:
- Picker MUST surface when local human wins AND ≥ 2 eligible targets
  exist OR action choice is meaningful.
- Picker holds for up to 5s; default to engine's auto-pick if user
  doesn't choose.
- Three actions selectable based on stage:
  - `扒裤衩` (PULL_PANTS) — target is ALIVE_CLOTHED
  - `咔嚓` (CHOP) — target is ALIVE_PANTS_DOWN
  - `穿好裤衩` (PULL_OWN_PANTS_UP) — winner is ALIVE_PANTS_DOWN
- v6 §K4 bug fix: picker is reliable across solo and multi flows.
  No auto-skip path. Headless sim asserts agency dispatch.

**C11. Steam-quality bar.** Compare a mid-action screenshot to:
**Hades, Stardew Valley, Don't Starve, Spiritfarer, Bastion**. The
target is "indie iso-or-3D-quarter-view game from 2020-2024", not
"web prototype 2015". Eval drives this judgment.

### D. Audio

**D1.** SFX bus with named slots: `tap`, `reveal`, `pull`, `chop`,
`dodge`, `thud`, `victory`, `defeat`. Initially WAVs derived from v2
ZzFX presets (procedurally generate 8-bit-ish chiptunes via offline
ZzFX-to-WAV conversion in `scripts/`, port verbatim from v2).

**D2.** BGM bus with cross-fade. Three variants: `lobby` (calm
pentatonic), `battle` (slightly tense, same key), `victory` (uplifting
flourish). Auto-cross-fade on phase change.

**D3.** Mute toggle in corner. Persisted to user-profile config (Godot
`user://settings.cfg`).

### E. Build + dev

**E1.** `pnpm install` in repo root succeeds in ≤ 60s clean.

**E2.** `pnpm test` runs the TS suite (vitest) for `shared/` and
`server/` in < 5s.

**E3.** `pnpm build` produces:
- Server bundle at `server/dist/`
- Godot HTML5 export at `client/build/index.html` + `.wasm` + `.pck`
- Total HTML5 bundle ≤ **6 MB** (Godot's HTML5 runtime is ~5 MB; this
  is a soft cap — flag if it exceeds, not a fail)

**E4.** `pnpm sim` works from a fresh clone after `pnpm install` only.
No Godot dependency for the headless path.

**E5.** GitHub Actions CI: on every push, run `pnpm install`,
`pnpm test`, `pnpm sim --rounds 50 --seed 42 --strict`, AND
`godot --headless --import client/` to verify the Godot project
imports cleanly with no errors. (Full HTML5 export in CI is optional;
would add ~2 minutes.)

### F. Documentation

**F1.** `README.md` — pitch, install / dev / test / sim / build-html5
commands, screenshot, link to architecture.

**F2.** `ARCHITECTURE.md` — the Godot scene tree, the Effect[]
protocol, the timing.ts ↔ Timing.gd codegen, why-Godot rationale.

**F3.** `WORKLOG.md` — append-only iteration log.

### G. Out of scope (do NOT flag)

- Fly.io deploy (paid account, manual)
- Two-device cross-network real-radio test (requires hardware)
- Account system / login
- ELO / leaderboards
- Observation mode, in-app purchases, voice chat
- Native mobile / desktop Godot exports (HTML5 only for autopilot loop)

## Reuse pointers (v2 paths to read)

The v2 codebase at `/home/hanyu/projects/xiaodaoyiba-v2/` has working
TS server + sim + bot strategies + narrative pool. **Port these
verbatim** to the v3 monorepo's `server/` and `shared/`:

- `xiaodaoyiba-v2/packages/server/src/sim.ts` — copy
- `xiaodaoyiba-v2/packages/server/src/rooms/Room.ts` — copy
- `xiaodaoyiba-v2/packages/server/src/matchmaking.ts` — copy
- `xiaodaoyiba-v2/packages/shared/src/game/` — copy entirely (engine,
  rps, bots, effects, types)
- `xiaodaoyiba-v2/packages/shared/src/narrative/lines.ts` — copy
- `xiaodaoyiba-v2/packages/client/src/audio/zzfx.ts` — read for the
  preset values, convert to WAV via offline tooling for Godot

Do NOT port from `xiaodaoyiba-v2/packages/client/src/canvas/` — that's
the PixiJS layer being thrown out.

## Definition of Done

The judge returns `done: true` AND eval returns `passed: true` AND:

```bash
# Headless gate (TS, no Godot)
cd /home/hanyu/projects/xiaodaoyiba-v3
pnpm sim --players 4 --bots counter,random,iron,mirror \
         --winner-strategy random-target+random-action \
         --rounds 50 --seed 42
# → tie_rate < 0.30, no winner > 0.60, PULL_OWN_PANTS_UP ≥ 1 occurrence

# Test gate
pnpm test                          # → all green
godot --headless --import client/  # → 0 errors

# Build gate
pnpm build                         # → server + Godot HTML5

# UI gate (eval drives via Playwright)
pnpm serve                         # → http://localhost:5173
# → eval enters 3-player room, throws ROCK to force win,
#   confirms winner-picker dialog appears (no auto-skip),
#   confirms iso 45° projection visible,
#   confirms cinematic zoom on PULL_PANTS,
#   confirms persistent shame across rounds,
#   compares mentally to Stardew/Hades/Don't Starve.
```

## Notes on driving this build with autopilot

Autopilot (`/home/hanyu/projects/agent-autopilot`, v0.12.0+, npm-linked)
has never driven a Godot project before. The work skill SKILL.md does
not mention `.gd` / `.tscn` / `godot` CLI. **Expect the worker's first
1-3 iterations to be discovery** — reading Godot docs (web search), the
project structure, the `godot --help` output, and figuring out the
test/build toolchain. This is normal. The orchestrator should NOT
trigger evolve on early Godot discovery iterations — it's not a tool
gap, it's onboarding.

If the worker repeatedly produces no commits OR repeatedly fails to
get `godot --headless --import client/` to exit 0, an evolve targeting
`skills/work/SKILL.md` to add Godot-specific guidance would be
warranted. Until that pattern emerges, let the worker discover.

`godot` is on PATH at `/home/hanyu/bin/godot` (v4.3 stable). Worker can
verify via `godot --version`.

---

## §H. Aesthetic pass — Stardew Valley quality bar (2026-05-05 用户反馈)

User played v3 ship and said: 差不多是这个意思，但是 UI 也太丑太差了，我不信
godot 没有比这更好的，能不能像星露谷物语一样.

The architecture is correct (iso, cinematic camera, stay-at-target,
persistent shame, picker, REVEAL phase). The **rendering layer** is the
gap. v3's procedural sprite generator produces flat 4-color chibi rigs;
Stardew Valley's bar is hand-shaded pixel art with cohesive palette,
ambient detail, custom UI chrome.

### §H1. Authorized art sources

The worker has THREE valid paths to reach the bar — pick whichever lands
fastest:

1. **CC0 / public-domain pixel-art packs.** Allowed and recommended:
   - https://kenney.nl/assets (specifically `top-down-tanks-redux`,
     `medieval-rts`, `1-bit-pack`, `pixel-platformer`, `tiny-town`)
   - https://opengameart.org (filter: 2D pixel art, CC0/CC-BY-SA)
   - https://itch.io/game-assets/free/tag-stardew-valley-style
   - https://lpc.opengameart.org (Liberated Pixel Cup, CC-BY-SA 3.0)
   Use `curl` to download, extract to `client/assets/sprites/3rd-party/`,
   document license + attribution in `client/assets/sprites/3rd-party/
   LICENSES.md`. CC-BY/CC-BY-SA requires attribution; CC0 doesn't.

2. **Procedural Stardew-quality generation.** If the worker prefers
   self-contained, upgrade `scripts/gen-sprites.mjs` (or a Godot
   tool-script equivalent) to produce **properly shaded** sprites:
   - 32×32 native tiles, 16×32 native characters (Stardew's actual
     resolution, NOT 96×96 oversized blobs)
   - Per pixel: base color + highlight (lerp toward white ~25%) +
     shadow (lerp toward black ~25%) + outline (darker than shadow)
   - 16-color palette with cohesive temperature (warm, slightly
     desaturated — DB16 / Sweetie16 / Endesga32 are good references)
   - Hand-drawn lookalike via dithering and pixel-perfect placement,
     not antialiasing
   The reference: `pico-8` demoscene, Eric Barone's original Stardew
   sprites, Cuphead-quality pixel work.

3. **Hybrid.** Use CC0 packs for environment tiles (grass, paths,
   houses, props) and procedural for the player avatars (so each
   player still gets a unique procedural variant). Probably the
   fastest path.

### §H2. Concrete aesthetic deltas (acceptance criteria)

**§H2.1 Ground tiles.** Replace solid-color iso ground with
**textured tiles**: grass with tufts, dirt path with stone speckle,
cobblestone, packed earth. Use Godot `TileSet` with at least 4
distinct ground variants tinted/composited from a base atlas.
Eval check: 100% of visible ground in a screenshot has texture
detail at the pixel level, not flat color blocks.

**§H2.2 House visual depth.** Houses go from "rectangle with roof
slope" to:
- Wooden plank wall texture (visible grain, ~3-color shading per plank)
- Tiled / shingled roof (individual shingle outlines, light/shadow
  per row)
- Door with frame, hinges, knob detail (≥ 8×8 visible pixels of
  hardware)
- Window with cross-mullion + curtain or interior glow tint
- Chimney with brick texture + animated smoke
- A small foundation step / porch
Eval check: a 256×256 zoom-in on one house reveals ≥ 5 distinct
textural elements.

**§H2.3 Character art.** Replace flat 4-color chibi:
- 16×32 native (Stardew exact size), 4× scale = 64×128 viewport
- Visible eyes (≥ 2 colors per eye for highlight + iris)
- Mouth with ≥ 3 expression states (idle smile / shocked O / dead X)
- Hair: distinct silhouette shape (mohawk / bowl / antenna / cap /
  ponytail / bun), each with 2-tone shading
- Clothing: shirt + pants with cloth folds (≥ 2 tones per garment)
- Skin tone: at least 2 shades (highlight on cheek, shadow on jaw)
- Idle squash-and-stretch animation every 1.5-2.5s
Eval check: zoom in on one character; you can read facial expression
and clothing detail from a single still frame.

**§H2.4 UI chrome.** Replace default Godot Control nodes with
**Stardew-style carved wooden panels**:
- 9-slice `StyleBoxTexture` with **carved wood frame** PNG (3-pixel
  border with highlight/shadow rim)
- Background: parchment/paper texture or dark wood plank
- Buttons: wood-button look, pressed state visibly indented
- Custom **bitmap pixel font** for UI text (download from
  damieng.com/typography/zx-origins/ or similar CC0 pixel fonts;
  embed as Godot `BitmapFont` resource). Default `LineEdit` /
  `Label` fonts are forbidden in user-visible UI.
- Battle log entries: hand-painted ribbon look, NOT a flat colored row
- Buttons have ≥ 1px hard drop-shadow + ≥ 1px highlight rim

**§H2.5 Ambient detail.** Stardew's world feels alive even when
nothing is happening:
- Grass tufts sway every 2-3s (subtle 1-pixel offset)
- Chimney smoke continuously emits (1 particle every 800ms drifting
  up + fading)
- 3-5 dust motes float in the foreground (looped sprite, slow drift)
- Background birds / clouds drift across sky every 8-12s
- Player characters have a 2-3 frame idle bob

**§H2.6 Color palette discipline.** Pick one cohesive palette and use
it for EVERY pixel rendered:
- Recommended: **Endesga 32** (32 colors, warm, indie-game default)
  — https://lospec.com/palette-list/endesga-32
- Or **Sweetie 16** (16 colors, gentler) —
  https://lospec.com/palette-list/sweetie-16
- Or **DB32** (DawnBringer 32, classic)
- Hardcode the palette as a Godot resource (`palette.tres`); all
  programmatic sprite generation samples FROM the palette only — no
  arbitrary hex codes.

**§H2.7 Audio polish.** Stardew has tactile UI sounds:
- Hover button: soft wood-tap (tiny ZzFX tone)
- Click button: deeper wood-knock + paper-rustle blend
- Page transition: scroll-rustle
- Currently the SFX bus has tap/reveal/pull/chop only — extend to
  include hover, click, transition.

### §H3. Definition of done (additive)

Add to the existing ship gate:

- Eval takes a screenshot at each of: landing, lobby, mid-action,
  game-over.
- For each screenshot, eval **side-by-side mentally compares** to a
  reference Stardew Valley screenshot (eval may web-search "stardew
  valley screenshot game" via WebFetch to ground the comparison).
- Eval returns `passed: false` if **any** of these fails on **any**
  screenshot:
  - Visible flat-color blocks (background, ground, walls)
  - Default Godot UI fonts visible in user-facing chrome
  - Default Godot Control panels (gray boxes) visible
  - Characters readable as "stick figure / 4-color blob" rather than
    "shaded pixel-art character"
  - Empty regions with no ambient detail (no tufts, no smoke, no
    motion)

Eval narrates which screenshot fails which check, with file path
and pixel coordinates.

### §H4. Don't regress acceptance A-G

§H is **strictly additive**. All v3 functional acceptance (game
logic, headless sim, agency picker, cinematic camera, stay-at-target,
persistent shame) must continue to pass. The aesthetic pass touches
asset pipelines, sprite generators, UI theme resources, palette,
ambient particle scenes — NOT the game-logic packages.

### §H5. Hot-swap art slot still works

When user provides hand-drawn art later, drop into:
- `client/assets/sprites/characters/`
- `client/assets/sprites/houses/`
- `client/assets/sprites/tiles/`

Loader prefers user assets over CC0 / procedural fallback (per the
existing §C / asset-loading contract).

---

## §I. Mandatory CC0/CC-BY pack download — procedural entity art is BANNED (2026-05-05 second user playtest)

User played §H ship: **"this is still so bad yo, i said 星露谷物语 / pokemon 那种可爱画风, 你看看我们现在是啥, 丑的一比, 计分板还把游戏挡住了, 路远得很呢"**.

The §H spec offered three paths (CC0 packs, procedural, hybrid). The
worker picked path 2 (procedural) for every entity sprite. That choice
is no longer available. Hand-drawn pixel art of Stardew/Pokemon quality
is **physically impossible to reach with `_draw_line` / `_draw_circle`
/ programmatic Image manipulation**. Stardew was hand-drawn by Eric
Barone over four years; Pokemon by professional artists. We are not
going to compete with that procedurally — we are going to **stand on
the shoulders of artists who already did it** by using their CC0/CC-BY
work.

### §I.0 HARD BAN — no procedural draw calls for entity art

No new code AND no surviving code in the project may use any of these
to render a character / house / tile / prop:

- `draw_line`, `draw_circle`, `draw_rect`, `draw_polygon`,
  `draw_polyline`, `draw_arc`, `draw_multiline`, `draw_colored_polygon`
- `Image.set_pixel`, `Image.fill_rect`, `Image.fill`, manual loops over
  `set_pixelv`
- Any procedural sprite generator that produces character/house/tile
  PNGs or in-memory ImageTextures

**Allowed exceptions** (only these):
- 9-slice UI chrome (`StyleBoxTexture` slices in `client/assets/sprites/ui/`)
- Particle textures (small 4×4 dust/cloth/chip blobs — fine procedural)
- Debug overlays / hit-testing markers (must be `editor_only` flagged)

Eval check: `grep -rn 'draw_line\|draw_circle\|draw_rect\|draw_polygon\|set_pixel' client/scripts/ | grep -v 'tests/' | grep -v 'particles/' | grep -v 'ui/9slice' | grep -v 'editor_only'` must return **zero entity-rendering matches**. Any hit fails the build.

### §I.1 Mandatory pack downloads — these specific packs

Worker MUST `curl` and integrate at least these packs. They are
licensed for unrestricted use and look like actual hand-drawn pixel
art:

**Characters** (chibi / Stardew-villager / Pokemon-trainer style):
- Pipoya **RPG Character Pack** — https://pipoya.itch.io/pipoya-free-rpg-character-sprites-32x32
  License: free, redistribution OK with credit
  Format: 32×32 spritesheets, 4-direction walk cycles, tons of variants
- Penzilla **Hooded Protagonist** + **Cute Fantasy Characters** —
  https://penzilla.itch.io/hooded-protagonist (free)
  License: free, modification + commercial OK
- Kenney **Tiny Dungeon** + **Tiny Town** —
  https://kenney.nl/assets/tiny-dungeon and https://kenney.nl/assets/tiny-town
  License: CC0
  Format: 16×16 native, includes characters + buildings + props

**Houses + tiles** (top-down village / Stardew-style):
- Kenney **Tiny Town** (above) — has buildings, fences, paths, props
- Limezu **Modern Tiles RPG** — https://limezu.itch.io/moderntiles
  License: free, attribution required
- 0x72 **Dungeon Tileset II** — https://0x72.itch.io/dungeontileset-ii
  License: CC0

**Particles + decorative**:
- Kenney **Particle Pack** — https://kenney.nl/assets/particle-pack
- Kenney **Pixel UI Pack** — https://kenney.nl/assets/ui-pack-pixel-adventure

**Fonts**:
- DamienG **ZX Origins** pixel fonts — https://damieng.com/typography/zx-origins/
  License: free for any use
- Or **Press Start 2P** (Google Fonts) — https://fonts.google.com/specimen/Press+Start+2P
  License: OFL 1.1

**Procedure for each pack:**

```bash
mkdir -p client/assets/sprites/3rd-party/<pack-name>
cd /tmp && curl -sL -o <pack>.zip "<pack URL>" && \
  python3 -c "import zipfile; zipfile.ZipFile('<pack>.zip').extractall('/home/hanyu/projects/xiaodaoyiba-v3/client/assets/sprites/3rd-party/<pack-name>/')"
# Then add LICENSES.md attribution entry per the existing template.
```

### §I.2 Replace ALL existing procedural sprite generation

`client/scripts/globals/SpriteAtlas.gd` and any helper that produces
character / house / tile imagery must be deleted or reduced to a thin
loader that reads PNG files from `client/assets/sprites/3rd-party/`.

Specifically:
- `Character.gd` loads a `Texture2D` from one of the Pipoya / Penzilla
  / Kenney character sprite sheets via `AnimatedSprite2D`. Each player
  picks a different character variant (deterministic by playerId hash).
  Walk cycle, idle bob, attack frames all come from the sprite sheet.
- `House.gd` loads one of the Kenney Tiny Town building variants per
  player. Each player has a visually distinct house (different roof
  color, door type, window arrangement) by deterministic variant pick.
- `Ground.tscn` swaps the procedural ground_atlas.png for tiles from
  Kenney Tiny Town or Limezu Modern Tiles.
- The LandingHero CJK BattleLog mock can stay procedural — it's UI
  chrome rendering.

### §I.3 BUG: BattleLog must not occlude the iso stage

User report: 计分板还把游戏挡住了 (the scoreboard is blocking the
game).

The right-rail BattleLog currently steals horizontal space from the
iso stage. Fix:

- **Game stage must occupy ≥ 70% of viewport width** at every
  supported aspect ratio (1280×800 desktop, 1920×1080 desktop,
  375×667 mobile portrait, 667×375 mobile landscape).
- BattleLog options (worker picks):
  1. **Collapsed by default** with a toggle button; expand-on-tap to
     read history. When expanded, ≤ 30% of viewport width.
  2. **Bottom-sheet on mobile**, right-rail on desktop — but desktop
     rail caps at 22% width and uses a translucent background so it
     never visually occludes characters behind it.
  3. **Floating ribbons** that fade in for the most recent entry only
     (≤ 4 lines visible), holding ≥ 2.5s, then drift out. Full
     history accessible via a small "history" icon.
- Eval check: take a 1280×800 screenshot mid-action; iso stage
  rendered area (where characters / houses live) must measure ≥ 896
  pixels wide (70%). Anything less = fail.

### §I.4 Cute-art quality bar — explicit reference screenshots

For eval's mental compare, the bar is:

- Stardew Valley: https://stardewvalley.net/wp-content/uploads/2024/02/SDV1_6_4.png
- Pokemon Red/Blue overworld town: search "pokemon red pallet town"
- Pokemon HeartGold overworld: search "pokemon heartgold new bark town"
- Dave the Diver (top-down): search "dave the diver pixel art"
- Sun Haven: search "sun haven indie game pixel art screenshot"
- Stardew villager portraits: search "stardew valley character art"

Eval must WebFetch one of these and side-by-side compare to a
mid-action screenshot of our game. If our screenshot looks like
"hand-drawn-by-a-grown-up indie game" the gate passes. If it looks
like "polylines drawn by a script" it fails.

### §I.5 Done = real PNG sprites in 3rd-party/, zero procedural entity draws, BattleLog ≤ 22% width

Concrete ship gate (additive to all prior acceptance):

```bash
# 1. 3rd-party directory is non-empty AND has at least 3 packs
ls client/assets/sprites/3rd-party/ | wc -l    # → ≥ 3 directories

# 2. LICENSES.md has attributions for each pack
grep -c 'source_url:' client/assets/sprites/3rd-party/LICENSES.md   # → ≥ 3

# 3. No procedural entity draw calls
grep -rn 'draw_line\|draw_circle\|draw_rect\|draw_polygon\|set_pixel' \
  client/scripts/ | grep -v tests/ | grep -v particles/ | grep -v 9slice \
  | grep -v editor_only | wc -l                                     # → 0

# 4. Game stage width ≥ 70% at 1280×800 (eval Playwright screenshot + measure)

# 5. Eval side-by-side: looks like Stardew/Pokemon, not polylines
```

§I overrides §H's permissive "three paths" — only path 1 (CC0/CC-BY
download) and the already-finished path 3 (UI 9-slice procedural) are
allowed for the entity layer. Path 2 procedural sprite generation is
banned for characters, houses, ground tiles, and props going forward.
