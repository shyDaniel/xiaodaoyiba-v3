// scripts/validate-winner-picker.mjs — S-445 deterministic WinnerPicker harness.
//
// Drives a real chrome-headless-shell against http://localhost:5173 with a
// dev server that was started with XDYB_DEBUG_BOT_CHOICE=1, and:
//
//   1. Creates a room (xdyb_landing_create).
//   2. Adds 2 bots (xdyb_lobby_addBot ×2).
//   3. Polls window.xdyb_debug_getBots() for the server-assigned bot ids.
//   4. Forces both bots to throw SCISSORS for round 1 via
//      window.xdyb_debug_forceBotChoice(botId, 'SCISSORS').
//   5. Starts the game (xdyb_lobby_start).
//   6. Throws ROCK as the local human (xdyb_game_throw).
//   7. Waits for room:winnerChoice on the wire (the server emits it
//      personalized to the unique-winner socket).
//   8. Screenshots the picker overlay to ${SHOTS}/picker.png.
//   9. Runs scripts/check-winner-picker-pixels.py on it; passes only if
//      the panel + ≥2 target rows + ≥3 action buttons all read as
//      structurally present.
//
// Acceptance (matches FINAL_GOAL §C10 / S-445 brief):
//   - room:winnerChoice arrives RX-side after the human's ROCK throw.
//   - The PNG passes scripts/check-winner-picker-pixels.py.
//
// Exit codes:
//   0 — pass
//   1 — drove fine but acceptance not met (no winnerChoice frame, or
//       pixels failed)
//   2 — fundamental failure (bridges missing, server unreachable,
//       chrome crashed)

import { chromium } from "/home/hanyu/.cache/xdyb-playwright-core/1.59.1/package/index.mjs";
import fs from "node:fs";
import { spawnSync } from "node:child_process";

const URL_ = process.env.URL || "http://localhost:5173/";
const HEADLESS_SHELL = process.env.HEADLESS_SHELL ||
  process.env.HOME + "/.cache/ms-playwright/chromium_headless_shell-1217/chrome-headless-shell-linux64/chrome-headless-shell";
const CHROME_LIBS = process.env.CHROME_LIBS ||
  process.env.HOME + "/.local/chrome-libs/usr/lib/x86_64-linux-gnu";
process.env.LD_LIBRARY_PATH = (process.env.LD_LIBRARY_PATH ? process.env.LD_LIBRARY_PATH + ":" : "") + CHROME_LIBS;

const SHOTS = process.env.SHOTS || "/tmp/judge_winner_picker";
fs.mkdirSync(SHOTS, { recursive: true });

const wsFrames = [];
let exit = 1;

const browser = await chromium.launch({
  executablePath: HEADLESS_SHELL,
  args: [
    "--no-sandbox",
    "--use-gl=angle",
    "--use-angle=swiftshader",
    "--enable-unsafe-swiftshader",
    "--disable-dev-shm-usage",
  ],
});

try {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  const page = await ctx.newPage();
  page.on("console", m => process.stderr.write(`[chrome:${m.type()}] ${m.text().slice(0, 200)}\n`));
  page.on("pageerror", e => process.stderr.write(`[chrome:pageerror] ${e.message}\n`));
  page.on("websocket", ws => {
    ws.on("framereceived", f => { wsFrames.push("RX " + String(f.payload || "")); });
    ws.on("framesent",     f => { wsFrames.push("TX " + String(f.payload || "")); });
  });

  await page.goto(URL_, { waitUntil: "domcontentloaded", timeout: 30000 });
  await page.waitForFunction(() => {
    const c = document.querySelector("canvas");
    return c && c.width > 0 && c.height > 0;
  }, { timeout: 30000 });
  // Settle Godot scene tree so autoload _ready() fires and the Landing
  // scene's xdyb_landing_create bridge is installed.
  await page.waitForTimeout(8000);

  // S-445 — confirm the debug bridges installed by GameState.gd are
  // present BEFORE we start. If they're not, the run is hopeless and
  // we want a clear "missing bridge" failure not a timeout 30s in.
  const haveBridges = await page.evaluate(() => ({
    landing: typeof window.xdyb_landing_create === "function",
    addBot:  typeof window.xdyb_lobby_addBot === "function",
    start:   typeof window.xdyb_lobby_start === "function",
    throw_:  typeof window.xdyb_game_throw === "function",
    forceBot: typeof window.xdyb_debug_forceBotChoice === "function",
    getBots:  typeof window.xdyb_debug_getBots === "function",
  }));
  process.stderr.write(`[bridges] ${JSON.stringify(haveBridges)}\n`);
  // landing+addBot+start may not all be installed before scene change;
  // we only require the autoload-level debug bridges + landing here.
  if (!haveBridges.landing) {
    process.stderr.write("[drive] FATAL — xdyb_landing_create not installed\n");
    exit = 2;
    throw new Error("missing landing bridge");
  }
  if (!haveBridges.forceBot || !haveBridges.getBots) {
    process.stderr.write("[drive] FATAL — debug bridges missing; did you start the server with XDYB_DEBUG_BOT_CHOICE=1?\n");
    exit = 2;
    throw new Error("missing debug bridges");
  }

  // 1. Create room.
  await page.evaluate(() => window.xdyb_landing_create());
  await page.waitForTimeout(2500);
  await page.screenshot({ path: `${SHOTS}/01-after-create.png`, fullPage: false });

  // 2. Add 2 bots — wait for the lobby bridge first.
  await page.waitForFunction(
    () => typeof window.xdyb_lobby_addBot === "function",
    { timeout: 10000 }
  );
  for (let i = 0; i < 2; i++) {
    await page.evaluate(() => window.xdyb_lobby_addBot());
    await page.waitForTimeout(500);
  }
  await page.waitForTimeout(1500); // let snapshots roll in
  await page.screenshot({ path: `${SHOTS}/02-after-bots.png`, fullPage: false });

  // 3. Read bot ids back from the snapshot mirror.
  const botsJson = await page.evaluate(() => window.xdyb_debug_getBots());
  let bots = [];
  try { bots = JSON.parse(botsJson); } catch (_) { bots = []; }
  process.stderr.write(`[bots] ${JSON.stringify(bots)}\n`);
  if (bots.length < 2) {
    process.stderr.write(`[drive] FAIL — expected ≥2 bots in snapshot, got ${bots.length}\n`);
    fs.writeFileSync(`${SHOTS}/wsframes.txt`, wsFrames.join("\n") + "\n");
    throw new Error("not enough bots");
  }

  // 4. Force each bot to throw SCISSORS so the human's ROCK is the
  //    unique winner with 2 eligible targets.
  for (const bot of bots.slice(0, 2)) {
    const ok = await page.evaluate((id) => {
      try {
        window.xdyb_debug_forceBotChoice(id, "SCISSORS");
        return true;
      } catch (e) {
        return false;
      }
    }, bot.id);
    process.stderr.write(`[force] bot=${bot.id} ok=${ok}\n`);
  }

  // 5. Start.
  await page.evaluate(() => window.xdyb_lobby_start());
  await page.waitForTimeout(2500);
  await page.screenshot({ path: `${SHOTS}/03-after-start.png`, fullPage: false });

  // 6. Wait for the throw bridge, then throw ROCK.
  await page.waitForFunction(
    () => typeof window.xdyb_game_throw === "function",
    { timeout: 10000 }
  );
  await page.evaluate(() => window.xdyb_game_throw("ROCK"));
  process.stderr.write("[throw] ROCK\n");

  // 7. Poll the WS frame log for an RX with "room:winnerChoice". The
  //    server emits this socket-personalized; we should see it on the
  //    wire as a RX frame on the human's socket. Up to 6s to allow
  //    server timing (PRE_REVEAL_HOLD_MS, REVEAL_DURATION_MS). After
  //    server emits, the picker fades in (180ms) — wait an extra
  //    400ms before the screenshot.
  const startWait = Date.now();
  let sawWinnerChoice = false;
  while (Date.now() - startWait < 8000) {
    if (wsFrames.some(f => f.startsWith("RX") && f.includes("room:winnerChoice"))) {
      sawWinnerChoice = true;
      break;
    }
    await page.waitForTimeout(150);
  }
  process.stderr.write(`[picker] sawWinnerChoice=${sawWinnerChoice} waited=${Date.now() - startWait}ms\n`);

  // Sample the picker fully visible — the open() animation ramps over
  // 0.18s; a 600ms pad is comfortable.
  await page.waitForTimeout(600);
  const pickerPath = `${SHOTS}/picker.png`;
  await page.screenshot({ path: pickerPath, fullPage: false });

  // 8. Pixel-assert the picker.
  const pix = spawnSync("python3", [
    `${process.cwd()}/scripts/check-winner-picker-pixels.py`,
    pickerPath,
    "--json",
  ], { encoding: "utf8" });
  const pixOut = (pix.stdout || "").trim();
  const pixErr = (pix.stderr || "").trim();
  process.stderr.write(`[pixel-check] status=${pix.status}\n${pixOut}\n`);
  if (pixErr) process.stderr.write(`[pixel-check stderr] ${pixErr}\n`);
  fs.writeFileSync(`${SHOTS}/pixel-check.json`, pixOut + "\n");

  // 9. Persist the WS log + final acceptance.
  fs.writeFileSync(`${SHOTS}/wsframes.txt`, wsFrames.join("\n") + "\n");

  const pixelsPass = pix.status === 0;
  const accept = sawWinnerChoice && pixelsPass;
  process.stderr.write(`[acc] sawWinnerChoice=${sawWinnerChoice} pixelsPass=${pixelsPass}\n`);
  if (accept) {
    process.stderr.write("[drive] PASS — picker visible + pixels structurally correct\n");
    exit = 0;
  } else {
    process.stderr.write(`[drive] FAIL — see ${SHOTS}/wsframes.txt and ${SHOTS}/pixel-check.json\n`);
  }
} catch (err) {
  process.stderr.write(`[drive] threw: ${err && err.stack || err}\n`);
  if (exit === 1) exit = 2;
} finally {
  await browser.close();
}

process.exit(exit);
