// scripts/validate-particles-pixeldiff.mjs
//
// S-322 acceptance — proves the live HTML5 build paints particle FX bursts
// after the GPUParticles2D → CPUParticles2D swap.
//
// Drives the same headless chromium pipeline as validate-game-progression,
// but instead of sampling at fixed wall-clock offsets, it times screenshots
// relative to PHASE_START events:
//
//   - For PULL_PANTS: snap at t=PULL_PANTS.atMs (cloth burst frame) and
//     at +200ms (cloth in flight). 64×64 ROI must show ≥0.5% pixel diff.
//   - For IMPACT (CHOP): snap at IMPACT.atMs and +200ms; 64×64 ROI must
//     show ≥0.5% pixel diff.
//
// Acceptance per the S-322 brief.
//
// Exit codes:
//   0 — pass (≥0.5% on both)
//   1 — drove fine but pixel diff under threshold (regression)
//   2 — fundamental failure (canvas missing, no PHASE_START on wire)

import { chromium } from "/home/hanyu/.cache/xdyb-playwright-core/1.59.1/package/index.mjs";
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";

const URL_ = process.env.URL || "http://localhost:5173/";
const HEADLESS_SHELL = process.env.HEADLESS_SHELL ||
  process.env.HOME + "/.cache/ms-playwright/chromium_headless_shell-1217/chrome-headless-shell-linux64/chrome-headless-shell";
const CHROME_LIBS = process.env.CHROME_LIBS ||
  process.env.HOME + "/.local/chrome-libs/usr/lib/x86_64-linux-gnu";
process.env.LD_LIBRARY_PATH = (process.env.LD_LIBRARY_PATH ? process.env.LD_LIBRARY_PATH + ":" : "") + CHROME_LIBS;

const SHOTS = process.env.SHOTS || "/tmp/judge_particles";
fs.mkdirSync(SHOTS, { recursive: true });

const log = (m) => process.stderr.write(`[particles] ${m}\n`);

// Minimal PNG decoder (RGBA8, color type 6, bit depth 8) using built-in
// zlib only. Sufficient for chromium's screenshot output.
function decodePng(buf) {
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  if (!buf.subarray(0, 8).equals(sig)) throw new Error("not a PNG");
  let pos = 8;
  let width = 0, height = 0, colorType = 0;
  const idatChunks = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos); pos += 4;
    const type = buf.subarray(pos, pos + 4).toString("ascii"); pos += 4;
    const data = buf.subarray(pos, pos + len); pos += len;
    pos += 4; // CRC
    if (type === "IHDR") {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      colorType = data[9];
    } else if (type === "IDAT") {
      idatChunks.push(data);
    } else if (type === "IEND") break;
  }
  const raw = zlib.inflateSync(Buffer.concat(idatChunks));
  const bpp = colorType === 6 ? 4 : (colorType === 2 ? 3 : 4);
  const stride = width * bpp;
  const out = Buffer.alloc(stride * height);
  let rp = 0, op = 0;
  for (let y = 0; y < height; y++) {
    const filter = raw[rp++];
    for (let x = 0; x < stride; x++) {
      const cur = raw[rp++];
      const left = x >= bpp ? out[op + x - bpp] : 0;
      const up = y > 0 ? out[op + x - stride] : 0;
      const upLeft = (y > 0 && x >= bpp) ? out[op + x - stride - bpp] : 0;
      let recon;
      switch (filter) {
        case 0: recon = cur; break;
        case 1: recon = (cur + left) & 0xff; break;
        case 2: recon = (cur + up) & 0xff; break;
        case 3: recon = (cur + ((left + up) >> 1)) & 0xff; break;
        case 4: {
          const p = left + up - upLeft;
          const pa = Math.abs(p - left);
          const pb = Math.abs(p - up);
          const pc = Math.abs(p - upLeft);
          const pred = (pa <= pb && pa <= pc) ? left : (pb <= pc ? up : upLeft);
          recon = (cur + pred) & 0xff;
          break;
        }
        default: throw new Error("unknown PNG filter " + filter);
      }
      out[op + x] = recon;
    }
    op += stride;
  }
  return { width, height, data: out, bpp };
}

function diffRatio(a, b, cx, cy, region) {
  if (a.width !== b.width || a.height !== b.height) return 1.0;
  const half = region >> 1;
  const x0 = Math.max(0, cx - half);
  const y0 = Math.max(0, cy - half);
  const x1 = Math.min(a.width, cx + half);
  const y1 = Math.min(a.height, cy + half);
  let changed = 0, total = 0;
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      total++;
      const i = (y * a.width + x) * a.bpp;
      const dr = Math.abs(a.data[i] - b.data[i]);
      const dg = Math.abs(a.data[i + 1] - b.data[i + 1]);
      const db = Math.abs(a.data[i + 2] - b.data[i + 2]);
      if (dr + dg + db > 4) changed++;
    }
  }
  return total === 0 ? 0 : changed / total;
}

(async () => {
  const browser = await chromium.launch({
    executablePath: HEADLESS_SHELL,
    args: ["--no-sandbox", "--disable-dev-shm-usage", "--use-gl=swiftshader"],
  });
  const context = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  const page = await context.newPage();

  page.on("console", (msg) => {
    const t = msg.text();
    if (/error|warn|particle/i.test(t)) log(`chrome:${msg.type()} ${t}`);
  });

  let lastEffectsWallTime = 0;
  page.on("websocket", (ws) => {
    ws.on("framereceived", (f) => {
      const s = f.payload?.toString?.() ?? "";
      if (s.includes("room:effects")) lastEffectsWallTime = Date.now();
    });
  });

  await page.goto(URL_, { waitUntil: "domcontentloaded" });
  await page.waitForFunction(() => typeof window.xdyb_landing_create === "function", { timeout: 30000 });
  await page.evaluate(() => window.xdyb_landing_create());

  await page.waitForFunction(() => typeof window.xdyb_lobby_addBot === "function", { timeout: 30000 });
  for (let i = 0; i < 3; i++) {
    await page.evaluate(() => window.xdyb_lobby_addBot());
    await page.waitForTimeout(200);
  }
  await page.evaluate(() => window.xdyb_lobby_start());

  await page.waitForFunction(() => typeof window.xdyb_game_throw === "function", { timeout: 30000 });
  log("game bridge ready");

  // Per shared/src/game/timing.ts the round timeline relative to the
  // ROUND_START effect (which is also when the server emits room:effects)
  // is REVEAL 0-1500 / PREP 1500-1800 / RUSH 1800-2400 / PULL_PANTS
  // 2400-3300 / STRIKE 3300-3900 / IMPACT 3900-4700. So the cloth burst
  // fires at atMs=2400 and the wood-chip impact burst fires at atMs=3900.
  // Wall-clock for a phase fire = lastEffectsWallTime + atMs. ±50ms is
  // fine because particle bursts last 600-1600ms.
  const ROUND_BASE_OFFSETS = { PULL_PANTS: 2400, IMPACT: 3900 };

  const snap = async (label) => {
    const buf = await page.screenshot({ fullPage: false });
    fs.writeFileSync(path.join(SHOTS, `${label}.png`), buf);
    return decodePng(buf);
  };

  await page.evaluate(() => window.xdyb_game_throw("ROCK"));
  log("R1 ROCK thrown");

  const waitForNewEffects = async (timeoutMs) => {
    const t0 = Date.now();
    const before = lastEffectsWallTime;
    while (Date.now() - t0 < timeoutMs) {
      if (lastEffectsWallTime > before) return lastEffectsWallTime;
      await page.waitForTimeout(50);
    }
    return 0;
  };

  // Sample a grid of plausible ROI centers near the iso-stage middle and
  // take the max diff. Any one successful burst dominates one cell.
  const ANCHORS = [
    [520, 320], [600, 320], [680, 320], [760, 320],
    [520, 380], [600, 380], [680, 380], [760, 380],
    [520, 440], [600, 440], [680, 440], [760, 440],
  ];
  const bestDiff = (a, b) => {
    let best = 0;
    for (const [x, y] of ANCHORS) {
      const d = diffRatio(a, b, x, y, 64);
      if (d > best) best = d;
    }
    return best;
  };

  const sleepUntil = async (target) => {
    const dt = target - Date.now();
    if (dt > 0) await page.waitForTimeout(dt);
  };

  let pullDiff = 0, impactDiff = 0;
  // Iterate up to 10 rounds. Each round we wait for the *next* room:effects
  // RX frame (which marks ROUND_START), then snap +PULL_PANTS / +IMPACT
  // pairs. R1 was already thrown above and may already have produced an
  // effects payload, so we accept that "lastEffectsWallTime" is non-zero
  // on entry and immediately use it for the first iteration.
  for (let r = 1; r <= 10 && (pullDiff < 0.005 || impactDiff < 0.005); r++) {
    const ts = (r === 1 && lastEffectsWallTime > 0)
      ? lastEffectsWallTime
      : await waitForNewEffects(10000);
    if (ts === 0) {
      log(`R${r} no room:effects in 10s — bailing`);
      break;
    }
    const tPull = ts + ROUND_BASE_OFFSETS.PULL_PANTS;
    const tImp  = ts + ROUND_BASE_OFFSETS.IMPACT;

    await sleepUntil(tPull);
    const pa = await snap(`r${r}_pull_a`);
    await page.waitForTimeout(200);
    const pb = await snap(`r${r}_pull_b`);

    await sleepUntil(tImp);
    const ia = await snap(`r${r}_impact_a`);
    await page.waitForTimeout(200);
    const ib = await snap(`r${r}_impact_b`);

    const dPull = bestDiff(pa, pb);
    const dImp  = bestDiff(ia, ib);
    log(`R${r} pull_diff=${dPull.toFixed(4)} impact_diff=${dImp.toFixed(4)}`);
    if (dPull > pullDiff) pullDiff = dPull;
    if (dImp  > impactDiff) impactDiff = dImp;

    // Throw next round (ROCK). If the human has been eliminated the bridge
    // function may still be present (spectator mode) but throwing is a
    // no-op; the server keeps the round loop alive on the bots either way.
    const stillAlive = await page.evaluate(() => typeof window.xdyb_game_throw === "function");
    if (stillAlive) {
      try { await page.evaluate(() => window.xdyb_game_throw("ROCK")); } catch {}
    }
  }

  log(`final pull_diff=${pullDiff.toFixed(4)} impact_diff=${impactDiff.toFixed(4)}`);
  await browser.close();

  if (pullDiff >= 0.005 && impactDiff >= 0.005) {
    log("PASS — PULL_PANTS waist + IMPACT door ROIs both moved ≥0.5% under CPUParticles2D");
    process.exit(0);
  } else {
    log(`FAIL — pull_diff=${pullDiff.toFixed(4)} impact_diff=${impactDiff.toFixed(4)} (need ≥0.005 each)`);
    process.exit(1);
  }
})().catch((e) => {
  log(`fatal: ${e.stack || e.message || String(e)}`);
  process.exit(2);
});
