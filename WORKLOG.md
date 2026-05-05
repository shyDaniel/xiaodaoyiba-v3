# Worklog

Append-only iteration log for xiaodaoyiba v3. Newest entries on top.

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
