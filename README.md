# 小刀一把 v3 (xiaodaoyiba-v3)

Casual web multiplayer RPS-elimination game based on the Chinese nursery rhyme
**"小刀一把，来到你家，扒你裤衩，直接咔嚓！"** — third rewrite, this time with a
**Godot 4** client (HTML5 export) wired to the v2 TypeScript multiplayer
server.

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

pnpm test                    # vitest suites (shared/, server/)
pnpm typecheck               # tsc --noEmit across workspaces
pnpm sim                     # headless sim CLI (50 rounds × 4 players)

pnpm dev                     # server in watch mode (run godot --editor separately)
pnpm dev -- --with-godot     # also launch the Godot editor against client/

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
├── scripts/
│   ├── dev.sh               server watch + optional godot --editor
│   ├── build.sh             server bundle + godot HTML5 export
│   └── serve-html5.sh       static file server with COOP/COEP for Godot threads
├── package.json             workspace root (pnpm)
├── pnpm-workspace.yaml      lists shared/, server/
├── tsconfig.base.json       strict TS6.0 baseline
├── .nvmrc                   Node 20
├── FINAL_GOAL.md            design brief
├── ARCHITECTURE.md          scene tree, protocol, codegen
└── WORKLOG.md               append-only iteration log
```

## Status

Iteration 1 (S-001) scaffolded the pnpm workspace root. The Godot client,
the v2 server port, and the headless sim are pending in subsequent
subtasks. See [`WORKLOG.md`](./WORKLOG.md) for what's done and what's next.
