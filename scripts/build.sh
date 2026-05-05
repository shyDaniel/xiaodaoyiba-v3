#!/usr/bin/env bash
# scripts/build.sh — produce production artifacts.
#
# - Builds the TypeScript server bundle to server/dist/.
# - Exports the Godot HTML5 client to client/build/index.html (+ .wasm + .pck).
#
# Flags:
#   --server-only   skip the Godot HTML5 export
#   --client-only   skip the server bundle (for `pnpm dev:godot:rebuild`)
#
# Soft caps: HTML5 bundle ≤ 6 MB (FINAL_GOAL §E3).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DO_SERVER=1
DO_CLIENT=1
for arg in "$@"; do
  case "$arg" in
    --server-only) DO_CLIENT=0 ;;
    --client-only) DO_SERVER=0 ;;
    *) ;;
  esac
done

if [[ "$DO_SERVER" -eq 1 ]]; then
  echo "[build] building @xdyb/server..."
  pnpm --filter @xdyb/server build
fi

if [[ "$DO_CLIENT" -eq 1 ]]; then
  if [[ ! -f "client/project.godot" ]]; then
    echo "[build] client/project.godot missing — Godot client not scaffolded yet; skipping HTML5 export." >&2
  elif ! command -v godot >/dev/null 2>&1; then
    echo "[build] godot not on PATH; skipping HTML5 export." >&2
  else
    mkdir -p client/build
    echo "[build] importing Godot project..."
    godot --headless --path client --import || true
    echo "[build] exporting Godot HTML5 release..."
    godot --headless --path client --export-release "Web" build/index.html
    if [[ -d client/build ]]; then
      SIZE_BYTES=$(du -sb client/build 2>/dev/null | awk '{print $1}')
      SIZE_MB=$(( SIZE_BYTES / 1024 / 1024 ))
      echo "[build] HTML5 bundle size: ${SIZE_MB} MB"
      if [[ "$SIZE_MB" -gt 6 ]]; then
        echo "[build] WARNING: HTML5 bundle ${SIZE_MB} MB exceeds 6 MB soft cap (FINAL_GOAL §E3)." >&2
      fi
    fi
  fi
fi

echo "[build] done."
