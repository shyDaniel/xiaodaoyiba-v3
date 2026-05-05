# 小刀一把 v3 (xiaodaoyiba-v3)

Casual web multiplayer RPS-elimination game based on the Chinese nursery rhyme
**"小刀一把，来到你家，扒你裤衩，直接咔嚓！"** — third rewrite, this time with a
**Godot 4** client (HTML5 export) wired to the v2 TypeScript multiplayer
server.

![xiaodaoyiba v3 — R1 REVEAL phase static mock: 4 players (Bot-A, Bot-B, Hong, Ming) on an iso 45° stage with shingle-roofed houses, knife sprite in Bot-A's hand, persistent red briefs on Hong (ALIVE_PANTS_DOWN), BattleLog rail with timestamped rows on the right, ✊✋✌ HandPicker chips along the bottom](./docs/screenshots/action.png)
<sub>(static design mock — composed offline by `client/tests/render_action_static.gd`; the live HTML5 build at `pnpm serve` differs in art workflow but renders the same scene tree. See [WORKLOG.md](./WORKLOG.md) iter 17 for the live `screenshots/live-landing.png` capture.)</sub>

See [`FINAL_GOAL.md`](./FINAL_GOAL.md) for the full design brief and
[`ARCHITECTURE.md`](./ARCHITECTURE.md) for the scene-tree / protocol /
codegen layout. Iteration history lives in [`WORKLOG.md`](./WORKLOG.md).

## Stack

- **Game client** — Godot 4.3 stable (GDScript), exported to HTML5,
  served at `http://localhost:5173`.
- **Multiplayer server** — Node ≥ 20 + Socket.IO 4 + TypeScript, ported
  verbatim from v2's `packages/server/`.
- **Headless sim** — TypeScript CLI (`pnpm sim`), 50 rounds × 4 players
  in <2s, single-source game logic in `shared/`.

## Quickstart

```bash
# Prereqs: Node 20+, pnpm 9+, Godot 4.3 stable on PATH (`which godot`).
pnpm install                 # ≤ 60s on a clean clone

pnpm test                    # vitest suites (shared/, server/) — 90/90 green
pnpm typecheck               # tsc --noEmit across workspaces
pnpm sim                     # headless sim CLI (50 rounds × 4 players)

pnpm dev                     # server in watch mode (run godot --editor separately)
pnpm dev -- --with-godot     # also launch the Godot editor against client/

pnpm codegen:timing          # regenerate client/scripts/generated/Timing.gd
pnpm codegen:audio           # regenerate 8 SFX + 3 BGM WAVs from offline ZzFX
pnpm build                   # server bundle + Godot HTML5 export
pnpm build:server            # server-only bundle
pnpm build:client            # Godot HTML5 export only
pnpm serve                   # serve client/build/ at :5173 with COOP/COEP headers
```

## Repo layout

```
xiaodaoyiba-v3/
├── client/                  Godot 4.3 project (scaffolded in S-005)
├── server/                  TypeScript Socket.IO server (ported in S-003)
├── shared/                  Pure TS game logic (ported in S-002)
├── docs/screenshots/        Committed PNGs (hero image, anim strips)
├── scripts/
│   ├── dev.sh               server watch + optional godot --editor
│   ├── build.sh             pnpm codegen:* + server bundle + godot HTML5 export
│   ├── serve-html5.sh       static file server with COOP/COEP for Godot threads
│   └── codegen-audio.mjs    offline ZzFX → WAV synth (S-148)
├── shared/scripts/
│   └── codegen-timing.ts    timing.ts → client/scripts/generated/Timing.gd
├── .github/workflows/
│   ├── ci.yml               pnpm install + test + sim --strict + godot --import
│   └── codegen-drift.yml    fail PR if codegen output drifts from committed file
├── package.json             workspace root (pnpm)
├── pnpm-workspace.yaml      lists shared/, server/
├── tsconfig.base.json       strict TS6.0 baseline
├── .nvmrc                   Node 20
├── FINAL_GOAL.md            design brief
├── ARCHITECTURE.md          scene tree, protocol, codegen
└── WORKLOG.md               append-only iteration log
```

## Status

Iterations 1–15 have shipped a playable end-to-end build. The
screenshot above is a **static mock** composed by
`client/tests/render_action_static.gd` — it blits the SpriteAtlas
house + character ImageTextures onto a hand-painted iso ground plane,
then layers the phase banner, BattleLog, and HandPicker UI using a
hand-rolled 5×7 bitmap font (ASCII) plus the committed
NotoColorEmoji.ttf bitmap glyphs (✊ ✋ ✌). It runs in any
`godot --headless` environment with no GPU, no SubViewport, and no CI
font dependencies. A live HTML5-export capture is gated on the
browser-MCP install in iter-16+; until then the mock truthfully
demonstrates the §C11 viral aesthetic and §C8 BattleLog palette
without claiming to be a runtime screenshot.

**TypeScript shared + server (S-002 / S-003 / S-004)** — `shared/`
holds the canonical game logic ported verbatim from v2: `engine.ts`
(6-phase round, no `PHASE_T_RETURN` per §K2), `rps.ts` (multi-player
RPS resolution for N≥3), `timing.ts` (single source of truth for ms
constants), `effects.ts` (the `Effect[]` choreography protocol),
`bots/{counter,random,iron,mirror}.ts` (seeded-RNG diversified
strategies), and `narrative/lines.ts` (8 tie variants + 7
`pullOwnPantsUpVariants`). `server/` runs Socket.IO 4 over
`WebSocketPeer`, with `Room.ts`, `matchmaking.ts`, the `/healthz`
endpoint, and the agency-aware winner-picker flow (9-second
`WINNER_CHOICE_BUDGET_MS`, auto-pick fallback).
**`pnpm test` → 90/90 green** (79 shared + 11 server) in <1s.

**Headless sim CLI (S-004)** — `pnpm sim --players 4 --bots
counter,random,iron,mirror --winner-strategy
random-target+random-action --rounds 50 --seed 42` exits 0 with the
canonical acceptance numbers: **5 games, 50 rounds, tie_rate=0.260
(<0.30 ✓), max winner share=0.40 (<0.60 ✓), `PULL_OWN_PANTS_UP` fires
≥1× ✓**, duration_ms=8 (≪ 2000ms budget). Output preserves the v6
columns `round, throws_kv, winners, losers, action, target,
winner_picked_target, winner_picked_action, narration`. `--strict`
mode fails the run if any §A2/§A3 budget breaches.

**Godot HTML5 client (S-005 / S-098 / S-109 / S-119 / S-148)** — the
full Godot 4.3 project tree under `client/` with 16 `.tscn` scenes,
GDScript autoloads (`Net.gd` speaks Engine.IO v4 / Socket.IO v4
directly over `WebSocketPeer`, no addon; `GameState.gd` keeps the
room snapshot; `Audio.gd` is the SFX/BGM bus with mute persisted to
`user://settings.cfg`; `Timing.gd` is the codegen target;
`SpriteAtlas.gd` renders procedural pixel-art at boot — characters
across 5 states, houses across 4 damage stages, knife sprite, throw
FX dots), and gameplay scripts (`Camera.gd` runs three-stage
cinematic zoom-pan-zoom for §C2; `EffectPlayer.gd` schedules
`Effect[]` dispatches by `atMs`; `GameStage.gd` owns the iso world).
Iso 45° ground via `_draw()` diamond lattice. ✊✋✌ throw glyphs
render via the committed `NotoColorEmoji.ttf` CBDT/CBLC font with
`disable_embedded_bitmaps=false` so the colour bitmap strikes
actually paint. Persistent-shame state machine (red ankle briefs in
every phase until `PULL_OWN_PANTS_UP`). Winner-picker dialog with
target + action selection. `client/build/index.html` HTML5 export
boots in a browser via `pnpm serve` at :5173 with COOP/COEP headers
for SharedArrayBuffer threads.

**Audio bus (S-148)** — 8 SFX (`tap`, `reveal`, `pull`, `chop`,
`dodge`, `thud`, `victory`, `defeat`) and 3 BGM variants (`lobby`,
`battle`, `victory`) under `client/assets/audio/`, generated by
`pnpm codegen:audio` — an offline Node port of v2's ZzFX 1.3.2
micro-renderer that synthesizes 44.1 kHz / 16-bit / mono PCM WAVs
deterministically (preset-name-seeded `mulberry32` PRNG, byte-stable
across CI runs). `.import` sidecars set `loop_mode=2` (Forward) on
BGM so cross-fades stay continuous. `tests/audio_smoke.gd` asserts
every named slot resolves to a non-null `AudioStreamWAV` — total
~3.2 MB, well under the §E3 6 MB soft cap.

**CI (S-129 / S-139)** — `.github/workflows/ci.yml` runs the full
§E5 pipeline on every push and PR: `pnpm install --frozen-lockfile`,
`pnpm test`, `pnpm sim ... --strict --seed 42`, then a hermetic
Godot 4.3-stable install (`Godot_v4.3-stable_linux.x86_64.zip`)
followed by `godot --headless --path client --import` to verify the
project imports cleanly. `.github/workflows/codegen-drift.yml` runs
`pnpm codegen:timing` and fails the PR if the regenerated
`Timing.gd` differs from the committed file — drift detection per
§A4. `concurrency.cancel-in-progress` prevents stacked runs.

**Codegen-timing drift gate (S-129)** — `shared/scripts/codegen-timing.ts`
imports the timing constants from `shared/src/game/timing.ts` and
writes `client/scripts/generated/Timing.gd` byte-deterministically.
The six previously-hand-maintained GD-only constants
(`ZOOM_IN_DUR_MS`, `ZOOM_HOLD_MS`, `ZOOM_OUT_DUR_MS`, `ZOOM_TARGET`,
`WINNER_CHOICE_BUDGET_MS`, `PICKER_AUTO_PICK_MS`) were promoted into
`timing.ts` so it is genuinely the single source of truth.
`server/src/rooms/Room.ts` imports `WINNER_CHOICE_BUDGET_MS` from
`@xdyb/shared` instead of declaring its own literal.

## Outstanding (next iteration candidates)

See [`WORKLOG.md`](./WORKLOG.md) for the latest judge brief.
Still-open work as of iteration 12: house wall texture / shingle
detail (§C11 viral-aesthetic gate), nickname-label legibility on
roofs, animation-timing trace evidence (`tests/sample_animation.gd`),
protocol-driven `ZOOM_IN`/`ZOOM_OUT` effects in `effects.ts`, and a
browser-MCP prerequisites script for the Definition-of-Done UI gate
(blocked on `sudo` inside the WSL2 sandbox).
