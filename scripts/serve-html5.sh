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
