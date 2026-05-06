#!/usr/bin/env bash
# scripts/serve-html5.sh — serve the exported Godot HTML5 build at :5173.
#
# Godot's HTML5 export requires Cross-Origin-Opener-Policy: same-origin and
# Cross-Origin-Embedder-Policy: require-corp headers for SharedArrayBuffer
# (Godot 4 threads). We use a tiny Node static server that sets the COOP/COEP
# headers.
#
# Stale-build guard (S-409 — replaces the older S-362 narrower check):
#   The served bundle (client/build/index.pck) is silently authoritative for
#   what a real player sees in the browser. Iter-85 shipped 16 new house
#   composite PNGs but never re-exported, so the live game kept rendering
#   the old wallpaper houses for a full iteration. To prevent that class of
#   bug, this script now considers the build stale whenever ANY of the
#   following are newer than client/build/index.pck:
#
#     - client/scripts/**/*.gd
#     - client/scenes/**/*.tscn
#     - client/assets/**/*.png             (sprites, composites, atlases)
#     - client/assets/**/*.{jpg,jpeg,svg}  (other entity art)
#     - client/assets/**/*.import          (Godot import metadata)
#     - client/assets/**/*.{wav,ogg}       (audio)
#     - client/project.godot
#     - client/export_presets.cfg
#
#   When stale is detected we auto-invoke `pnpm build:client` to re-export the
#   HTML5 bundle. If the rebuild fails OR the build is still stale after the
#   rebuild, we exit non-zero. The previous ALLOW_STALE=1 escape hatch has
#   been removed — silent stale serves were the iter-85 root cause.
#
# Usage:
#   scripts/serve-html5.sh           # serve client/build at :5173
#   PORT=8080 scripts/serve-html5.sh # override port
#   NO_AUTO_BUILD=1 scripts/serve-html5.sh
#       # CI/judge-runner mode: refuse to start on stale build instead of
#       # auto-rebuilding (useful when the runner has no Godot binary).
set -euo pipefail

# Allow tests to inject a known repo root via XDYB_REPO_ROOT — production
# usage relies on the BASH_SOURCE-derived default.
ROOT="${XDYB_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

PORT="${PORT:-5173}"
DIR="client/build"

# Compute the list of source files newer than $DIR/index.pck. Echoes one path
# per line on stdout. Empty stdout = build is fresh.
list_stale_sources() {
  local pck="$1"
  [[ -f "$pck" ]] || { echo "$pck:missing"; return; }
  # Combine scripts/scenes/project.godot/export_presets AND assets/** in a
  # single find so ordering / pruning is consistent.
  find \
      client/scripts \
      client/scenes \
      client/assets \
      client/project.godot \
      client/export_presets.cfg \
      \( \
         -name '*.gd' \
         -o -name '*.tscn' \
         -o -name '*.png' \
         -o -name '*.jpg' \
         -o -name '*.jpeg' \
         -o -name '*.svg' \
         -o -name '*.import' \
         -o -name '*.wav' \
         -o -name '*.ogg' \
         -o -name 'project.godot' \
         -o -name 'export_presets.cfg' \
      \) \
      -newer "$pck" \
      2>/dev/null | head -25 || true
}

build_client() {
  echo "[serve] auto-triggering pnpm build:client to refresh HTML5 export..." >&2
  if command -v pnpm >/dev/null 2>&1; then
    pnpm build:client
  else
    bash scripts/build.sh --client-only
  fi
}

# If client/build/index.pck doesn't exist at all, we treat that as "stale".
if [[ ! -f "$DIR/index.pck" ]]; then
  echo "[serve] $DIR/index.pck missing — HTML5 build has never been exported." >&2
  if [[ "${NO_AUTO_BUILD:-0}" = "1" ]]; then
    echo "[serve] NO_AUTO_BUILD=1 set — refusing to auto-rebuild. Run \`pnpm build:client\`." >&2
    exit 2
  fi
  build_client
fi

# Always confirm index.html exists too (a partial export with no index.html
# would 404 every request — fail loud).
if [[ ! -f "$DIR/index.html" ]]; then
  echo "[serve] $DIR/index.html missing after build — Godot HTML5 export failed." >&2
  exit 3
fi

STALE_LIST=$(list_stale_sources "$DIR/index.pck")
if [[ -n "${STALE_LIST:-}" ]]; then
  echo "[serve] STALE BUILD: source files are newer than $DIR/index.pck:" >&2
  echo "${STALE_LIST}" | sed 's/^/  /' >&2

  if [[ "${NO_AUTO_BUILD:-0}" = "1" ]]; then
    echo "[serve] NO_AUTO_BUILD=1 set — refusing to auto-rebuild. Run \`pnpm build:client\`." >&2
    exit 2
  fi

  build_client

  # After rebuild, re-check. If still stale, the export silently dropped some
  # sources (e.g. .import files outside the export filter) — fail loud rather
  # than serve mismatched art.
  STALE_LIST=$(list_stale_sources "$DIR/index.pck")
  if [[ -n "${STALE_LIST:-}" ]]; then
    echo "[serve] STALE BUILD persists after rebuild — these sources are still newer:" >&2
    echo "${STALE_LIST}" | sed 's/^/  /' >&2
    echo "[serve] The Godot HTML5 export did not pick up these files. Aborting." >&2
    exit 4
  fi
fi

echo "[serve] serving $DIR at http://localhost:${PORT} (COOP/COEP enabled for Godot threads)..."
exec node -e "
const http = require('http');
const fs = require('fs');
const path = require('path');
const root = path.resolve('$DIR');
const port = Number(process.env.PORT || $PORT);
const mime = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.wav': 'audio/wav',
  '.ogg': 'audio/ogg'
};
http.createServer((req, res) => {
  let urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
  if (urlPath === '/' || urlPath.endsWith('/')) urlPath += 'index.html';
  const filePath = path.join(root, urlPath);
  if (!filePath.startsWith(root)) { res.statusCode = 403; res.end('forbidden'); return; }
  fs.readFile(filePath, (err, data) => {
    if (err) { res.statusCode = 404; res.end('not found'); return; }
    res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
    res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
    res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
    res.setHeader('Content-Type', mime[path.extname(filePath)] || 'application/octet-stream');
    res.end(data);
  });
}).listen(port, () => {
  console.log('[serve] http://localhost:' + port);
});
"
