# Architecture — xiaodaoyiba v3

This file is appended-to as design decisions firm up. The first cut is
intentionally short: only the workspace skeleton exists. Sections marked
**(pending)** will be filled in by subsequent subtasks.

## Top-level shape

```
xiaodaoyiba-v3/         pnpm monorepo, two TS packages + one Godot project
├── shared/             pure TS game logic (no DOM, no Node, no Godot)
├── server/             Socket.IO entry + Room.ts + matchmaking + sim CLI
├── client/             (pending S-005) Godot 4.3 project, HTML5 export target
├── scripts/            shell entry points (dev.sh, build.sh, serve-html5.sh)
└── (root)              workspace + tsconfig + docs
```

## Workspace topology

`pnpm-workspace.yaml` lists exactly two packages:

- `shared/` — `@xdyb/shared`, pure-TS, no runtime deps.
- `server/` — `@xdyb/server`, depends on `@xdyb/shared` via
  `workspace:*`, plus `socket.io`. Owns the headless sim CLI.

Godot lives at `client/` but is **not** a pnpm workspace package — it's
a Godot project tree imported by the `godot` CLI directly. The build
glue lives in `scripts/build.sh` (`godot --headless --export-release Web`).

## Why three packages instead of one

The v2 codebase already split shared/server/client cleanly and the v6
acceptance criterion B4 demands shared `shared/src/game/` between live
server and headless sim. Keeping `shared` as its own package preserves
that single-source-of-truth property and lets the timing-codegen step
(criterion A4) emit `client/scripts/generated/Timing.gd` from a
well-defined location.

## Scripts

- `scripts/dev.sh` — runs `@xdyb/server` in `tsx watch` mode.
  `--with-godot` additionally launches `godot --editor --path client`
  (Godot has no JS-level HMR, so the editor is the iteration loop).
- `scripts/build.sh` — builds the server bundle (`tsup` → `server/dist/`)
  and exports the Godot HTML5 build to `client/build/`. Flags:
  `--server-only`, `--client-only`. Soft-warns if HTML5 bundle exceeds
  6 MB (FINAL_GOAL §E3).
- `scripts/serve-html5.sh` — tiny Node static server that sets
  `Cross-Origin-Opener-Policy: same-origin` and
  `Cross-Origin-Embedder-Policy: require-corp` headers. These are
  required for Godot 4 HTML5 threads (SharedArrayBuffer); a vanilla
  `npx serve` would fail to load the game with a CORS error.

## Effect[] protocol (S-003 — server side landed; S-004 — sim CLI pending)

The server emits a JSON `Effect[]` per resolved round. Both the live
Godot client and the (in-progress) headless sim consume the same
array. The full Effect union is declared in
`shared/src/game/effects.ts` and re-exported through `@xdyb/shared`;
`Room.resolveCurrentRound()` calls `resolveRound(...)` (also from
`@xdyb/shared`) and broadcasts the result on the `room:effects`
Socket.IO channel via `RoomBroadcaster.emitRound`. Each Effect carries
an `atMs` offset; the client's EffectPlayer schedules scene-tree calls
at those offsets, so the server only throttles round-to-round
transitions (`ROUND_TOTAL_MS = 4700ms`, `TIE_NARRATION_HOLD_MS =
2000ms`), never per-phase ticks.

Socket.IO channels (server → client):
- `room:snapshot` — `RoomSnapshot` on every membership / state change.
- `room:effects` — `RoundBroadcast` ({round, effects[], narration, isGameOver, winnerId}).
- `room:winnerChoice` — `WinnerChoicePrompt` to one socket when a human winner has §H3 agency.
- `room:error` — `{code, message}` validation rejections.

Socket.IO channels (client → server):
- `room:create {nickname}`, `room:join {code, nickname}`, `room:leave`.
- `room:addBot`, `room:start`, `room:rematch` (host-only).
- `room:choice {choice: 'ROCK'|'PAPER'|'SCISSORS'}`.
- `room:winnerChoice {target: string|null, action: ActionKind|null}` (within 9000ms `WINNER_CHOICE_BUDGET_MS`).

v3 already includes the v2 Effect types `RPS_REVEAL` (per-player throw
glyph hold, 1500ms) and `ZOOM_IN` / `ZOOM_OUT` (camera cinematic
markers) — no schema migration needed for the Godot client; it can
consume the same protocol the v2 PixiJS client did.

## Server build (S-003)

`server/tsup.config.ts` bundles `@xdyb/shared` into `server/dist/index.js`
via `noExternal: ['@xdyb/shared']`. Without this, Node would try to
`import` the workspace package's `main` field (`./src/index.ts`), fail
on `ERR_UNKNOWN_FILE_EXTENSION`, and refuse to boot — the workspace
strategy of pointing `main` at TS source is fine for dev (tsx) and for
intra-workspace test runs (vitest), but it requires the bundler to
inline the shared code for production startup.

## timing.ts ↔ Timing.gd codegen (pending S-006)

`shared/src/game/timing.ts` is the single source of truth. A
build-time script (`shared/scripts/codegen-timing.ts`, wired into
`pnpm codegen:timing`) emits `client/scripts/generated/Timing.gd`
with the same constant names and ms values. CI fails if the generated
file drifts from the TS source.

## Godot scene tree (pending S-005)

See `FINAL_GOAL.md` §"Repository structure" for the full scene tree.

## Why Godot (deliberate, see FINAL_GOAL §"Why a third rewrite")

Four structural gaps that v2 (PixiJS) exposed map to first-class Godot
features: isometric `TileMap`, `Camera2D` zoom/pan with `AnimationPlayer`,
keyframe-driven character state machines, and asset hot-reload via
`AnimatedSprite2D` + `AtlasTexture`. The TS server doesn't have any of
those concerns and stays.
