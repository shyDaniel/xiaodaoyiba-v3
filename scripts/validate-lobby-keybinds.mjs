// Drives a real headless chromium against http://localhost:5173, walks
// Landing → window.xdyb_landing_create() → press A 3× via keyboard
// → press S, captures WebSocket frames + screenshots.
// Exit 0 only if ≥3 room:addBot frames are observed AND room:start fires.

import { chromium } from "/home/hanyu/.cache/xdyb-playwright-core/1.59.1/package/index.mjs";
import fs from "node:fs";

const URL_ = process.env.URL || "http://localhost:5173/";
const HEADLESS_SHELL = process.env.HEADLESS_SHELL ||
  process.env.HOME + "/.cache/ms-playwright/chromium_headless_shell-1217/chrome-headless-shell-linux64/chrome-headless-shell";
const CHROME_LIBS = process.env.CHROME_LIBS ||
  process.env.HOME + "/.local/chrome-libs/usr/lib/x86_64-linux-gnu";
process.env.LD_LIBRARY_PATH = (process.env.LD_LIBRARY_PATH ? process.env.LD_LIBRARY_PATH + ":" : "") + CHROME_LIBS;

const SHOTS = "/tmp/lobby_keybind_check";
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
  page.on("console", m => process.stderr.write(`[chrome:${m.type()}] ${m.text()}\n`));
  page.on("pageerror", e => process.stderr.write(`[chrome:pageerror] ${e.message}\n`));
  page.on("websocket", ws => {
    process.stderr.write(`[ws] open ${ws.url()}\n`);
    ws.on("framereceived", f => { wsFrames.push("RX " + String(f.payload || "")); });
    ws.on("framesent",     f => { wsFrames.push("TX " + String(f.payload || "")); });
  });
  await page.goto(URL_, { waitUntil: "domcontentloaded", timeout: 30000 });
  await page.waitForFunction(() => {
    const c = document.querySelector("canvas");
    return c && c.width > 0 && c.height > 0;
  }, { timeout: 30000 });
  await page.waitForTimeout(8000); // settle Godot scene tree

  await page.waitForFunction(
    () => typeof window.xdyb_landing_create === "function",
    { timeout: 10000 }
  ).catch(() => {});
  const hasLandingBridge = await page.evaluate(() => typeof window.xdyb_landing_create === "function");
  process.stderr.write(`[drive] window.xdyb_landing_create available: ${hasLandingBridge}\n`);
  await page.screenshot({ path: SHOTS + "/01-landing.png", fullPage: false });

  if (!hasLandingBridge) {
    process.stderr.write("[drive] FAIL: landing bridge missing — Godot _ready never installed callbacks?\n");
    process.exit(2);
  }

  process.stderr.write("[drive] calling window.xdyb_landing_create()\n");
  await page.evaluate(() => window.xdyb_landing_create());
  await page.waitForTimeout(3500);
  await page.screenshot({ path: SHOTS + "/02-after-create.png", fullPage: false });

  const roomCreated = wsFrames.some(f => f.includes("room:created"));
  process.stderr.write(`[drive] room:created seen=${roomCreated}, frames so far=${wsFrames.length}\n`);

  await page.waitForFunction(
    () => typeof window.xdyb_lobby_addBot === "function",
    { timeout: 10000 }
  ).catch(() => {});
  const hasLobbyBridge = await page.evaluate(() => typeof window.xdyb_lobby_addBot === "function");
  process.stderr.write(`[drive] window.xdyb_lobby_addBot available: ${hasLobbyBridge}\n`);

  // Acceptance: press A 3× via page.keyboard. Our document-level
  // keydown shim (installed in Lobby.gd) routes them to the bridge.
  process.stderr.write("[drive] pressing A 3× via page.keyboard\n");
  for (let i = 0; i < 3; i++) {
    await page.keyboard.press("KeyA");
    await page.waitForTimeout(400);
  }
  await page.waitForTimeout(2000);
  await page.screenshot({ path: SHOTS + "/03-after-a3x-keyboard.png", fullPage: false });

  let addBotFrames = wsFrames.filter(f => f.includes("room:addBot")).length;
  process.stderr.write(`[drive] room:addBot frames after A×3 keyboard = ${addBotFrames}\n`);

  // Press S to start. Same path: document keydown → shim → bridge.
  process.stderr.write("[drive] pressing S via page.keyboard\n");
  await page.keyboard.press("KeyS");
  await page.waitForTimeout(2500);
  let startFrames = wsFrames.filter(f => f.includes("room:start")).length;
  process.stderr.write(`[drive] room:start frames after S keyboard = ${startFrames}\n`);
  await page.screenshot({ path: SHOTS + "/04-after-start.png", fullPage: false });

  fs.writeFileSync("/tmp/judge-wsframes.txt", wsFrames.join("\n") + "\n");
  process.stderr.write(`[drive] wrote ${wsFrames.length} frames to /tmp/judge-wsframes.txt\n`);

  if (addBotFrames >= 3 && startFrames >= 1) {
    process.stderr.write("[drive] PASS\n");
    exit = 0;
  } else {
    process.stderr.write(`[drive] FAIL: addBotFrames=${addBotFrames} (need≥3), startFrames=${startFrames} (need≥1)\n`);
  }
} finally {
  await browser.close();
}
process.exit(exit);
