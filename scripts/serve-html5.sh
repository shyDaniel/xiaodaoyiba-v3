#!/usr/bin/env bash
# scripts/serve-html5.sh — serve the exported Godot HTML5 build at :5173.
#
# Godot's HTML5 export requires Cross-Origin-Opener-Policy: same-origin and
# Cross-Origin-Embedder-Policy: require-corp headers for SharedArrayBuffer
# (Godot 4 threads). We use `npx serve` with a custom headers config OR fall
# back to a tiny Node static server that sets the COOP/COEP headers.
#
# Usage:
#   scripts/serve-html5.sh           # serve client/build at :5173
#   PORT=8080 scripts/serve-html5.sh # override port
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PORT="${PORT:-5173}"
DIR="client/build"

if [[ ! -f "$DIR/index.html" ]]; then
  echo "[serve] $DIR/index.html missing — run \`pnpm build\` (or \`pnpm build:client\`) first." >&2
  exit 1
fi

# S-362: refuse to serve a stale HTML5 build. If any .tscn / .gd / .import /
# project.godot source is newer than client/build/index.pck, the live game
# would ship the OLD localization (e.g. English Lobby panel) even though the
# source has been updated. That is a brand-identity bug — fail loud instead
# of silently serving stale strings.
if [[ -f "$DIR/index.pck" ]]; then
  STALE=$(find client/scenes client/scripts client/project.godot \
    \( -name '*.tscn' -o -name '*.gd' -o -name '*.import' -o -name 'project.godot' \) \
    -newer "$DIR/index.pck" 2>/dev/null | head -5 || true)
  if [[ -n "${STALE:-}" ]]; then
    echo "[serve] STALE BUILD: source files are newer than $DIR/index.pck:" >&2
    echo "${STALE}" | sed 's/^/  /' >&2
    if [[ "${ALLOW_STALE:-0}" = "1" ]]; then
      echo "[serve] ALLOW_STALE=1 set — serving stale build anyway." >&2
    else
      echo "[serve] Run \`pnpm build:client\` to re-export (or set ALLOW_STALE=1 to override)." >&2
      exit 2
    fi
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
