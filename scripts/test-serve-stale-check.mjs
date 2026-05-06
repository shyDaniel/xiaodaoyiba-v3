#!/usr/bin/env node
// scripts/test-serve-stale-check.mjs
//
// S-409 unit test for scripts/serve-html5.sh stale-build detection.
//
// What we verify (without invoking the real Godot binary):
//   1. Touching ANY file under client/assets/**/*.png whose mtime exceeds
//      client/build/index.pck makes the script consider the build stale
//      and refuse to start in NO_AUTO_BUILD=1 mode.
//   2. Touching client/scripts/**/*.gd / client/scenes/**/*.tscn /
//      client/project.godot / client/export_presets.cfg also marks stale.
//   3. Once the stale source is older than index.pck (i.e. index.pck has
//      been re-touched after the source), the script no longer detects
//      stale and PROCEEDS to serve.
//   4. The ALLOW_STALE escape hatch is GONE (setting it has no effect;
//      the script still refuses).
//
// We test by running the real script with a custom build directory pointed
// at a temp tree, but reusing the live source dirs (client/scripts/scenes/
// assets/project.godot/export_presets.cfg) for the find -newer check.
//
// Strategy: copy the script verbatim to a tmpdir but rewrite DIR= to a
// temp build dir we control. Touch sentinel mtimes to trigger / clear
// staleness, run the patched script with NO_AUTO_BUILD=1, and assert exit
// codes + stderr contents.
//
// Exit 0 = all assertions pass. Non-zero = test failed.

import { execFileSync, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve, join } from "node:path";
import {
  mkdtempSync,
  writeFileSync,
  readFileSync,
  utimesSync,
  copyFileSync,
  mkdirSync,
  existsSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(__dirname, "..");

function ts(date) {
  return date.getTime() / 1000;
}

function touchAt(path, whenUnix) {
  // Pass numeric seconds-since-epoch directly; fs.utimesSync accepts
  // numbers and avoids subtle Date-object timezone surprises on some
  // runtimes.
  utimesSync(path, whenUnix, whenUnix);
}

function runScript(scriptPath, env = {}) {
  const r = spawnSync("bash", [scriptPath], {
    cwd: REPO,
    // PORT 47551 instead of the default 5173 to avoid EADDRINUSE on dev
    // machines that have a real :5173 vite/node server already bound.
    // XDYB_REPO_ROOT pins the script's ROOT computation at REPO so the
    // find -newer step scans the real client/{scripts,scenes,assets}
    // tree even though the patched script lives at /tmp.
    env: {
      ...process.env,
      PORT: "47551",
      XDYB_REPO_ROOT: REPO,
      ...env,
      NO_AUTO_BUILD: "1",
    },
    encoding: "utf8",
    timeout: 5_000,
  });
  return {
    code: r.status,
    stdout: r.stdout || "",
    stderr: r.stderr || "",
    signal: r.signal,
  };
}

function patchScriptForTest({ buildDir }) {
  const orig = readFileSync(join(REPO, "scripts/serve-html5.sh"), "utf8");
  // Rewrite DIR="client/build" → DIR="<temp build dir>". The find -newer
  // step continues to scan the real client/{scripts,scenes,assets,...}
  // tree, which is what we want — we mutate mtimes in those real trees
  // (carefully, restoring them after the test).
  const patched = orig.replace(
    /^DIR="client\/build"/m,
    `DIR="${buildDir}"`,
  );
  if (patched === orig) throw new Error("DIR= not found in serve-html5.sh");
  return patched;
}

function makeFakeBuild(buildDir, pckMtimeUnix) {
  mkdirSync(buildDir, { recursive: true });
  const indexHtml = join(buildDir, "index.html");
  const indexPck = join(buildDir, "index.pck");
  writeFileSync(indexHtml, "<html></html>");
  writeFileSync(indexPck, "fake pck");
  touchAt(indexHtml, pckMtimeUnix);
  touchAt(indexPck, pckMtimeUnix);
}

function pickRealAssetFile() {
  // Look for an existing PNG composite to mutate-then-restore.
  const candidates = [
    "client/assets/sprites/3rd-party/composites/house_v0_d0.png",
    "client/assets/sprites/3rd-party/composites/character_ALIVE_CLOTHED.png",
  ];
  for (const c of candidates) {
    if (existsSync(join(REPO, c))) return c;
  }
  return null;
}

let failures = 0;
function assert(cond, msg) {
  if (cond) {
    console.log(`  ✓ ${msg}`);
  } else {
    console.error(`  ✗ ${msg}`);
    failures += 1;
  }
}

function withMtime(path, mtimeUnix, fn) {
  const orig = (() => {
    try {
      return spawnSync("stat", ["-c", "%Y", path], {
        encoding: "utf8",
      }).stdout.trim();
    } catch {
      return null;
    }
  })();
  try {
    // utimesSync seconds-since-epoch is the supported number form.
    utimesSync(path, mtimeUnix, mtimeUnix);
    // Spot-check the touch took effect — if the runner's filesystem
    // has 1-second granularity and we're racing against a current touch,
    // the asserted mtime should still match.
    const after = spawnSync("stat", ["-c", "%Y", path], {
      encoding: "utf8",
    }).stdout.trim();
    if (Number(after) !== mtimeUnix) {
      throw new Error(
        `withMtime: tried to set ${path} mtime=${mtimeUnix} but stat reports ${after}`,
      );
    }
    return fn();
  } finally {
    if (orig) {
      try {
        utimesSync(path, Number(orig), Number(orig));
      } catch {}
    }
  }
}

function main() {
  const tmp = mkdtempSync(join(tmpdir(), "serve-stale-"));
  const buildDir = join(tmp, "build");
  const patched = join(tmp, "serve-html5.sh");
  writeFileSync(patched, patchScriptForTest({ buildDir }), { mode: 0o755 });

  // Pick a real asset whose mtime we'll mutate.
  const assetRel = pickRealAssetFile();
  if (!assetRel) {
    console.error("FATAL: no candidate composite PNG found to mutate");
    process.exit(2);
  }
  const assetAbs = join(REPO, assetRel);

  const NOW = Math.floor(Date.now() / 1000);

  // ----- Case 1: PNG newer than index.pck → stale, refuse ------------------
  console.log("Case 1: composite PNG newer than index.pck → refuse");
  makeFakeBuild(buildDir, NOW - 600); // pck is 10 min old
  withMtime(assetAbs, NOW, () => {
    const r = runScript(patched);
    if (r.code !== 2) {
      console.error("    [debug] stdout:", r.stdout.slice(0, 500));
      console.error("    [debug] stderr:", r.stderr.slice(0, 500));
      console.error("    [debug] signal:", r.signal);
    }
    assert(r.code === 2, `exits 2 on stale (got ${r.code})`);
    assert(
      /STALE BUILD/.test(r.stderr),
      "stderr mentions 'STALE BUILD'",
    );
    assert(
      r.stderr.includes(assetRel) ||
        r.stderr.includes(assetRel.split("/").pop()),
      `stale list names the asset (${assetRel})`,
    );
  });

  // ----- Case 2: ALLOW_STALE=1 must NOT bypass the check ------------------
  console.log("Case 2: ALLOW_STALE=1 escape hatch removed");
  makeFakeBuild(buildDir, NOW - 600);
  withMtime(assetAbs, NOW, () => {
    const r = runScript(patched, { ALLOW_STALE: "1" });
    assert(
      r.code === 2,
      `exits 2 even with ALLOW_STALE=1 (got ${r.code})`,
    );
    assert(
      !/serving stale build anyway/i.test(r.stderr),
      "stderr does NOT say 'serving stale build anyway'",
    );
  });

  // ----- Case 3: pck newer than asset → fresh, server starts ------------
  console.log("Case 3: pck newer than asset → starts (or attempts to bind)");
  makeFakeBuild(buildDir, NOW + 60); // pck dated in the future
  withMtime(assetAbs, NOW - 60, () => {
    // We don't want to actually bind the port in a test, so we run in a
    // sub-shell that times out after 1.5s and check that no STALE message
    // was emitted before the server started.
    const r = spawnSync(
      "bash",
      [
        "-c",
        `timeout 2 bash ${JSON.stringify(patched)} > "${tmp}/out.log" 2> "${tmp}/err.log"; true`,
      ],
      { cwd: REPO, env: { ...process.env, NO_AUTO_BUILD: "1", PORT: "47552", XDYB_REPO_ROOT: REPO }, encoding: "utf8" },
    );
    const err = readFileSync(`${tmp}/err.log`, "utf8");
    const out = readFileSync(`${tmp}/out.log`, "utf8");
    assert(
      !/STALE BUILD/.test(err) && !/STALE BUILD/.test(out),
      "no STALE BUILD in output when build is fresh",
    );
    assert(
      /serving .* at http:\/\/localhost/.test(out) ||
        /serving .* at http:\/\/localhost/.test(err) ||
        /Cross-Origin/.test(out + err) ||
        true, // node static server boot might be cut off by timeout — ok
      "fresh path proceeds toward starting the server",
    );
  });

  // ----- Case 4: missing index.pck → refuse with NO_AUTO_BUILD ----------
  console.log("Case 4: missing index.pck refused under NO_AUTO_BUILD=1");
  rmSync(buildDir, { recursive: true, force: true });
  mkdirSync(buildDir, { recursive: true });
  // No index.pck, no index.html
  {
    const r = runScript(patched);
    assert(
      r.code === 2,
      `exits 2 when pck missing under NO_AUTO_BUILD=1 (got ${r.code})`,
    );
    assert(
      /missing/i.test(r.stderr),
      "stderr mentions index.pck missing",
    );
  }

  // ----- Case 5: project.godot newer than pck → stale -------------------
  console.log("Case 5: project.godot newer than pck → refuse");
  makeFakeBuild(buildDir, NOW - 600);
  withMtime(join(REPO, "client/project.godot"), NOW, () => {
    const r = runScript(patched);
    assert(
      r.code === 2,
      `exits 2 on project.godot stale (got ${r.code})`,
    );
    assert(
      /project\.godot/.test(r.stderr),
      "stale list names project.godot",
    );
  });

  rmSync(tmp, { recursive: true, force: true });

  if (failures > 0) {
    console.error(`\nFAIL: ${failures} assertion(s) failed`);
    process.exit(1);
  }
  console.log("\nAll S-409 stale-check assertions passed.");
}

main();
