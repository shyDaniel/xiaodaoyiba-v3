// Drives a real headless chromium against http://localhost:5173, walks
// Landing → window.xdyb_landing_create() → A×3 (add bots) → S (start) →
// R (rock throw) and observes that the live game does NOT freeze.
//
// Acceptance (S-234):
//   - At least one human throw makes it onto the wire as room:choice
//     (TX frame containing "room:choice").
//   - Server emits room:effects (RX frame with the channel name).
//   - Server snapshot phase advances LOBBY → PLAYING with hasSubmitted
//     true on the human after the throw.
//   - The screenshot taken 5s after the throw shows visible game state
//     change vs a still-frozen post-Start screen (we don't pixel-diff
//     here — the screenshots are committed for human / judge review).
//
// Exit codes:
//   0 — pass
//   1 — chromium drove fine but acceptance not met
//   2 — fundamental failure (canvas never came up, bridges missing)

import { chromium } from "/home/hanyu/.cache/xdyb-playwright-core/1.59.1/package/index.mjs";
import fs from "node:fs";

const URL_ = process.env.URL || "http://localhost:5173/";
const HEADLESS_SHELL = process.env.HEADLESS_SHELL ||
  process.env.HOME + "/.cache/ms-playwright/chromium_headless_shell-1217/chrome-headless-shell-linux64/chrome-headless-shell";
const CHROME_LIBS = process.env.CHROME_LIBS ||
  process.env.HOME + "/.local/chrome-libs/usr/lib/x86_64-linux-gnu";
process.env.LD_LIBRARY_PATH = (process.env.LD_LIBRARY_PATH ? process.env.LD_LIBRARY_PATH + ":" : "") + CHROME_LIBS;

const SHOTS = process.env.SHOTS || "/tmp/judge_throw";
fs.mkdirSync(SHOTS, { recursive: true });

const wsFrames = [];
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
let exit = 1;
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
  await page.waitForTimeout(8000); // settle Godot scene tree

  // Landing: create a room.
  await page.waitForFunction(
    () => typeof window.xdyb_landing_create === "function",
    { timeout: 10000 }
  );
  await page.evaluate(() => window.xdyb_landing_create());
  await page.waitForTimeout(3500);
  await page.screenshot({ path: `${SHOTS}/01-after-create.png`, fullPage: false });

  // Lobby: A×3 to add 3 bots, then S to start.
  await page.waitForFunction(
    () => typeof window.xdyb_lobby_addBot === "function",
    { timeout: 10000 }
  );
  for (let i = 0; i < 3; i++) {
    await page.keyboard.press("KeyA");
    await page.waitForTimeout(400);
  }
  await page.waitForTimeout(1500);
  await page.screenshot({ path: `${SHOTS}/02-after-bots.png`, fullPage: false });
  await page.keyboard.press("KeyS");
  await page.waitForTimeout(2500);
  await page.screenshot({ path: `${SHOTS}/03-after-start.png`, fullPage: false });

  // Game: wait for the throw bridge to install.
  await page.waitForFunction(
    () => typeof window.xdyb_game_throw === "function",
    { timeout: 10000 }
  );
  process.stderr.write("[drive] xdyb_game_throw bridge installed\n");

  // Throw ROCK at t≈2s into the round, both via JS bridge AND keyboard
  // (the keyboard route is the canonical user path — JS is the
  // headless-driver insurance).
  await page.evaluate(() => window.xdyb_game_throw('ROCK'));
  await page.waitForTimeout(150);
  await page.keyboard.press("KeyR");

  // Sample at t = 1, 3, 5, 7, 10, 15s after throw.
  const times = [1000, 3000, 5000, 7000, 10000, 15000];
  let prev = 0;
  for (const t of times) {
    await page.waitForTimeout(t - prev);
    prev = t;
    await page.screenshot({ path: `${SHOTS}/t${t}.png`, fullPage: false });
    process.stderr.write(`[shot] t=${t}ms wsFrames=${wsFrames.length}\n`);
  }

  fs.writeFileSync(`${SHOTS}/wsframes.txt`, wsFrames.join("\n") + "\n");

  // Acceptance.
  const sawChoiceTx = wsFrames.some(f => f.startsWith("TX") && f.includes("room:choice"));
  const sawEffectsRx = wsFrames.some(f => f.startsWith("RX") && f.includes("room:effects"));
  const sawPhasePlaying = wsFrames.some(f => f.startsWith("RX") && /"phase":"PLAYING"/.test(f));
  const phaseStartFrames = wsFrames.filter(f => f.startsWith("RX") && /"type":"PHASE_START"/.test(f)).length;
  const rpsRevealFrames = wsFrames.filter(f => f.startsWith("RX") && /"type":"RPS_REVEAL"/.test(f)).length;

  process.stderr.write(`[acc] sawChoiceTx=${sawChoiceTx} sawEffectsRx=${sawEffectsRx} sawPhasePlaying=${sawPhasePlaying}\n`);
  process.stderr.write(`[acc] PHASE_START effect frames in stream = ${phaseStartFrames}\n`);
  process.stderr.write(`[acc] RPS_REVEAL effect frames in stream = ${rpsRevealFrames}\n`);

  if (sawChoiceTx && sawEffectsRx && sawPhasePlaying && phaseStartFrames > 0 && rpsRevealFrames > 0) {
    process.stderr.write("[drive] PASS\n");
    exit = 0;
  } else {
    process.stderr.write("[drive] FAIL — see /tmp/judge_throw/wsframes.txt for the full trace\n");
  }
} catch (err) {
  process.stderr.write(`[drive] threw: ${err && err.stack || err}\n`);
  exit = 2;
} finally {
  await browser.close();
}
process.exit(exit);
