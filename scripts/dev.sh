#!/usr/bin/env bash
# scripts/dev.sh — start the v3 dev environment.
#
# Runs the multiplayer TypeScript server in watch mode, and (if --with-godot
# is passed) launches the Godot editor against client/. The Godot HTML5
# export served at :5173 is rebuilt manually via `pnpm dev:godot:rebuild`
# (Godot has no JS-level HMR — see FINAL_GOAL §B3).
#
# Usage:
#   scripts/dev.sh                # server-only (default; godot editor opens separately)
#   scripts/dev.sh --with-godot   # also launch godot --editor against client/
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

WITH_GODOT=0
for arg in "$@"; do
  case "$arg" in
    --with-godot) WITH_GODOT=1 ;;
    *) ;;
  esac
done

if [[ ! -d "shared" || ! -d "server" ]]; then
  echo "[dev] shared/ and server/ workspace packages missing — run pnpm install at repo root first." >&2
  exit 1
fi

cleanup() {
  trap - INT TERM
  jobs -p | xargs -r kill 2>/dev/null || true
}
trap cleanup INT TERM EXIT

echo "[dev] starting @xdyb/server in watch mode..."
pnpm --filter @xdyb/server dev &
SERVER_PID=$!

if [[ "$WITH_GODOT" -eq 1 ]]; then
  if ! command -v godot >/dev/null 2>&1; then
    echo "[dev] godot not on PATH; install Godot 4.3 stable to /home/hanyu/bin/godot or similar" >&2
    wait "$SERVER_PID"
    exit 1
  fi
  if [[ ! -f "client/project.godot" ]]; then
    echo "[dev] client/project.godot missing — Godot client not scaffolded yet; running server-only" >&2
  else
    echo "[dev] launching Godot editor against client/..."
    godot --editor --path client &
  fi
fi

wait "$SERVER_PID"
