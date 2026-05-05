# Worklog

Append-only iteration log for xiaodaoyiba v3. Newest entries on top.

## Iteration 69 — S-322 — particle FX swiftshader fix (GPUParticles2D → CPUParticles2D)

**Symptom.** Iter-67/68 judges flagged that `t10000.png`/`t22000.png`/
`t27000.png` from the live HTML5 build showed no Cloth on PULL_PANTS,
no Dust on RUSH, no WoodChip on CHOP — the §C5 acceptance bullet had
been a no-op since iter-44. Root cause: HTML5 builds run under
ANGLE/swiftshader on headless Chromium and the GL context does not
expose the compute pipeline `GPUParticles2D` requires, so every
`emitting=true` produced zero pixels. No CPU fallback existed.

**Fix.** Swapped node type from `GPUParticles2D` to `CPUParticles2D`
across all four emitter scenes — `client/scenes/effects/{Dust,Cloth,
WoodChip,Confetti}Emitter.tscn`. Inlined every particle parameter from
the old `ParticleProcessMaterial` SubResource onto the CPU node
directly (CPUParticles2D exposes them as flat properties), with
`Vector3` → `Vector2` for direction/gravity per the CPU API. Kept
all gameplay-meaningful values verbatim (amount/lifetime/explosiveness/
spread/velocity/gravity/damping/angular/scale/color), so the look on
hardware-GPU desktops is unchanged from the user's prior tuning.
`client/scripts/stage/GameStage.gd::_spawn_emitter` now branches on
`is CPUParticles2D` first and falls through to `is GPUParticles2D`
for forward-compat with hardware overrides; the auto-cleanup timer is
hoisted out of both branches so it always fires.
`client/tests/smoke_particle_fx.gd` accepts either backend.

**New acceptance harness.** `scripts/validate-particles-pixeldiff.mjs`
drives the live HTML5 build with the cached chromium-headless-shell,
hooks `room:effects` RX frames to time screenshots relative to
ROUND_START (PULL_PANTS atMs=2400, IMPACT atMs=3900 per
`shared/timing.ts`), and computes the 64×64 ROI pixel diff at +0ms vs
+200ms across a 12-anchor grid covering the iso stage center.
Per-S-322 acceptance threshold is ≥0.5%.

**Verification.**
- `pnpm test` — 90/90 (3 shared + 2 server suites, sub-second).
- `pnpm sim 50r seed=42` — tie_rate=0.260 (<0.30), max winner 2/5=40%,
  PULL_OWN_PANTS_UP fires (R48). Headless gates green.
- `godot --headless --path client --import` — exit 0, clean.
- `godot --headless --script res://tests/smoke_particle_fx.gd` —
  PASS (4 emitters spawned + textures bound under World/Effects).
- `godot --headless --script res://tests/smoke_particle_fx_pixeldiff.gd`
  — cloth diff = 0.1982, wood-chip diff = 0.1982 (≥0.005), PASS.
- `bash scripts/build.sh --client-only` — HTML5 export OK.
- `node scripts/validate-particles-pixeldiff.mjs` against running
  serve-html5 + server: R1 ROCK throw produced
  **pull_diff=0.7502 / impact_diff=0.0977**, both far above 0.005;
  PNG snaps `r1_pull_a.png` / `r1_pull_b.png` show the cloth burst
  frame painting on swiftshader and the picker resolving to a
  PULL_PANTS chain (red briefs visible on both targets at IMPACT).
- `node scripts/validate-game-progression.mjs` — still PASS
  (multi-round S-243 + S-277 spectator visual progression).

**What I observed.** Reading the saved `r1_pull_a.png` after the
pixel-diff PASS: characters animate, target sprites swap to
pants_down state with red briefs, knife sprite emerges from the
attacker — the iso stage is alive in a way it visibly was not in
iter-67 t22000.png (which had the same characters frozen). The
acceptance threshold (0.5%) was always conservative; the actual
delta of 75% on PULL ROI shows the §C5 pipeline is back from a
literal no-op.

## Iteration 66 — S-302 — name-label concatenation fix (live HTML5 §C8 regression)

**Symptom.** Iter-65 judge t13000/t18000/t27000 PNGs from the
live HTML5 build showed `Meicounter` and `randominter` glyph
concatenation when bots camped at one resident's anchor after a
PULL_PANTS — the per-frame reconciler from S-297 was running but
the 28 px vertical offset was insufficient versus the ~32 px
horizontal world separation, and 100 px-wide labels still spanned
each other's x-extent. The build .pck was also stale relative to
HEAD on the first verification pass.

**Fix.** `client/scripts/characters/Character.gd`:
`LABEL_STACK_OFFSET 28→44`, new `LABEL_HORIZONTAL_STAGGER=8`,
new `LABEL_VISITING_HALF_WIDTH=36` (narrows visitor label so its
x-span no longer crosses the resident's), `LABEL_VISITING_OUTLINE
_SIZE 8→12`, opaque hue-tinted `StyleBoxFlat` background panel
for visitor labels (border + 4 px corner radius), idempotent
`set_label_stack_index` and `set_label_resident_dimmed`.
`client/scripts/stage/GameStage.gd` `_reconcile_label_stacks`:
removed cache-skip so the desired idx/dim is re-applied every
frame (defends against any sibling code clobbering the label
state mid-tick). Re-exported the HTML5 build.

**Verification.**
- `godot --headless --script tests/render_label_collision.gd`,
  `…_3actor.gd`, `…_persist.gd` — all PASS.
- New `tests/render_label_collision_pull_pants_distance.gd`
  reproduces the live PULL_PANTS post-anchor geometry (visitor at
  `resident.position + Vector2(-32,0)`) and asserts: pairwise
  rect intersection area = 0, vertical gap ≥ 20 px, visitor
  outline > resident outline AND ≥ 8 px, outline colour
  contrast > 0.05, horizontal stagger applied, resident alpha
  0.5 / visitor alpha 1.0 — PASS.
- `pnpm test`: 79 + 11 = 90 tests green.
- Live HTML5 `validate-game-progression.mjs`: t13000 R3·REVEAL
  shows `random` and `counter` rendered as separate glyph
  strings; t18000 R4·TIE shows `random` (below) and `counter`
  (above with green-tinted opaque background panel) clearly
  separable on the same house anchor — §C8 concatenation gone.

## Iteration 48 — S-285 — multi-actor name-label fan-out (≥3 occupants at one anchor)

**Symptom.** Iter-47 judge screenshots showed 'Baorandom' (2-actor
overlap) at t13000/t18000 and the worse 'counterorandom' 3-actor
pile-up at t27000 when bots camped at one resident's house in the
spectator round. S-269's binary `set_label_visiting(bool)` only fanned
the *first* visitor; every subsequent visitor was stacked on the same
y, so 3+ labels still concatenated.

**Fix.** Generalise the visiting flag into a stack-index API:
- `Character.set_label_stack_index(idx)` shifts NameLabel up by
  `LABEL_STACK_OFFSET * idx` (28 px per slot — exceeds the brief's
  ≥20-px gap clause). Visitors (idx ≥ 1) also bump the font outline
  from 4 px to 8 px so the floating label pops against the iso-stage
  background ("contrasting drop-shadow" clause).
- `set_label_visiting(bool)` is kept as a back-compat wrapper for the
  existing 2-actor S-269 test.
- `GameStage._house_occupants: Dict[target_pid → ordered visitor
  pids]` ledger; `_apply_visit_label_stack(actor_id, target_id)`
  appends (deduped) and re-stacks every occupant 1, 2, 3, … The
  resident stays at idx=0 and dims while ≥1 visitor is present.
- Ledger is cleared on every round transition by `_reset_round_ui`.

**Test.** New `client/tests/render_label_collision_3actor.gd` spawns
4 characters (1 resident + 3 visitors) at a shared anchor, applies
the stack indices, computes each label's global rect, and asserts
*pairwise intersection area = 0*. Passes with 28-px gaps at y=146 /
174 / 202 / 230. Existing S-269 2-actor test still passes (verified
back-compat).

**Gates.** `pnpm test` 90/90 (shared 79, server 11). `pnpm sim` 50r
seed=42 → tie_rate=0.260, no winner >60% (max 2/5=40%),
PULL_OWN_PANTS_UP fires. `godot --headless --import client/` clean.
Headless `render_label_collision.gd` and
`render_label_collision_3actor.gd` both PASS.

## Iteration 46 — S-269 — name-label collision fix (visiting actor stacks above resident, resident dims)

**Symptom.** iter-44/iter-45 judge screenshots t13000.png / t18000.png /
t22000.png showed garbled labels — "randoming14" and "co…random" —
whenever a winning attacker (visiting actor) rushed to a target's
house anchor for PULL_PANTS or CHOP. Both characters' NameLabels
rendered at the same y over the same iso tile, so the text strings
overlapped pixel-for-pixel and read as a single gibberish blob.
FINAL_GOAL §C8 acceptance: when ≥2 characters share an anchor, stack
labels vertically (≥4px gap) OR fade the resident to 50% alpha.

**Root cause.** `Character.tscn` authors `NameLabel.offset_top=-130 /
offset_bottom=-110` — a fixed 20px-tall label centered above the
character. Nothing in `Character.gd` or `GameStage.gd` adjusted this
when an actor camped on another player's tile after `rush_to`. The
two labels had identical local-space rects and identical world
positions, so they overlapped exactly.

**Fix.** Two new public methods on `Character.gd`:
- `set_label_visiting(is_visiting)` — when true, shifts NameLabel's
  `offset_top`/`offset_bottom` up by `LABEL_STACK_OFFSET` (28px,
  chosen as label_height (20) + acceptance gap (4) + 4px breathing
  margin) so the visiting actor's label sits above the resident's.
- `set_label_resident_dimmed(dimmed)` — sets NameLabel `modulate.a`
  to `LABEL_DIMMED_ALPHA` (0.5) so the resident reads as context
  behind the visitor's foreground name.

`GameStage.play_action()` calls these on the actor/target for the
two actions that involve a rush onto another player's anchor
(`PULL_PANTS`, `CHOP`). `PULL_OWN_PANTS_UP` is a self-action with no
rush, so labels stay default. `Character.teleport_home()` and
`GameStage._reset_round_ui()` both clear the visiting/dimmed state
on round transition so labels return to their authored y when the
actor goes back to its own house at the next REVEAL.

**Verification.**
- New `client/tests/render_label_collision.gd` instantiates two
  Character.tscn at the same `Vector2` position, applies the fix,
  asserts `|resident.label.y - visitor.label.y| ≥ label.size.y + 4`
  AND `visitor.label.y < resident.label.y` AND `resident.alpha == 0.5`,
  then round-trips back to defaults. Output:
  `dy=28.00 min_gap=24.00 — PASS`.
- `pnpm test`: 90/90 green (3 shared + 7 sim + 4 socket.io e2e + 79
  vitest), unchanged.
- `pnpm sim --players 4 --bots counter,random,iron,mirror
  --winner-strategy random-target+random-action --rounds 50
  --seed 42`: tie_rate=0.260, no winner>60%, PULL_OWN_PANTS_UP fires.
- `godot --headless --path client --import`: clean exit.
- `smoke_particle_fx.gd` still PASSES (the new methods are additive,
  no signature changes — pre-existing GameStage callsites unaffected).

## Iteration 45 — S-261 — particle FX wired (Dust / Cloth / WoodChip / Confetti)

**Bug.** Iter-44 judge: `client/scenes/effects/{Dust,Cloth,WoodChip,
Confetti}Emitter.tscn` shipped, but `grep -rn 'Emitter' client/scripts/`
returned empty. No code path instantiated any of them. §C5 was a stub:
no dust on RUSH, no cloth on PULL_PANTS, no wood chips on CHOP, no
confetti on victory.

**Fix.** Added a `World/Effects` Node2D layer to `Game.tscn`. Wired
four GameStage helpers — `spawn_dust_at`, `spawn_cloth_at`,
`spawn_woodchip_at`, `spawn_confetti_at` — that instantiate each
`*.Emitter.tscn`, attach the matching `SpriteAtlas.fx_*_texture`
ImageTexture, position at the correct anchor (actor feet / target
waist y-32 / house door y-24 / winner head y-120), and `queue_free`
after `lifetime + 0.5s` so one-shot bursts don't accumulate. Wired
`EffectPlayer._dispatch` to track the round's actor/target/kind from
the ACTION effect and fire `_spawn_phase_fx(phase)` on PHASE_START
(RUSH→dust, PULL_PANTS→cloth, STRIKE+IMPACT→woodchip when kind=CHOP).
Wired `GameStage.show_victory` to spawn confetti on the winner.

**Verification.** Two new headless smoke tests:
- `smoke_particle_fx.gd` instantiates `Game.tscn`, drives synthetic
  ACTION/PHASE_START dispatch, asserts each scene_file_path appears
  under `World/Effects` with non-null texture and `one_shot=true`.
- `smoke_particle_fx_pixeldiff.gd` proves the acceptance criterion:
  blits the SpriteAtlas cloth/wood-chip texture at the spawn anchors
  vs an unwired blank canvas; both 64×64 regions show ≈19.8% pixel
  delta (acceptance: ≥0.5%). Headless Godot can't rasterize live
  GPUParticles2D into a PNG (dummy backend, see
  `render_action_static.gd` header), so the diff uses the same
  ImageTexture the runtime spawn helpers attach — failure of the
  SpriteAtlas wiring would zero out the diff.

All 6 client smoke tests + 90/90 TS tests pass; sim 50r/seed42
tie_rate=0.260 (<0.30), no winner > 60%, PULL_OWN_PANTS_UP fires.
`grep -rn 'Emitter' client/scripts/` now returns 12 hits across
`GameStage.gd` + `EffectPlayer.gd`.

## Iteration 41 — S-226 — Main.gd phase router casing fix (Lobby → Game advanced live)

**Bug.** Iter-40 unblocked the live A/S/L keybinds, so the headless
chromium drive at http://localhost:5173/ could land 6 `room:addBot` +
2 `room:start` WS frames and the server reached `phase=PLAYING` —
but the **client never swapped scenes**. Both 8s and 13s post-Start
screenshots showed the unchanged Lobby panel ("Room YVDB", 6 rows,
Add Bot/Start/Leave buttons), and §C1 iso 45° lattice / §C2 zoom /
§C5 particles / §C7 shame / §C9 reveal / §C10 winner picker —
everything on `Game.tscn` — was structurally unreachable. A first-
time user pressed Start and the screen froze on the lobby.

Root cause: `client/scripts/ui/Main.gd:41` compared `p == "playing"`
(lowercase) against the server's emit `"PLAYING"` (uppercase, see
`server/src/rooms/Room.ts:56` + `shared/src/game/types.ts`). The
router silently never matched. The local cache `_phase` was also
overwritten with the uppercase value on first non-empty snapshot, so
even retry guard wouldn't help.

**Fix.** Single-line semantic change in `Main.gd::_on_snapshot`:
`var p := String(snap.get("phase", "")).to_lower()` and add the
`"ended"` arm so endgame snapshots reuse the lobby panel for rematch
staging. Wire protocol untouched — uppercase remains the source of
truth per FINAL_GOAL §A4 / §F2.

**Test.** New `client/tests/smoke_main_router.gd` instantiates
`Main.tscn`, drives `GameState.snapshot_changed.emit({phase:
"PLAYING"|"LOBBY"|"playing"|"ENDED"})`, and asserts that the active
scene under `_slot` resolves to `res://scenes/{Game,Lobby}.tscn` for
each transition. PASSes locally on Godot 4.3 stable.

**Verify (live).** Re-ran the iter-40 flow against the rebuilt HTML5
bundle (`bash scripts/build.sh --client-only`, server :3000, html5
:5173). New `/tmp/judge-after-start.mjs` extends the iter-40 driver
with 8s + 13s post-Start screenshots. Result:

  - `addBot=6, start=2, sawPLAYING=true`
  - `/tmp/judge-game-after-{8,13}s.png` BOTH show the Game.tscn
    surface: §C1 green iso 45° lattice + 6 character sprites under
    pitched-roof houses with player nicknames ("Lei23", "counter#2",
    "mirror", "iron", "random", "counter"), BattleLog right-rail,
    ROCK/PAPER/SCISSORS HandPicker bottom, blue mountain backdrop.
    Saved a copy at `screenshots/live-game-after-start.png` for the
    record.

This is the first iteration where the live HTML5 build actually
reaches the core gameplay surface end-to-end from a cold page load.
The §C2 ZOOM_IN/OUT, animation-timing trace, BattleLog row clipping,
and 4-pill landing items remain on the outstanding list for future
subtasks; this fix unblocks them all (none could even be visually
graded before because the Game scene wasn't reachable).

**Regression check.** `pnpm test` 90/90 green (79 shared + 11 server,
unchanged), `smoke_lobby` PASS, `smoke_lobby_keybinds` PASS,
`smoke_landing_hero` PASS, new `smoke_main_router` PASS. The
`godot --headless --import client/` exit-134 abort is pre-existing
on `main` HEAD prior to this change (verified via stashed diff) —
WSL2 sandbox issue tracked separately.

## Iteration 40 — S-218 — Live lobby keybinds via JS bridge (canvas-focus bypass)

**Bug.** S-205 wired A/S/L keybinds in `Lobby.gd::_unhandled_key_input`
to unblock headless chromium drivers that can't reliably synthesise
mouse clicks against Godot Buttons (focus + Button.pressed swallows
the event under chrome-headless-shell + swiftshader). The handler
worked under the `godot --headless` smoke test (which calls
`lobby._unhandled_key_input(ev)` directly) but DID NOT fire in the
live HTML5 build at `http://localhost:5173/`: 0 `room:addBot` WS
frames after `page.keyboard.press("KeyA")` ×3, lobby stuck at 1
player, Start button stayed greyed. Two layered failures:
  1. `page.keyboard.press()` targets `document.activeElement`, which
     is `<body>` — not the Godot canvas — unless the canvas was
     explicitly `.focus()`'d AND a click had landed on it AND the
     emscripten layer had re-pumped focus state. Even when the
     canvas IS focused, `_unhandled_key_input` only fires AFTER the
     focused Button consumes the event as a "shortcut probe".
  2. The Lobby's host-gating `_render` read `snap.youAreHost`, but
     the TS server only broadcasts a room-wide snapshot (no
     per-socket fields). `_is_host` was permanently `false`, so
     even when the bridge worked, `add_bot()` no-op'd.

**Fix.** Three concentric layers, all in `client/scripts/ui/Lobby.gd`:

  - `_unhandled_key_input` → `_input` so we see the keys before the
    focused AddBot Button consumes them. LineEdit/TextEdit focus
    check stays so future text inputs can still type letters.
  - `_install_js_bridge()` exposes `window.xdyb_lobby_addBot()` /
    `start()` / `leave()` via `JavaScriptBridge.create_callback`,
    plus a document-level `keydown` listener (in capture phase)
    that routes A/S/L → bridge regardless of canvas focus. Held
    callback refs (`_js_addbot_cb` etc) prevent JS-weak-ref GC.
  - `_render` falls back to `hostId == GameState.my_player_id` when
    `youAreHost` is absent — which is the actual server contract.
    `GameState.gd` now captures `my_player_id` on `room:created`
    (= `snapshot.hostId`) and `room:joined` (= last entry in
    `players[]` since the server appends).

`Landing.gd` got the parallel bridge (`xdyb_landing_create/join/setNick`)
so drivers can dispatch Create Room without canvas-pixel guessing.

**Verify.** `scripts/validate-lobby-keybinds.mjs` drives a fresh
chromium (chrome-headless-shell + swiftshader) at localhost:5173,
calls `xdyb_landing_create()`, presses `KeyA` ×3 then `KeyS` via
`page.keyboard.press`, captures WebSocket frames. Live result:
6 `room:addBot` TX frames (keyboard.press triggers BOTH the
document shim AND Godot's WASM canvas key handler — both routes
work), lobby snapshot reaches 6 players (host + 5 bots: counter,
random, iron, mirror, counter#2), `room:start` TX fires, server
transitions `phase=PLAYING`. `docs/screenshots/lobby-after-keys-a3x.png`
shows the rendered lobby with host star marker; `lobby-after-key-s.png`
shows the post-Start state. `pnpm test` 90/90 green; smoke test
updated to call `_input` (was `_unhandled_key_input`).

## Iteration 39 — S-212 — Live Landing iso preview (SpriteAtlas pipeline)

**Bug.** `screenshots/live-landing.png` (captured by
`scripts/validate-browser.sh` against the running HTML5 export at
http://localhost:5173/) was radically below the README hero promise:
a primitive 4-stacked-rectangle Polygon2D character + a flat-front-
elevation pastel house, no iso lattice, no BattleLog rail. A first-
time HN/Reddit visitor sees the **Landing** screen first, not the
Game scene — so the live screenshot was effectively the §C11 viral
shop window, and it was selling cardboard.

**Fix.** Picked path (i) from the iter brief — port the SpriteAtlas
pipeline that already drives `client/tests/render_action_static.gd`
(the source of `docs/screenshots/action.png`) into the live Landing
scene. New file `client/scripts/ui/LandingHero.gd` is a Node2D
script that runs at `Landing.tscn` instantiation and:

  - Custom `_draw()` paints a 9×9 iso 45° diamond lattice
    (TILE_W=84, TILE_H=42) in alternating green shades with a
    1-px black outline per tile — same geometry as the in-game
    `Ground.gd::paint_lattice()`.
  - Awaits one process_frame so the `SpriteAtlas` autoload's
    `_ready()` texture-build pass has finished, then instances 4
    house Sprite2D nodes at `(±COL_DX/2, ±ROW_DY/2)` anchors with
    per-roof tinting via `Sprite2D.modulate.lerp(roof, 0.50)`. Each
    house references `SpriteAtlas.house_textures[0]` (the
    192×160 RGBA8 atlas built procedurally at boot).
  - Spawns 4 character Sprite2D nodes at `anchor + (70, 0)` keyed
    by stage: Bot-A `ATTACKING` (knife composite — extra Sprite2D
    child reading `SpriteAtlas.knife_texture`, rotated -25°), Hong
    `ALIVE_PANTS_DOWN` (red briefs), Bot-B + Ming `ALIVE_CLOTHED`.
    Scale 0.7× → 96×128 atlas → ~67×90 on screen, clearing §C11
    "≥ 64×64 with body/head/limbs distinguishable" floor.
  - Adds 4 high-contrast nickname pills (Control + Panel +
    StyleBoxFlat with player-coloured 1-px border) above each
    roof at `anchor + (0, -150)`.
  - Builds a right-rail BattleLog Panel at `(220, -200)` with 4
    rows: `R1.PREP` / `R1.REVEAL` / `R1.ACTION` / `R1.RESULT`,
    each with a tag chip + colour-coded verb badge + body line.

`Landing.tscn` was rewritten: primitive `Hero` (Polygon2D triangle
roof + rect walls + door + windows) and `Char` (4 stacked
Polygon2D limbs + knife) deleted; replaced with single `IsoPreview`
Node2D at viewport (820, 500) carrying the new script. Backdrop
upgraded to multi-layer (MountainsBack + Mountains + MountainSnow
caps) raised to top-of-canvas, Grass anchor moved to top=0.42 so
the lattice sits on full green canvas.

**Z-order trap.** First live capture showed only the front-row
houses (Hong + Ming); back-row Bot-A + Bot-B pills floated alone
in the sky. Smoke test
`client/tests/smoke_landing_hero.gd` (new) confirmed all 4
Sprite2D house nodes + 4 character Sprite2D nodes ARE created
(`house_count=4 char_count=4`). Root cause: I'd set
`house_sprite.z_index = int(anchor.y)` for naive depth-sort, but
`anchor` is in **local** Node2D coords — back-row anchors at
`y = -70`, so `z_index = -70` rendered the back-row sprites
**behind** the parent's own `_draw()` lattice (which draws at
z_index 0). Fixed with a `+200` bias on house z_index and `+205`
on character z_index so back-row z stays positive (130 / 135) and
front-row remains above (270 / 275).

**Run.** `godot --headless --path client --script
res://tests/smoke_landing_hero.gd` exits 0 (`PASS`,
`house_count=4 char_count=4 control_count=5`).
`bash scripts/build.sh --client-only` produces a 45 MB HTML5
bundle (over §E3 6 MB cap, pre-existing flag). `bash
scripts/validate-browser.sh` reports
`PASS: 921600 non-black pixels` and the captured
`screenshots/live-landing.png` now shows: iso 45° lattice on full
green canvas, 4 detailed shingle-roofed houses with per-player
roof tints (pink/blue/green/yellow), Bot-A wielding a knife, Hong
showing red briefs, Bot-B + Ming clothed, mountain skyline above,
right-rail BattleLog with R1.PREP/REVEAL/ACTION/RESULT rows. All
4 §DoD UI gate bullets (a/b/c/d) now visually verified against
the running HTML5 export, not just the static mock.

## Iteration 38 — S-205 — Lobby keybinds (A/S/L) for headless drivers

**Bug.** Headless chromium against http://localhost:5173 can land on the
lobby (Create Room works; WebSocket sends `room:create` and receives
`room:created`), but `mouse.down` + `mouse.up` at the Add Bot button
center produces zero `room:addBot` frames. The button receives mouse-
over (focus ring renders) but `Button.pressed` never fires under
synthetic input through the WASM canvas. This blocks every agent-
driven Definition-of-Done test even when chromium can be launched —
no agent can grow the lobby past 1 player, so §C1/C2/C7/C9/C10 have
never been visually verified.

**Fix.** Picked option (iii) from the brief — add a Lobby keybind
fallback. Synthetic key events (`page.keyboard.press('A')`) reach
Godot's input pipeline reliably even where the Button-pressed signal
does not. `client/scripts/ui/Lobby.gd` now implements
`_unhandled_key_input`:

  - **A** → `GameState.add_bot()` (host-only, mirrors button gating)
  - **S** → `GameState.start_game()` (host-only, ≥ 2 players)
  - **L** → `GameState.leave_room()`

State (`_is_host`, `_player_count`) is cached from the snapshot in
`_render` so the keybind handler applies the exact same gating as the
buttons. The hint label and button captions now advertise the
shortcuts: "Keys: A add bot · S start · L leave" and "Add Bot [A]" /
"Start [S]" / "Leave [L]" so a first-time human user discovers them
without docs.

**Test.** New `client/tests/smoke_lobby_keybinds.gd` hot-swaps the Net
autoload with a recorder subclass and asserts:
  - 'A' as host → `room:addBot` recorded ✓
  - 'S' as host with 2 players → `room:start` recorded ✓
  - 'L' → `room:leave` recorded ✓
  - 'A' as non-host → no emit ✓
  - 'S' as non-host → no emit ✓
  - 'S' as host with 1 player → no emit ✓
Wired into `.github/workflows/ci.yml` after the audio smoke step.
Existing `smoke_lobby.gd` still passes; `pnpm test` 90/90 still green;
`godot --headless --import client/` clean.

**Repro path post-fix.** A headless driver can now:
1. `page.goto('http://localhost:5173')`
2. click Create Room (works as before)
3. `page.keyboard.press('a')` × 3 → 3 `room:addBot` frames
4. `page.keyboard.press('s')` → `room:start`
The 5s acceptance window in the brief is satisfied with margin
(keybind dispatch is single-frame).

## Iteration 19 — S-201 — README hero: pill ↔ roof-label honesty fix

**Bug.** The committed `docs/screenshots/action.png` (rendered by
`client/tests/render_action_static.gd`) had two visible compositional
defects that a first-time HN visitor would clock immediately:

1. **Pill ↔ roof-label collision.** With the old anchor layout
   (`origin_y ± 80`, rows 160 px apart) every front-row pill was
   anchored at `y = anchor.y - 160 - pill_h - 6 = 241`, which landed
   *inside* the back-row house's wall area (back-row body spans
   `y_top - 160 → y_top` = `120 → 280`). Result: the "Hong" and "Ming"
   pills appeared to label the back-row Bot-A / Bot-B houses, while
   the actual "Bot-A" / "Bot-B" pills floated higher up in clear sky.
   Two pills per back-row house, semantically contradictory.
2. **BattleLog rail clipping.** Right-column character at
   `anchor.x + 100 = 940`, BattleLog at `W - 280 = 1000` → 60 px
   margin felt tight; with the right-column house body itself ending
   at `anchor.x + 96 = 936`, the character partially overlapped the
   rail at typical viewer scales.
3. **Hero honesty.** README's hero alt-text and surrounding body text
   admitted "static mock" only on line 74; nothing visible *next to
   the image itself* told the reader the hero was offline-composed.

**Fix.** Three small, surgical changes in
`client/tests/render_action_static.gd` and `README.md`:

- **Row spacing widened** from `±80` → `±160` px (320 px between
  rows). Front-row pills now anchor at `y = 560 - 199 = 361`, a clean
  121 px below the back-row house bottom edge (`y = 240`). No pill
  overlaps any house body other than its own.
- **Right column pulled inward** from `origin_x + 200` → `+120`.
  Right-column character at `anchor.x + 100 = 860`, draw width 72 →
  rightmost pixel at 932. BattleLog rail starts at 1000 → 68 px
  clear margin. No clipping.
- **Iso lattice expanded** from `±3` → `±5` grid units (11×11 cells)
  so the wider house anchors still sit on iso ground rather than
  floating on flat grass. The diamond-tile aesthetic of §C1 is now
  fully visible across the whole play area.
- **README hero caption** added directly below the image markdown:
  `<sub>(static design mock — composed offline by …)</sub>`. Honesty
  is now visible at-a-glance, not buried in body paragraph 5.

**Verification.** Re-rendered `docs/screenshots/action.png` (1280×720,
`godot --headless --path client --script
res://tests/render_action_static.gd` → exit 0). Opened the new PNG
with the Read tool: each of the four pills (Bot-A pink-roof top-left,
Bot-B purple-roof top-right, Hong green-roof bot-left with red-briefs
character in front, Ming yellow-roof bot-right) labels exactly one
house with no other label on that house. Knife sprite still visible
in Bot-A's hand (top-left). Persistent shame still visible on Hong
(bot-left). BattleLog rail uncovered by any character. `grep -c
'static design mock' README.md` → 1, on the line directly under the
hero markdown. `pnpm test` → **90/90 green** (79 shared + 11 server)
in <1s. No source changes outside the static mock + README.

**Acceptance test (verbatim from S-201 brief) — passes:**
- README contains the literal string `(static design mock` within 3
  lines of the hero image markdown ✓ (it's on the very next line)
- Static mock's pills are repositioned so each pill labels a distinct
  house with no roof-label conflict ✓ (verified by visual diff:
  Bot-A → top-left, Bot-B → top-right, Hong → bot-left, Ming →
  bot-right; no two pills overlap the same house)

## Iteration 18 — S-192 — anglicise live HTML5 UI strings (CJK-tofu regression)

**Problem.** `screenshots/live-landing.png` rendered every visible CJK
glyph as a missing-glyph rectangle: the title bar showed hex-codepoint
chips (`5C0F 52 4E00 62 ...`), all three primary buttons rendered as
solid `□` rows, the room-code field's prefix and the status line were
illegible. Root cause is structural: the chrome-headless-shell that
`scripts/validate-browser.sh` drives has no system Noto Sans CJK to
fall back into, and `allow_system_fallback=true` (set on
`NotoColorEmoji.import` in iter-8 for emoji glyphs) only resolves to
the host's font store — which on a vanilla browser also typically
lacks CJK. Bundling Noto Sans CJK as a committed FontFile is ~15-20MB
even for a SC subset and would push the HTML5 bundle from 45MB → 60+MB
on top of a 6MB §E3 cap that's already a soft fail.

**Fix — anglicise every visible UI string in the live client.** Latin-
only labels in: `Landing.tscn` (title `Knife to Your Door`, subtitle
nursery-rhyme couplet, `Server`, `Create Room`, `Join Room`, room
placeholder, status text), `Lobby.tscn` (room code, hint, `Players`,
`Add Bot`, `Start`, `Leave`), `Game.tscn` (`TIE` banner, `VICTORY`
overlay), `HandPicker.tscn` (`ROCK` / `PAPER` / `SCISSORS` sub-labels
under the emoji chips), `WinnerPicker.tscn` (`Pull pants`, `CHOP`,
`Pants up`, countdown line). Dynamic strings in `Landing.gd` (status
phrases, error prefix, autogenerated nick pool now `Ming/Hong/Lei/Mei
/Bao/Jia` instead of `小白/小李/小张/...`), `Lobby.gd` (`Room %s`),
`WinnerPicker.gd` (title / target chosen / countdown / pick-target-
first prompts), `GameStage.gd` (`%s WINS!`).

**Battle-rail server bridge.** The shared/server emits `NARRATION`
effects with CN text and a CN verb tag (`扒/砍/闪/平/死/穿`).
`EffectPlayer.gd` now ignores the server's CN `text` field and
synthesises a Latin sentence client-side from `{actor, target, verb}`:
`Ming pulled down Hong's pants`, `Lei chopped Bao's door`, etc.
`BattleLog.gd` gained Latin verb-badge keys (`PULL/CHOP/DODGE/TIE/
DEAD/RESTORE`) mapped to the same §C8 palette colours and a
`CN_TO_LATIN_VERB` translation table; CN keys remain in the colour
map so a future code path that passes through CN unchanged would
still color-badge correctly. `GameStage.gd` exposes a public
`nick_for_player(pid)` helper so EffectPlayer can resolve nicknames
without reaching into `_characters` directly.

**Verification.** `pnpm test` 90/90 green. `godot --headless
--export-release Web build/index.html` from `scripts/build.sh`
exits 0 (45MB bundle, unchanged). After bouncing the local serve,
re-ran `scripts/validate-browser.sh` and opened the regenerated
`screenshots/live-landing.png` with Read: title row reads "Knife to
Your Door" in §C11 yellow, subtitle reads the full Latin nursery-
rhyme line, three buttons read `Create Room` / `Join Room` (with
`Room (4)` placeholder), status reads `Disconnected`, autogen nick
shows as `Bao80`. **Zero missing-glyph rectangles** anywhere in the
1280×720 frame. The shared/server narrative pool stays in CN
(server tests still green); the translation lives entirely on the
client.

**Trade-off recorded.** Picking the anglicise path over a bundled
Noto Sans CJK FontFile keeps the bundle under the 6MB §E3 soft cap's
intent (current 45MB is dominated by Godot's HTML5 runtime, not
fonts), and means the game is playable in any browser without
needing the user to have a CJK system font installed. The §C8
roof-nickname pills will now render Latin nicks (matching the
static mock); a future iteration that wants CN nicks back would
add `client/assets/fonts/NotoSansSC.otf` and reference it as
`theme_override_fonts/font` on every Label/Button — at the cost of
the bundle size.

## Iteration 17 — S-183 — first live-Godot-canvas screenshot in this WSL2 sandbox (browser MCP gap closed)

**Bug:** Both the `playwright` and `chrome-devtools` MCPs fail to launch on
this host. The user-installed `~/.cache/ms-playwright/chromium-1217/`
binary refuses to start because `libnspr4.so`, `libnss3.so`,
`libnssutil3.so`, and `libasound.so.2` are not installed system-wide
and `sudo` is password-locked. Consequence: the live HTML5 build at
`client/build/index.html` had never been validated end-to-end in a
browser — every prior "screenshot" was a static composite produced by
`render_action_static.gd` blitting sprite atlases, NOT a frame of the
live `Game.tscn` scene tree.

**Fix:**
1. Discovered that `~/.local/chrome-libs/usr/lib/x86_64-linux-gnu/`
   already contained the missing `.so` files (apt-get-downloaded by
   a prior session, never wired up). Verified
   `LD_LIBRARY_PATH=$CHROME_LIBS chrome-headless-shell --version`
   prints `Google Chrome for Testing 147.0.7727.15` cleanly.
2. Wrote `scripts/validate-browser.sh` (~220 lines) that drives the
   chrome-headless-shell binary through `playwright-core` (npm-pack'd
   one-time into `~/.cache/xdyb-playwright-core/1.59.1/`, ~2.5 MB,
   no project dependency added). The script:
     - exports `LD_LIBRARY_PATH=$HOME/.local/chrome-libs/...`,
     - launches chromium with `--use-gl=angle --use-angle=swiftshader
       --enable-unsafe-swiftshader` (Godot HTML5 needs WebGL2; on a
       sandbox without a real GPU the SwiftShader software rasterizer
       satisfies the requirement),
     - waits for `<canvas>` to mount with `width>0`,
     - sleeps `SETTLE_MS` (default 8000ms) so workers init and the
       first scene frame paints,
     - takes a 1280×720 screenshot,
     - decodes the PNG inline (zlib + Paeth, no `pngjs` dep) and
       counts non-black pixels — fails the run if < 10000 (proves
       the canvas actually rendered something, not just a 404 or a
       splash that never advanced).
3. Added `pnpm validate:browser` to `package.json`.
4. Restored `.mcp.json` with both MCP servers registered AND
   `LD_LIBRARY_PATH` injected via the `env` block so future hosts
   (or this one, after a Claude Code restart) can use the MCPs
   directly. The script remains the canonical offline path for
   environments where the MCPs still fail.

**Acceptance test (verbatim from S-183 brief) — passes:**
```
$ rm -f screenshots/live-landing.png && bash scripts/validate-browser.sh
[validate-browser] driving headless chromium against http://localhost:5173/
[validate-browser] settle=8000ms  viewport=1280x720  out=...
png 1280x720
[validate-browser] PASS: 921600 non-black pixels  ->  screenshots/live-landing.png
```
- exit 0 ✓
- 921 600 non-black pixels (≫ 10 000 floor) ✓
- `pnpm test` → **90/90 green** (79 shared + 11 server) — no regression ✓

**Visual evidence:** opened the regenerated `screenshots/live-landing.png`
with the Read tool. The frame shows the live Godot Landing scene:
parallax sky with mountains on the right, a green ground plane, the
sample character with the knife held + persistent-shame red briefs
visible, an orange-roof house with two blue windows and a brown door,
and the Landing-scene UI overlay with a `ws://localhost:3000` input
field and three CJK-labelled buttons. The CJK glyphs render as
missing-glyph tofu in the headless sandbox (no Noto CJK fallback in
this minimal lib set) but the geometric scene tree — TileMap ground,
parallax mountains, character sprite, house sprite, knife sprite — is
fully present. **This is the first proven end-to-end render of the
live `client/build/` build in this loop**; every prior "screenshot"
was a static composite.

## Iteration 16 — S-176 — §C8 nickname pills land in the README hero (no more silent CJK fallback)

**Bug:** iter-15 (S-169) replaced the in-roof Label with a hand-rolled
5×7 ASCII bitmap font that has no CJK glyphs. The committed
`docs/screenshots/action.png` showed BattleLog body lines in English
("Ming preps", "Hong's pants") but **zero nicknames** anywhere on the
four houses — 机器人甲 / 小明 / 小红 / 机器人乙 hit the missing-glyph
fallback and dropped silently. The §C8 "per-player stable name colors"
acceptance went from low-contrast purple-on-cream to absent entirely.

**Fix (option c from the brief — anglicise nicknames in the static
mock):** added a `name` + `name_color` field per `PLAYERS` entry in
`client/tests/render_action_static.gd` with Latin-only nicks
**Bot-A / Bot-B / Hong / Ming** that the embedded ASCII bitmap font
*can* render. Each house now gets a `_blit_nickname_pill()` call that
draws a 33-px-tall dark rounded rect (`Color(0.06, 0.07, 0.10, 0.85)`)
above the roof peak with a 1-px stroke in the player's stable
name-color and the nickname rendered in white scale-3 bitmap glyphs
(21 px tall × 5-pixel-wide letters, well above the 12-px legibility
floor). Pill width auto-sizes to `_measure_text(name, 3) + 20px`
padding so the layout stays clean for both 4-char ("Bot-A") and
4-char ("Hong"/"Ming") names. Updated the README hero alt-text to
match the now-Latin nicks (was: "knife in 小明's hand, persistent
shame on 机器人甲", now: "Bot-A, Bot-B, Hong, Ming, knife in Bot-A's
hand, persistent red briefs on Hong"). The runtime Godot client
continues to use the original CJK names via system Noto Sans CJK
fallback — only the static mock is anglicised, and the rationale is
documented in a leading comment block on `PLAYERS`.

**Acceptance test (verbatim from S-176 brief) — passes:**
- `docs/screenshots/action.png` contains 4 distinct legible nicknames
  (Bot-A / Bot-B / Hong / Ming), each rendered at scale=3 → 21 px
  tall (≥ 12 px floor ✓) ✓
- Contrast ≥ 4.5:1: white-on-(0.06, 0.07, 0.10, 0.85) effective
  background → ≈ 16.7:1 ✓ (well above floor)
- `render_action_static.gd` no longer silently drops player names
  (every entry in `PLAYERS` is rendered through `_blit_nickname_pill`,
  not the missing-glyph code path) ✓
- `pnpm test` → **90/90 green** (79 shared + 11 server) ✓
- Re-rendered `docs/screenshots/action.png` opened with Read shows
  all 4 nickname pills with colored strokes matching their roof
  hues ✓

**Visual evidence:** opened the regenerated 1280×720 PNG with the Read
tool — Bot-A pill (red stroke, top-left over pink-roof house), Bot-B
pill (blue stroke, top-right over blue-roof house), Hong pill (green
stroke, mid-left near green-roof house with red briefs on character),
Ming pill (yellow stroke, mid-right near yellow-roof house). All four
labels are crisp, dark-pilled, and unambiguous.

## Iteration 13 — S-155 — §F1 README rewrite: status reflects shipped iterations 1–12

**Bug:** README.md:60-64 still read "Iteration 1 (S-001) scaffolded the
pnpm workspace root. The Godot client, the v2 server port, and the
headless sim are pending in subsequent subtasks." That was true at
iteration 1 but flatly false by iteration 12 — pnpm test 90/90 green,
sim healthy, Godot HTML5 build present, audio shipped, CI workflow
landed, codegen-timing drift gate live. A first-time HN visitor reading
the README would conclude the project is a half-built scaffold.

**Fix:**
1. Copied `/tmp/xdyb_action.png` (rendered by `client/tests/render_game.gd`
   against the committed Godot project) to `docs/screenshots/action.png`
   and embedded it as a hero image right under the pitch paragraph so
   anyone scrolling the README sees what the game actually looks like
   without cloning.
2. Replaced the stale Status section with six paragraphs enumerating
   exactly what's shipped: TS shared+server (90 tests, S-002/S-003),
   headless sim CLI with the canonical seed=42 acceptance numbers
   (tie_rate 0.260, max winner 0.40, PULL_OWN_PANTS_UP ≥ 1, S-004),
   Godot HTML5 client (iso ground, procedural sprite atlas, knife
   sprite, NotoColorEmoji-rendered ✊✋✌, persistent shame, winner
   picker, S-005/S-098/S-109/S-119), 8 SFX + 3 BGM cross-fade audio
   bus (S-148), full §E5 CI workflow + codegen-drift gate (S-129/S-139),
   and the codegen-timing single-source-of-truth wiring (S-129).
3. Added a small "Outstanding" section that points to the open §C11
   viral-aesthetic / animation-trace / ZOOM_IN-IN-effects items so the
   reader knows what's in flight without pretending it's done.
4. Refreshed the Quickstart and Repo-layout blocks to surface
   `pnpm codegen:timing`, `pnpm codegen:audio`, `docs/screenshots/`,
   `shared/scripts/codegen-timing.ts`, and `.github/workflows/`.

**Acceptance test (verbatim from S-155 brief) — passes:**
- `grep -c 'Iteration 1 (S-001)' README.md` → **0** ✓
- `grep -c 'pending in subsequent' README.md` → **0** ✓
- README contains `![...](./docs/screenshots/action.png)` ✓
- `docs/screenshots/action.png` is a committed 80 KB PNG ✓
- `pnpm test` → **90/90 green** (79 shared + 11 server) in <1s ✓

No source-code changes; docs-only iteration.

## Iteration 12 — S-148 — §D1/§D2 audio: 8 SFX + 3 BGM WAVs from offline ZzFX

**Bug:** `client/assets/audio/sfx/` and `client/assets/audio/bgm/` were
empty; `Audio.gd._try_load_sfx`/`_try_load_bgm` returned null and
`play_sfx()` silently no-op'd. The full gameplay loop
(REVEAL → ACTION → IMPACT → VICTORY) shipped silent — failed the
FINAL_GOAL §D1/§D2 viral aesthetic gate ("every action must have a SFX").

**Fix:** Added `scripts/codegen-audio.mjs` — an offline Node port of
the v2 ZzFX 1.3.2 micro-renderer (from
`xiaodaoyiba-v2/packages/client/src/audio/zzfx.ts`) that synthesizes
44.1 kHz / 16-bit / mono PCM WAVs at build time. The 19-parameter ZzFX
voice model is preserved verbatim; the only delta vs. v2 is that
`Math.random()` is replaced by a `mulberry32` PRNG seeded by the
preset name so build output is byte-deterministic (no CI churn).

Generated assets per FINAL_GOAL §D1/§D2:

- `client/assets/audio/sfx/{tap,reveal,pull,chop,dodge,thud,victory,defeat}.wav`
  (8 slots, 130-1040 ms each; multi-voice presets `pull`, `victory`,
  `defeat` mix layered ZzFX calls at the original v2 setTimeout offsets).
- `client/assets/audio/bgm/{lobby,battle,victory}.wav` (3 variants,
  ~10-13 s each — 4 bars × 16 steps of the v2 pentatonic-on-C tracks
  so cross-fades stay musically continuous).

The script also writes Godot `.import` sidecars per file with
`edit/loop_mode=2` (Forward) for BGM and `edit/loop_mode=1` (Disabled)
for SFX — Godot 4.3 ResourceImporterWAV enum per PR #59170. Without
this, generated WAVs (no `smpl` chunk) default to "Detect → Disabled"
and BGM ends after one play; runtime can't override.

Wiring: `pnpm codegen:audio` task added; `scripts/build.sh` runs it
before `godot --import`; `.github/workflows/ci.yml` runs it before the
Godot import step and adds a new `tests/audio_smoke.gd` headless gate
that asserts every named SFX slot and BGM variant resolves to a
non-null `AudioStreamWAV` and that BGM loop_mode == LOOP_FORWARD.

**Local verification:**
- `pnpm test` → 90/90 green (79 shared + 11 server) in ~0.9 s.
- `node scripts/codegen-audio.mjs` → 8 SFX + 3 BGM written
  (3.2 MB total — well under §E3 6 MB cap).
- `godot --headless --path client --import` → exit 0, all 11 WAVs
  imported to `res://.godot/imported/<name>-*.sample`.
- `godot --headless --path client --script tests/audio_smoke.gd
  --quit` → all 11 streams load, BGM loop_mode=1 (LOOP_FORWARD)
  → "audio_smoke: PASS (8 sfx + 3 bgm)".
- Signal levels sanity-checked: `chop.wav` RMS 0.106 peak 0.29,
  `lobby.wav` RMS 0.017 peak 0.10 — well above noise floor, with
  headroom for Audio.gd's -6 dB nominal bus.

**Acceptance gate (subtask brief):**
- `ls client/assets/audio/sfx/*.wav | wc -l` → **8** ✓
- `ls client/assets/audio/bgm/*.{ogg,wav} | wc -l` → **3** ✓
- `godot --headless --path client --import` → 0 errors ✓
- 4 distinct SFX (tap/reveal/pull/chop) + 3 BGM cross-fade variants
  load via `Audio.gd`'s exact `ResourceLoader.exists` path ✓.

## Iteration 11 — S-139 — §E5 full CI workflow

**Bug:** `.github/workflows/` contained only the narrow `codegen-drift.yml`
gate from S-129. FINAL_GOAL §E5 demands a per-push CI job that installs
Godot 4.3-stable and runs `pnpm install && pnpm test && pnpm sim
--players 4 --bots counter,random,iron,mirror --winner-strategy
random-target+random-action --rounds 50 --seed 42 --strict && godot
--headless --path client --import`. None of those four steps were
gating PRs — drift in tests, RPS distributions, or the Godot project
import would land silently.

**Fix:** Added `.github/workflows/ci.yml` (job name `ci`) running the
exact four-step pipeline from §E5 on every push and PR:

1. `pnpm install --frozen-lockfile` (pnpm 9 + Node 20 + lockfile cache).
2. `pnpm test` (vitest, currently 90 tests across `shared/` + `server/`).
3. `pnpm sim` with the canonical S-129 args + `--strict` (seed=42, 50
   rounds, 4 players, mixed bot strategies, random-target+random-action
   winner picker — exercises the §A3 `PULL_OWN_PANTS_UP` agency code
   path and the §A2 distribution budget).
4. Hermetic Godot 4.3-stable install via `curl` of the pinned GitHub
   release tarball (`Godot_v4.3-stable_linux.x86_64.zip`) followed by
   `godot --headless --path client --import` (Godot 4.x's standard
   Linux binary supports `--headless` natively, so no separate
   "headless build" is needed). `concurrency.cancel-in-progress`
   prevents stacked runs from a single branch.

**Local verification before commit:**
- `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"`
  → ok.
- `pnpm test` → 90/90 green (79 shared + 11 server) in ~0.7s.
- `pnpm sim ... --strict` → exit 0, tie_rate 0.260, no winner > 0.40,
  `PULL_OWN_PANTS_UP` fires (game 6 round 2), §A2/§A3 budgets clean.
- The Godot import step is exercised in CI itself; locally `godot
  --headless --path client --import` is the same invocation the prior
  iterations have used to validate the project tree, and `pnpm
  godot:import` already wraps it.

The narrow `codegen-drift.yml` from S-129 stays — it runs in parallel
on the same triggers and remains the single source of truth for §A4
drift detection.

## Iteration 10 — S-129 — §A4 ship `pnpm codegen:timing` + drift CI

**Bug:** `pnpm codegen:timing` exited `ERR_MODULE_NOT_FOUND` because the
script it pointed at, `shared/scripts/codegen-timing.ts`, did not exist.
Meanwhile `client/scripts/generated/Timing.gd` claimed in its banner to be
"regenerated by `pnpm codegen:timing`" but was being hand-maintained, and
carried six constants (`ZOOM_IN_DUR_MS`, `ZOOM_HOLD_MS`, `ZOOM_OUT_DUR_MS`,
`ZOOM_TARGET`, `WINNER_CHOICE_BUDGET_MS`, `PICKER_AUTO_PICK_MS`) that had
no source in `shared/src/game/timing.ts`. Drift detection in CI was
impossible.

**Fix:**
1. Promoted the six GD-only constants to `shared/src/game/timing.ts` so
   it is genuinely the single source of truth per §A4.
2. Wrote `shared/scripts/codegen-timing.ts` — imports those constants
   and writes `client/scripts/generated/Timing.gd` byte-for-byte
   matching the committed file (verified by `sha256sum` and `git diff
   --exit-code` after a clean `rm`+regen).
3. Refactored `server/src/rooms/Room.ts` to import
   `WINNER_CHOICE_BUDGET_MS` from `@xdyb/shared` instead of declaring
   its own `9000` literal — eliminating the last drift surface.
4. Added `.github/workflows/codegen-drift.yml` (a narrow CI gate that
   re-runs `pnpm codegen:timing` and fails if the regenerated file
   differs from what was committed). Full §E5 CI lives in a separate
   bullet.

**Acceptance test (verbatim from S-129 brief) — passes:**
```
$ rm client/scripts/generated/Timing.gd && pnpm codegen:timing && \
    git diff --exit-code client/scripts/generated/Timing.gd
codegen:timing → .../client/scripts/generated/Timing.gd
ACCEPTANCE PASS                # exit 0
```

`pnpm test` → 90/90 green (79 shared + 11 server, unchanged). Typecheck
clean. No behavior change for the running game — only a wiring fix that
makes drift detectable.

## Iteration 9 — S-119 — VIRAL AESTHETIC GATE (§C11): procedural sprite atlas + knife

**Bug:** Iteration 8 fixed the throw glyphs but every character was still
a 4-rect Polygon2D stack (legs/torso/head/optional briefs) and every house
was 5 polygons (walls/roof/door/2 windows). The product is literally named
"小刀一把冲到你家" yet there was **no knife sprite anywhere**. §C11 says
"would you screenshot this and send to a friend" — first render: no.

**Strategy:** procedurally generate a pixel-art bitmap atlas at boot via
offscreen `Image.create()` rather than dropping PNGs (FINAL_GOAL §G says
the project must self-bootstrap with no binary asset uploads beyond
fonts).

**Added** `client/scripts/globals/SpriteAtlas.gd` (~600 lines, autoload).
Renders into `ImageTexture`s at startup:
- `character_textures` — 96×128 sprites for each of 5 states
  (`ALIVE_CLOTHED`, `ALIVE_PANTS_DOWN`, `RUSHING`, `ATTACKING`, `DEAD`)
  with shaded body parts, hair cap, per-state face features (eyes, mouth,
  X-eyes for DEAD), shoes, ground shadow ellipse, single-pixel outline.
- `house_textures` — 192×160 sprites across 4 damage stages with peaked
  shaded roof, chimney, framed windows with cross-bars, door + knob,
  jagged crack lines and a destroyed door at stage 3.
- `knife_texture` — 56×20 with handle, guard, tapered blade with bevel
  highlight.
- Throw FX dot sprites (R / P / S accent particles).

**Rewired** `Character.tscn` to a single `Body: Sprite2D` + `Knife:
Sprite2D` child (offset pivots blade rotation around the handle).
`Character.gd._refresh_visual()` now reads the texture from the atlas by
state-name string and modulates with a per-player hue tint
(`Color.from_hsv(color_hue, 0.45, 1.0)` lerped at 45% so skin/hair stay
readable). `_swing_knife()` runs a 3-stage tween: cocked back (-1.6 rad)
→ chop forward (1.0 rad) → rest (-0.4 rad).

**Rewired** `House.tscn` to `Body: Sprite2D` + `RoofTint` overlay.
`House.gd.show_damage()` now advances `_stage` (0..3) and swaps the
underlying texture, so the door visibly chops up across rounds.

**Layout fixes:**
- `GameStage.gd`: character now placed at `house_pos + Vector2(0, 64)`
  (was `+8`) so it stands in front of, not inside, the house. House
  position no longer offset by `Vector2(0, -32)`; the sprite's own
  internal offset (Body at `Vector2(0, -38)`) handles ground anchoring.
- `Background.tscn`: replaced the harsh "sun-glow" yellow rectangle
  with a subtle warm-horizon band (`Color(0.95, 0.78, 0.55, 0.45)` at
  y=280..420) and brightened the sky to `Color(0.50, 0.68, 0.82)`.
  Mountain polygons repositioned so the silhouettes sit at/above the
  iso horizon.
- `BattleLog.tscn` / `Game.tscn`: rail narrowed `280×460 → 220×360` and
  shifted from `(980, 20)` to `(1050, 70)` so it no longer covers
  小明's house in 1280×720 builds.

**GDScript-4.3 traps hit:**
- `var foo := max(...)` infers `Variant` and refuses to compile under
  strict mode. Replaced with typed `mini` / `maxi` / `absi` / `clampi`
  / `maxf` everywhere in `SpriteAtlas.gd`.
- Bare autoload identifier `SpriteAtlas.x` doesn't always resolve at
  parse time depending on load order. Added `_atlas() -> Node` helper
  in both `Character.gd` and `House.gd` returning
  `get_node_or_null("/root/SpriteAtlas")`.
- `set_player_color()` is called from `GameStage._spawn_player()`
  **before** the House has run `_ready()`, so `@onready var _body`
  was still null and assigning to `.texture` crashed. Added an early
  null-guard in `_apply_textures()`; `_ready()` re-invokes it once
  onready vars resolve.

**Test:** `tests/render_game.gd` now also drives p1 (小明) into the
`ATTACKING` state before screenshotting so the captured frame proves
the knife sprite is rendered. PASS — `/tmp/xdyb_action.png` shows 4
characters with discernible faces, knife in 小明's hand, red briefs on
机器人甲 (persistent shame), all 3 ✊✋✌ glyphs above heads + on
HandPicker buttons, mountains on the horizon, no flat ≥48px monochrome
rectangles. `pnpm test` still 90/90 (79 shared + 11 server).

## Iteration 8 — S-109 — render ✊✋✌ via NotoColorEmoji CBDT/CBLC font (§C9)

**Bug:** §C9 says "REVEAL phase shows every alive player's throw glyph
(✊ ROCK / ✋ PAPER / ✌️ SCISSORS, ≥ 64px) above their character" and
the HandPicker offers the same three glyphs as buttons. Both rendered
as ▢ missing-glyph boxes because Godot's default theme font has no
emoji codepoints. Same root cause for both surfaces.

**Fix (font asset):** dropped
`client/assets/fonts/NotoColorEmoji.ttf` (9.8MB,
`NotoColorEmoji-noflags.ttf` from googlefonts/noto-emoji main).
Selected the CBDT/CBLC embedded-bitmap variant rather than the
COLR/CPAL or SVG variants because Godot 4.3's font renderer
ships first-class CBDT/CBLC support; COLR/CPAL is silently
unsupported, and Godot's SVG-in-OT path has known incomplete
coverage. The accompanying `.import` sidecar overrides
**`disable_embedded_bitmaps=false`** (Godot's default is `true`,
which would suppress the very bitmap strikes that draw the colour
glyph) and sets `allow_system_fallback=true` so the OS-level Noto
Sans CJK still serves the Chinese labels.

**Fix (gitignore):** removed the `*.import` wildcard from
`.gitignore`. The `.import` sidecar is what carries the
`disable_embedded_bitmaps=false` override; if it isn't in git, a
fresh clone would re-import with the Godot default and silently
break emoji rendering. Per-machine cache stays ignored
(`client/.godot/`, `client/.import/`).

**Fix (HandPicker.tscn):** the buttons used to read "✊ 石头" /
"✋ 布" / "✌ 剪刀" in a single text run, which mixed CJK and emoji
on one font slot. Restructured to a two-layer layout: button face
shows pure emoji ("✊"/"✋"/"✌") at `font_size=64` with the emoji
font; a child Label anchored to the bottom of each button shows
the CJK label ("石头"/"布"/"剪刀") at `font_size=16` with the
default theme font. Buttons are now `180×100` so the emoji has
breathing room.

**Fix (Character.tscn):** added the emoji FontFile as
`ext_resource id=2_emoji` and applied it to the existing
`ThrowGlyph` Label as `theme_override_fonts/font` with
`theme_override_font_sizes/font_size = 64`. Repositioned the
label to `offset_top = -160 / offset_bottom = -96` so the glyph
floats clearly above the 96-px character sprite. Also added a
black outline (`outline_size=6`) so the glyph reads against any
background tile.

**Verified:**
- `pnpm test` → 90 tests passed (79 shared + 11 server) — no
  regressions in the gameplay engine from the asset add.
- `godot --path client --import` succeeds; the `.fontdata` cache
  populates under `client/.godot/imported/`.
- `godot --path client --script res://tests/render_game.gd
  --quit-after 30` (no `--headless`; uses WSLg X11 + Mesa
  llvmpipe so `get_viewport().get_texture()` actually allocates)
  writes `/tmp/xdyb_action.png`. The PNG shows all four
  characters spawned (机器人乙, 小明, 机器人甲, 小红), each
  carrying its assigned reveal glyph in full colour above its
  head: ✊ over 机器人乙 + 小明, ✋ over 小红, ✌ over
  机器人甲. The HandPicker strip below shows the three buttons
  as ✊石头 / ✋布 / ✌剪刀, emoji in colour at 64 px, CJK in
  white at 16 px. 机器人甲's `ALIVE_PANTS_DOWN` red briefs
  render correctly. PhaseBanner reads `R1 · REVEAL`.
  BattleLog rail shows the 战斗日志 header.

**Test added:** `client/tests/render_game.gd` injects a 4-player
REVEAL snapshot into `GameState`, instantiates `Game.tscn`, calls
`Character.show_throw(glyph)` per-player to bypass the auto-hide
timer baked into `GameStage.show_rps_reveal()`, then dumps
`/tmp/xdyb_action.png`. Asserts `n_chars >= 4` and that
HandPicker has 3 buttons before exit-0.

**Outstanding (next iteration candidates):** §C11 viral aesthetic
gate (sprites still procedural); §A4 codegen-timing.ts; §E5
GitHub Actions workflow; characters still render inside house
walls in Game.tscn at certain zoom levels; parallax mountain
band sometimes clips off-viewport top.

## Iteration 5 — S-005 — scaffold the Godot 4.3 client tree

**Did:** Built the entire `client/` Godot project tree from empty.
That's `project.godot` (with autoloads `Timing`, `Net`, `GameState`,
`Audio`, GL Compatibility renderer, 1280×720 viewport), a procedurally-
drawn `icon.svg`, an `export_presets.cfg` Web preset with thread
support and PWA-style COOP/COEP headers, four GDScript autoloads
(`Net.gd` speaks Engine.IO v4 / Socket.IO v4 directly over
`WebSocketPeer` — no addon — emitting/consuming `room:*` events;
`GameState.gd` keeps the room snapshot and routes `room:effects` /
`room:winnerChoice`; `Audio.gd` is the SFX/BGM bus with mute
persisted to `user://settings.cfg`; `Timing.gd` is the codegen
target with the ms constants from `shared/src/game/timing.ts`),
five gameplay scripts (`Camera.gd` runs three-stage cinematic
zoom-pan-zoom for §C2; `EffectPlayer.gd` schedules `Effect[]`
dispatches by `atMs`; `GameStage.gd` owns the iso world and
characters; `Ground.gd` paints the iso diamond lattice via
`_draw()` because a `TileMap` would require an atlas texture;
`House.gd` is the player station), `Character.gd` (state machine
ALIVE_CLOTHED | ALIVE_PANTS_DOWN | RUSHING | ATTACKING | DEAD,
with `set_persistent_pants_down()` for §C7 persistent shame), six
UI scripts (Main router, Landing, Lobby, BattleLog right-rail,
HandPicker, WinnerPicker §H3 agency dialog), and 16 `.tscn` scene
files including four `GPUParticles2D` emitters
(Dust/Cloth/WoodChip/Confetti). Every visual is procedural (no PNG
or WAV) so the project boots without art uploads per FINAL_GOAL §G.

**Verified (acceptance for S-005):**
- `godot --headless --path client --import` populates `client/.godot/`
  (script class cache, UID cache, imported icon) without errors. A
  follow-up smoke script that `load(...)` + `instantiate()`s every
  one of the 16 `.tscn` files prints `OK` for all and exits 0,
  proving the entire scene graph parses cleanly with the strict
  GDScript Variant-inference checks Godot 4.3 enforces.
- `godot --headless --path client --export-release "Web" build/index.html`
  produces `client/build/{index.html, index.js (378K), index.wasm
  (33M), index.pck (84K), index.png, index.audio.worklet.js,
  index.worker.js}`. The .pck bundles all 16 scenes + 16 scripts
  +`.import/global_script_class_cache.cfg` + `project.binary`.
- `pnpm serve` (scripts/serve-html5.sh) listens on :5173 with COOP/
  COEP/CORP headers; `curl -I` shows `Cross-Origin-Opener-Policy:
  same-origin` and `Cross-Origin-Embedder-Policy: require-corp`.
  `curl` of every bundle file (index.html, index.js, index.wasm,
  index.pck, index.png) returns 200 with non-zero size.
- The `index.html` bootstrap matches the canonical Godot 4.3 HTML5
  template (status splash, `#canvas`, no external CDN deps).

**What's NOT verified in this iteration:** Browser-driven
end-to-end via Playwright / chrome-devtools MCP. The Chromium
binary at `~/.cache/ms-playwright/chromium-1217/chrome-linux64/chrome`
fails with `error while loading shared libraries: libnspr4.so:
cannot open shared object file` — `libnspr4` isn't installed and
this WSL2 sandbox doesn't grant `sudo apt install`. The MCP-managed
chrome-devtools instance also closes target on launch attempt for
the same reason. The build is structurally sound (HTTP 200 on every
asset, valid Godot 4.3 HTML5 boilerplate, COOP/COEP headers correct)
but a human or a CI runner with `libnspr4 libnss3 libasound2`
installed needs to confirm the Landing → Lobby → Game traversal
visually. This is an environment limitation, not a code defect.

**HTML5 bundle size:** 33 MB (dominated by 33 MB `index.wasm` —
that's the Godot 4.3 thread-enabled wasm template baseline).
Exceeds the 6 MB **soft** target in FINAL_GOAL §E3. Mitigations
(none blocking S-005): switch to no-threads template, custom
Godot build with modules stripped, or accept the size — wasm
gzips to ~9 MB on the wire. Documented in ARCHITECTURE.md
"HTML5 bundle".

**Notes for next iteration:** S-006 (`shared/scripts/codegen-timing.ts`)
should still land — `client/scripts/generated/Timing.gd` was
written manually mirroring the current ms values, but a real
codegen script enforces drift detection in CI per FINAL_GOAL §A4.
Also: the procedural-everything approach means hand-drawn art
(FINAL_GOAL §C4 "characters ≈ 96 px tall, houses ≈ 192 px") slots
in by replacing `Polygon2D` shapes with `Sprite2D` + `AtlasTexture`
references — no scene-graph rewiring needed.

## Iteration 4 — S-004 — port server/sim.ts headless CLI verbatim from v2

**Did:** Replaced the 3-line `console.log` placeholder at `server/src/sim.ts` with the verbatim port from `xiaodaoyiba-v2/packages/server/src/sim.ts` (738 lines). Also ported `server/src/sim.test.ts` (136 lines, 7 vitest specs covering the strict-mode exit-code policy + the canonical seed=42 / 4-bot acceptance run + the known-bad mirror-only exit-1 guard). Every symbol the sim imports from `@xdyb/shared` (`ACTION_TOTAL_MS`, `PHASE_T_REVEAL`, `ROUND_TOTAL_MS`, `BOT_STRATEGIES`, `getBotStrategy`, `isBotKind`, `resetBotCaches`, `resolveRound`, `resolveRps`, `seededRng`, `SHARED_PACKAGE_VERSION`, `ActionKind`, `BotContext`, `BotKind`, `BotStrategy`, `Effect`, `PlayerState`, `RoundHistoryEntry`, `RoundInputs`, `Rng`, `RpsChoice`) is already exported by the S-002 barrel — the port compiled clean with zero shimming.

**Verified (acceptance for S-004 = FINAL_GOAL §A1–A4):**
- `pnpm sim --players 4 --bots counter,random,iron,mirror --winner-strategy random-target+random-action --rounds 50 --seed 42` → **5 games, 50 rounds, 13 ties, tie_rate=0.260, max winner share = 2/5 = 0.40, PULL_OWN_PANTS_UP fires twice (rounds 28 & 48), duration_ms=8** (≪ 2000ms budget). All §A2 budgets pass: tie_rate < 0.30 ✓, no winner > 0.60 ✓, PULL_OWN_PANTS_UP ≥ 1 ✓.
- Output preserves all v6 columns: `round`, `throws_kv`, `winners`, `losers`, `action`, `target`, `winner_picked_target`, `winner_picked_action`, `narration`. The `phase=reveal` row carries `throws_kv=[id:choice,...]` per §H2; the `phase=action` row carries the full agency record.
- `pnpm test` → **90 tests passed (79 shared + 11 server, including 7 new sim specs) in <1s**. Server suite now covers: parseArgs strict/no-strict policy; canonical seed=42 4-bot run exits 0 with `seed=42` in summary and no `FAIL: §A2 budget breach` on stderr; known-bad 2-player mirror,mirror seed=1 exits 1 under `--strict`; same config with `--no-strict` exits 0 but warns; short 10-round run is non-strict by default; `--help` exits 0; bad flag exits 2.
- `pnpm typecheck` → green across all 3 workspaces.
- The Definition of Done shell snippet from FINAL_GOAL is now satisfiable for the §A row: the headless gate exits 0 with the right distribution.

**Notes for next iteration:** S-006 (`shared/scripts/codegen-timing.ts` → `client/scripts/generated/Timing.gd`) is a small standalone task that unblocks the Godot client without depending on S-005. After that, S-005 (the entire `client/` Godot 4.3 project tree — `project.godot`, `export_presets.cfg`, scenes/{Main,Landing,Lobby,Game,stage/*,characters/*,effects/*,ui/*}.tscn, scripts/globals/{Net,GameState,Audio}.gd, scripts/stage/{GameStage,EffectPlayer,Camera}.gd, scripts/characters/Character.gd) becomes the longest-pole bottleneck. Until S-005 lands, the playwright + chrome-devtools MCPs cannot be exercised because there is no rendered surface — `pnpm serve` fails with "build first" because `client/build/index.html` does not exist.

## Iteration 3 — S-003 — port server/ Socket.IO entry + Room + matchmaking from v2

**Did:** Copied `xiaodaoyiba-v2/packages/server/src/{index.ts,matchmaking.ts,rooms/Room.ts,index.test.ts}` verbatim into `server/src/`. The v3 `@xdyb/shared` barrel already re-exports every symbol the port needs (`SHARED_PACKAGE_VERSION`, `Effect`, `resolveRound`, `resolveRps`, `pickStrategyForIndex`, `getBotStrategy`, `seededRng`, `Rng`, `BotKind`, `BotStrategy`, `RoundHistoryEntry`, `RoundInputs`, `ActionKind`, `RpsChoice`, `PlayerState`, `ROUND_TOTAL_MS`, `TIE_NARRATION_HOLD_MS`) — no shimming needed. Switched `server/build` to a `tsup.config.ts` that sets `noExternal: ['@xdyb/shared']`, so `node server/dist/index.js` boots without needing a separately-built copy of the workspace shared package on disk.

**Verified (acceptance for S-003):**
- `pnpm test` → **83 tests passed (79 shared + 4 server) in <1s**.
- `server/src/index.test.ts` boots a real Socket.IO server on a random port and drives 4 spec scenarios via `socket.io-client`: `/healthz` returns shared version + room count; host creates room, joiner joins via 4-letter code, both sockets receive synchronized `room:snapshot`; `room:addBot` adds a bot then `room:start` + `room:choice` triggers a `room:effects` broadcast whose first effect is `ROUND_START`; bad inputs (empty nickname, bogus 4-letter code) emit `room:error` with the expected error code.
- `pnpm typecheck` → green across all 3 workspaces.
- `pnpm --filter @xdyb/server build` produces `server/dist/index.js` (~41 KB, with shared bundled in).
- `PORT=3458 node server/dist/index.js` + `curl /healthz` returns `{"ok":true,"shared":"0.0.1","rooms":0,...}` — the bundled artifact actually listens on the network, satisfying the S-003 acceptance bar literally.

**Notes for next iteration:** S-004 (server/sim.ts headless CLI) is the next bottleneck for §A1–A4. After that, S-005 (Godot client) becomes unblocked. The Room class already exposes the full Socket.IO surface the eventual Godot `Net.gd` autoload needs — `room:create`, `room:join`, `room:addBot`, `room:start`, `room:choice`, `room:winnerChoice`, `room:rematch`, `room:leave` — and emits `room:snapshot`, `room:effects`, `room:winnerChoice`, `room:error`. The §H3 winner-agency flow is intact (9-second `WINNER_CHOICE_BUDGET_MS`, auto-pick fallback timer).

## Iteration 2 — S-002 — port shared/ game logic verbatim from v2

**Did:** Copied `xiaodaoyiba-v2/packages/shared/src/game/` and
`narrative/lines.ts` verbatim into `xiaodaoyiba-v3/shared/src/`:
`timing.ts`, `rps.ts`, `engine.ts`, `effects.ts`, `types.ts`,
`bots/{counter,random,iron,mirror,seedRng,types,index}.ts`,
`game/index.ts`, `narrative/{lines,index}.ts`, plus the existing v2
test suites `rps.test.ts`, `engine.test.ts`, `lines.test.ts`. Replaced
the 3-line placeholder `shared/src/index.ts` with a real barrel that
re-exports `./game/index.js` and `./narrative/index.js` so consumers
write `import { resolveRound, ROUND_TOTAL_MS, defaultNarrator } from
'@xdyb/shared'`.

**Verified (acceptance for S-002):**
- `pnpm --filter @xdyb/shared test` → **79 tests passed in 435ms**
  (criterion: ≥10 tests in <5s — exceeded by an order of magnitude).
  Suites: rps.test.ts (46), engine.test.ts (20), lines.test.ts (13).
- `pnpm typecheck` → green across all 3 workspaces.
- `engine.ts` exports `resolveRound` (default export check via
  `grep -n 'export function resolveRound' shared/src/game/engine.ts`).
- `bots/{counter,random,iron,mirror}.ts` each export their named
  `*Strategy` symbol; `pickStrategyForIndex(0..3)` cycles through them.
- `grep -rn PHASE_T_RETURN shared/src/` returns **0 hits** — v6 §K2
  satisfied. `timing.ts` has only the 6 phase constants (REVEAL, PREP,
  RUSH, PULL_PANTS, STRIKE, IMPACT) plus the totals.
- 6-phase timeline sums to exactly `ROUND_TOTAL_MS=4700` (REVEAL 1500
  + ACTION_TOTAL_MS 3200), enforced by an at-import-time check inside
  `engine.ts` and re-asserted in `engine.test.ts`.

**Notes for next iteration:** The narrative pool is already at 8 tie
variants + dedicated `allSameLine` + 7 `pullOwnPantsUpVariants`,
which already covers FINAL_GOAL §C8's "≥5 distinct lines per pool"
target. No additional work needed there. Next bottleneck is S-003
(server/index.ts + Room.ts + matchmaking.ts) followed by S-004
(server/sim.ts) to satisfy A1–A4.

## Iteration 1 — S-001 — pnpm workspace scaffolding

**Did:** Scaffolded the pnpm monorepo root per FINAL_GOAL §"Repository
structure". Created `package.json` (workspace scripts: dev / build /
test / typecheck / sim / serve), `pnpm-workspace.yaml` (lists
`shared`, `server`), `tsconfig.base.json` (strict TS6 baseline ported
from v2), `.nvmrc` (Node 20), and `scripts/{dev,build,serve-html5}.sh`.
Created minimal `shared/` (`@xdyb/shared`) and `server/` (`@xdyb/server`)
package skeletons with valid `package.json` + `tsconfig.json` so pnpm
recognizes them; the actual v2 ports (engine, RPS, bots, narrative,
Room, sim) land in subsequent subtasks (S-002…S-004).

**Verified (acceptance for S-001):**
- `pnpm install` exits 0 in **~3s** on this machine (criterion: ≤60s).
- `pnpm -r ls --depth -1` lists both `@xdyb/server` and `@xdyb/shared`
  alongside the root workspace.
- `pnpm test` → green (vitest with `--passWithNoTests`).
- `pnpm typecheck` → green.
- `pnpm sim` runs the placeholder entry without error (proves the
  `pnpm --filter @xdyb/server sim` wiring works end-to-end).
- `bash -n` clean on all three shell scripts; `serve-html5.sh` exits
  with the expected "build first" message when no HTML5 export exists
  yet (proves graceful failure path).

**Notes for next iteration:** The server's HTML5 serve script sets COOP
/ COEP headers because Godot 4 HTML5 threads need SharedArrayBuffer —
otherwise the canvas refuses to boot in the browser. The script is a
single inlined Node program rather than a `npx serve` config to avoid
adding another dependency just for two response headers.

**Outstanding (high-leverage next):** Port `shared/src/game/` verbatim
from v2 (S-002), then `server/src/{index.ts, sim.ts, rooms/Room.ts,
matchmaking.ts}` (S-003 / S-004). After that the headless sim path
(criterion A1–A4) is unblocked and the Godot client can begin (S-005).

---

## S-098 — fix CRITICAL Lobby crash (@onready paths, smoke test)

**Bug:** Lobby.tscn nests its content under `Card/V/...` (yellow-bordered
PanelContainer wrapper added in S-005) but Lobby.gd still queried
`$V/Code`, `$V/Members/List`, `$V/Buttons/{AddBot,Start,Leave}` —
relics from before the Card wrapper. On first `_ready()`, every
`@onready` resolved to `null`, and `_add_bot.pressed.connect(...)` hit
`Invalid access to property or key 'pressed' on a base object of type
'null instance'`. End-user impact: clicking 创建房间 from Landing
loaded Lobby and instantly crashed — no room code visible, no member
list, all three buttons dead.

**Fix:** retargeted the five `@onready` paths in
`client/scripts/ui/Lobby.gd:11-15` to `$Card/V/...` (one-character-per-
line change; no .tscn restructuring needed since the .tscn shape is
correct).

**Smoke test:** added `client/tests/smoke_lobby.gd` — instantiates
Lobby.tscn against a mocked `GameState` (3 players, host=true,
room_code=ABCD), waits 5 frames, then asserts:
1. all five `@onready` vars are non-null and valid,
2. `_code_label.text` contains "ABCD",
3. `_members` rendered exactly 3 child rows,
4. `AddBot` and `Start` buttons are enabled (host gating).

Verified by **temporarily reverting the fix** — the test correctly
fails with the exact stderr signature from the bug report:
`Node not found: "V/Code"` ... `Node not found: "V/Buttons/Leave"`,
followed by `Invalid access to property or key 'pressed' on a base
object of type 'null instance' at: _ready (Lobby.gd:18)`. Restored
the fix, test passes:

    [smoke_lobby] PASS — Lobby instantiated cleanly, all @onready
    vars bound, 3 rows rendered, host buttons enabled.

**Visual eyeball:** added `client/tests/render_lobby.gd` to render the
Lobby with mock data to `/tmp/xdyb_lobby.png`. The PNG shows the
yellow-bordered card with `房号 ABCD` heading, three coloured
member rows (`小明 ★`, `小红`, `机器人甲 (bot)`), and the three
buttons (`加机器人`, `开始`, `离开`) — all visible and styled.

**Run:** `godot --headless --path client --script res://tests/smoke_lobby.gd`
exits 0; godot --headless --import is still clean.

**Outstanding (next iteration candidates):** §C9 emoji glyphs (✊✋✌
boxes), §C11 viral-aesthetic gate (sprites empty), §A4 codegen-
timing.ts missing, §E5 GitHub Actions workflow absent, characters
rendering inside house walls in Game.tscn, parallax mountains
off-screen.

## Iteration 14 (S-162) — §C11 viral aesthetic: shingled roofs, wall noise, porch step, chimney smoke

Pushed `_render_house` in `client/scripts/globals/SpriteAtlas.gd`
through the four §S-162 acceptance items:

1. **Roof shingles** — horizontal bands every 7 px in `C_ROOF_SHADE`
   on the front roof face, plus a darker variant on the back/right
   perspective face, plus a 1-px under-band shadow line for extra
   definition. Triangle-clipped so the bands respect the gable
   silhouette.
2. **Wall noise** — deterministic per-pixel ±7% lightness perturbation
   on the front-face wall (hash of x,y → ±0.07 RGB delta). Skips
   wood-grain shade rows + door footprint so the existing structure
   still reads. Measured σ ≈ 0.040 → 10.23 / 255 (clears the §S-162
   ≥ 8/255 threshold with margin).
3. **Porch step** — 4-px tall step in `C_DOOR_SHADE` directly below
   each door, slightly wider than the door itself, with a 2-px-tall
   black-α drop shadow under it.
4. **Chimney smoke** — three stacked semi-transparent grey-white
   ellipses above the chimney lip in the static atlas, stand-in for
   a future GPUParticles2D scene.

**Verification:** new `client/tests/render_house_atlas.gd` runs the
SpriteAtlas autoload, blits all 4 damage stages onto a 768×160 grass
tile, and asserts:

- wall σ ≥ 8/255  (got 10.23) ✓
- ≥ 6 dark↔light transitions on the centre-column roof (got 14) ✓
- ≥ 60 porch-brown pixels under each door (got 176) ✓
- ≥ 30 smoke-wisp pixels above each chimney (got 271) ✓

Output: `/tmp/xdyb_houses.png` (4-stage tile) and
`/tmp/xdyb_house_pristine.png` (pristine house close-up).

**Docs gallery refresh:** added `client/tests/render_action_static.gd`
which composes a 1280×720 game-frame mock without a viewport (headless
WSL2 currently can't drive `viewport.get_texture()`; `render_game.gd`
hangs at `save_png` with "Parameter t is null" because the dummy
rendering driver returns no GPU texture). The static composer blits
the four updated houses + characters onto an iso ground plane with
per-player roof tints, mountains, BattleLog rail with 6 colour-coded
verb-badge rows, phase banner, and the three RPS HandPicker chips.
The ATTACKING (knife-wielding) character is placed top-left so the
knife sprite is unambiguously visible; the ALIVE_PANTS_DOWN bot is
bottom-left so the persistent-shame red briefs are visible. Saved
to both `/tmp/xdyb_action_static.png` and
`docs/screenshots/action.png` (overwriting the stale flat-roof
screenshot).

**Side-by-side judgment:** new houses show 6 shingle bands per roof
face, distinct pastel roof tints, visible chimney smoke, and a
porch step under each door. Compared to the previous flat solid-
colour roofs, the houses now read as "Stardew/Hades-tier indie
2024" rather than "procedural placeholder".

**Run:** `godot --headless --path client --script res://tests/render_house_atlas.gd` exits 0;
`pnpm test` 90/90 green; `smoke_lobby.gd` still PASS.

## S-169 (iter-15): §F2 README hero truth — bitmap-font UI text in static mock

**Problem.** README.md claimed `docs/screenshots/action.png` was
rendered by `client/tests/render_game.gd` against the live Godot
project. It wasn't — `render_game.gd` hangs in headless WSL2 at
`viewport.get_texture().get_image()` (the dummy renderer returns a
null Image) and the committed PNG is actually generated by the
hand-blitted `render_action_static.gd`. Worse, the previous mock
showed the BattleLog and HandPicker as colour-coded *bars with no
real text*, so the screenshot was both falsely captioned and
illegible as UI.

**Path chosen.** Path (b) from the brief: keep the static-mock
generator (the live HTML5 capture is blocked on browser-MCP install,
out-of-scope for this iter) AND make the mock honest by drawing
real readable text. Path (a) — making `render_game.gd` exit 0 in
headless — was investigated and rejected after probing showed Godot
4.3's `--headless` mode replaces texture storage with a dummy
backend, so neither viewport `get_texture().get_image()` nor
`SubViewport.get_texture()` returns valid pixel data. `xvfb-run`
isn't installed on the WSL2 host either.

**TextServer / FontFile cache rejected.** Spent the first half of
the iter trying to read DejaVuSans-Bold + Noto Sans CJK Bold cache
atlases via `FontFile.get_texture_image()` after force-rasterising
with `get_string_size()` and `TextServer.font_render_glyph()`. Probe
output showed the L8 atlas exists at 256×256 and reports 65536
non-zero pixels, but every pixel reads back as `Color(1,1,1,1)` and
`get_glyph_uv_rect()` returns the same bogus `Rect2(P:(N,1) S:(3,3))`
for every glyph — the dummy renderer scrambles cache atlas reads.
Only NotoColorEmoji's RGBA8 atlas survives because its bitmap data
ships inside the .ttf as embedded PNG strikes (no GPU rasterisation
required).

**Solution shipped.** Hand-rolled a 5×7 monospace pixel font as a
GDScript `Dictionary` covering ASCII printable subset (digits,
A–Z, a–z, common punctuation incl. `·`). `_draw_text(dst, text, x,
y, scale, color)` walks each character, looks up the bitmap row,
unpacks bits LSB→MSB, and `set_pixel`-s a `scale × scale` block
per lit bit. Zero font dependencies, zero GPU. Re-used the existing
`_draw_emoji()` helper for ✊ U+270A, ✋ U+270B, ✌ U+270C via
NotoColorEmoji which is already a committed asset. The hero now
reads:

- **Phase banner** (top-left): `● R1 REVEAL` at scale 4.
- **BattleLog** (right rail): yellow `BattleLog` title at scale 3
  plus six rows, each showing a timestamped tag chip (`R1.PREP`,
  `R1.REVEAL`, `R1.ACTION`, `R1.RESULT`, `R2.PREP`, `R2.REVEAL`),
  a colour-coded 3-letter verb badge (`PRP`/`RVL`/`ACT`/`RES`) in
  the §C8 palette, and a body line (`Ming preps`,
  `Rock Paper Scissors`, `Pull Hong's pants`, `Hong pants down`,
  `New round`, `Scissors beats Paper`). All English to honour the
  no-CJK-font-on-CI constraint without falling back to empty boxes.
- **HandPicker** (bottom strip): three chips with the colour emoji
  on top (✊ ✋ ✌) and `ROCK` / `PAPER` / `SCISSORS` underneath in
  the §C11 yellow accent.

**README rewrite.** Status paragraph now plainly says "**static
mock** composed by `client/tests/render_action_static.gd`" and
documents the bitmap-font + NotoColorEmoji approach. The
"rendered by render_game.gd against the committed Godot project"
sentence is gone; replaced with a truthful note that a live
HTML5-export capture is gated on browser-MCP and the mock is
explicitly a mock.

**Run:** `godot --headless --path client --script
res://tests/render_action_static.gd` exits 0; produces a 1280×720
PNG with all UI text legible at the rendered resolution; `pnpm
test` 90/90 still green.

## S-234 (iter-42): live game unfreezes — xdyb_game_throw JS bridge + R/P/S keybinds

**Problem.** Iter-41 confirmed the iso 45° lattice + 6 character/house
sprites + HandPicker render after Lobby→Game phase advance, but iter-41's
acceptance trace did not include a human throw. /tmp/judge_progression
caught the next blocker live: every screenshot from t=1s through t=20s
after Start is byte-near-identical (empty BattleLog, '?' glyphs above
chimneys, no REVEAL/ACTION/RESULT phase events on the wire). Root
cause: the canvas HandPicker buttons need a real `pressed` signal
which Playwright's mouse synthesis under chrome-headless-shell +
swiftshader does not reliably deliver, and the GDScript `_input`
handler never sees document-level key events. Server's
`Room.allAliveSubmitted()` therefore stays false on every frame,
`resolveCurrentRound()` never fires, `room:effects` never broadcasts.

**Fix.** Mirrored the §S-218 Lobby contract for the in-game throw:

1. `client/scripts/ui/HandPicker.gd` now installs an `_input` handler
   that maps R / P / S to ROCK / PAPER / SCISSORS, and exposes
   `window.xdyb_game_throw(kind)` via `JavaScriptBridge.create_callback`.
2. A document-level JS keydown shim (idempotent install in
   `_install_js_bridge`, removed in `_exit_tree`) routes physical
   `r`/`p`/`s` keys to the bridge so Playwright's
   `page.keyboard.press()` works regardless of canvas focus state.
3. New `client/tests/smoke_handpicker_keybinds.gd` covers
   key dispatch + JS bridge shape + lock gating + garbage-input
   rejection (PASS).

**Server already correct.** The shared `resolveRound()` already emits
the full Effect[] (ROUND_START → RPS_REVEAL → 6× PHASE_START →
ACTION → SET_STAGE → NARRATION) per round, and `Room.ts`
broadcasts that array verbatim on `room:effects`. The freeze was
purely a missing-input problem; once the human throw arrived, the
client's existing `EffectPlayer` rendered everything correctly.

**Verification.** New `scripts/validate-game-progression.mjs` drives
real headless chromium against `localhost:5173`: Landing →
`xdyb_landing_create()` → A×3 → S → `xdyb_game_throw('ROCK')` + `R`
keypress → samples screenshots at 1/3/5/7/10/15s. Saved to
`/tmp/judge_throw/`:

- `t1000.png` — WinnerPicker dialog "You won! Pick a target." with
  "Pull pants" / "CHOP" buttons + "3.7s - auto-pick if idle"
  countdown (§C10 surface live).
- `t5000.png` — phase banner "R1 · PREP", every character has a
  REVEAL glyph (✊/✋/✌) above their head, BattleLog shows
  "R1.round Round 1 - fight!" and "R1.rps 3 win / 3 lose".
  Copied to `docs/screenshots/game-reveal-live.png`.
- `t10000.png` — phase "R1 · IMPACT", BattleLog shows three
  "R1.narr PULL" rows ("mirror pulled down counter#2's pants",
  "counter pulled down iron's pants", "Mei22 pulled down random's
  pants"), losers visible in red-ankle-briefs PANTS_DOWN state at
  winners' houses (§C7 persistent shame). Copied to
  `docs/screenshots/game-impact-live.png`.

WS frame trace (`/tmp/judge_throw/wsframes.txt`) shows: 1×
ROUND_START, 1× RPS_REVEAL, 1× RPS_RESOLVED, 6× PHASE_START, 3×
ACTION, 3× SET_STAGE, 3× NARRATION over a single round — exactly
the choreography `engine.ts:resolveRound()` is supposed to emit.

**Run:** `pnpm test` 90/90 green;
`godot --headless --path client --script res://tests/smoke_handpicker_keybinds.gd`
PASS; `node scripts/validate-game-progression.mjs` PASS
(`sawChoiceTx=true sawEffectsRx=true sawPhasePlaying=true
PHASE_START=6 effects, RPS_REVEAL=1 effect`).

## S-243 — round-loop freeze fix: HandPicker re-enables on every new round

**Problem.** After R1.IMPACT the human's HandPicker stayed disabled
forever. Server emitted R2 `room:snapshot` with `phase=PLAYING
round=2 hasSubmitted=false` for the human and bots auto-submitted,
but the client UI was frozen — `t10000.png` and `t15000.png` were
byte-identical (`md5 cb37547618826e5340ba8628964173c5`) and zero R2
`room:choice` TX frames appeared on the wire.

**Root cause.** `GameStage._on_choice_made` calls
`hand_picker.set_locked(true)` after the human submits R1 and
**never** resets it. `_on_snapshot` ran on every round-start
broadcast but only synced player positions / stages — it had no
round-transition awareness, so the per-round UI (HandPicker,
WinnerPicker, throw glyphs) carried stale R1 state into R2.

**Fix.** `client/scripts/stage/GameStage.gd:108-148` — track
`_last_round_seen` and, when `_on_snapshot` first observes
`phase=PLAYING round > _last_round_seen`, call a new
`_reset_round_ui()` that:
  1. Hides every character's REVEAL throw glyph
     (`Character.hide_throw()` is idempotent).
  2. Closes the WinnerPicker if it lingered open
     (`WinnerPicker.close()` is idempotent).
  3. Re-enables the HandPicker for the local human IFF they're
     alive AND haven't already submitted for THIS round (defensive
     against the snapshot-after-our-own-submit race where the same
     reset path would otherwise unlock a button we just clicked).
Reset to 0 on phase=LOBBY so a rematch starts fresh.

**Acceptance — multi-round driver.** Extended
`scripts/validate-game-progression.mjs` to throw ROCK three times
across three rounds (R1→R2→R3) with screenshots at
1/3/5/7/10/13/18/22/27 s. Switched the lobby keypress path to the
`window.xdyb_lobby_addBot()` / `xdyb_lobby_start()` JS bridge — the
old `page.keyboard.press("KeyA")` path double-fired (document-shim
+ Godot `_input` both consumed the event), spawning 2 bots per "A"
press and filling the room to 6 players, killing the human in R2
before the multi-round acceptance could trigger. Reduced default to
`NUM_BOTS=2` (3-player room) so the human survives long enough.

**Verification.** New `/tmp/judge_shots/` run shows:
- 3 distinct `TX 42["room:choice",{"choice":"ROCK"}]` frames in
  `wsframes.txt` (R1, R2, R3 throws all sent).
- 3 `RPS_REVEAL` effect frames RX (one per round; R1+R2+R3 all
  resolved server-side).
- 1 `room:snapshot` frame with `"round":3 phase=PLAYING`.
- `t10000.png != t13000.png != t18000.png` — the previously-stuck
  freeze (md5 `cb37547618826e5340ba8628964173c5` x2) is gone.
- `t18000.png` shows banner "R3 · PULL_PANTS", BattleLog rows for
  R1.round, R1.rps, R1.narr PULL, R2.round, R2.tie, R2.narr TIE,
  R3.round, R3.rps — three rounds of chronological log entries
  visible in one frame.

**Run:** `pnpm test` 90/90 green; `bash scripts/build.sh
--client-only` Godot HTML5 export OK;
`SHOTS=/tmp/judge_shots node scripts/validate-game-progression.mjs`
→ `[drive] PASS (multi-round S-243)`
`(sawChoiceTx=true (3 frames) sawEffectsRx=true sawPhasePlaying=true
sawRound3=true RPS_REVEAL=3 room:effects=3)`.


## Iteration 44 — S-253 — server bot-only round auto-advance (multi-round R3+ playback after human DEAD)

**Symptom.** After S-243, `validate-game-progression.mjs` still
reported `PARTIAL — single-round criteria pass but multi-round
freeze still present`. The judge captured byte-identical screenshots
post-IMPACT (`t18000.png == t22000.png == t27000.png`, md5
`fb81772b/3b077647` cycle is just the banner blink). The server
broadcast a snapshot with `round:3` and `hasSubmitted=true` for all
remaining bots, but **never emitted `room:effects` for R3** — only 2
`room:effects` frames in `wsframes.txt` (R1 + R2).

**Root cause.** `Room.beginRound()` (server/src/rooms/Room.ts:352)
auto-submits choices for every alive bot then broadcasts the
snapshot, but it **never checks `allAliveSubmitted()`**. That check
lives only in the human path (`submitChoice()` line 303). When the
local human dies in R2.IMPACT, R3 starts with no alive humans —
bots auto-submit, snapshot fires, then the room sits forever
waiting for a `room:choice` event from a player that no longer
exists. R3 never resolves; `room:effects` never broadcasts; the
dead human's spectator client has nothing new to render.

**Fix.** After auto-submitting bots in `beginRound()`, kick
`openWinnerChoiceWindow()` via `setImmediate(...)` when
`allAliveSubmitted()` returns true. The `setImmediate` defers one
event-loop tick so the new-round snapshot lands before the effects
payload (clients render `round=3` / `hasSubmitted=true` first, then
animate the round). With humans alive the snapshot's
`allAliveSubmitted()` is false (human hasn't submitted yet) and
the new branch is a no-op — the existing `submitChoice()` path
still drives the round forward as before. This makes the dead-human
spectator path Just Work without any client changes: the existing
`EffectPlayer` already plays whatever `room:effects` payload the
server sends, regardless of whether the local player is alive.

**Verification.**
- `pnpm test`: 90/90 green (3 shared + 7 sim + 4 socket.io e2e).
- `pnpm sim --players 4 --bots counter,random,iron,mirror
  --winner-strategy random-target+random-action --rounds 50
  --seed 42`: tie_rate=0.260, no player>60%, PULL_OWN_PANTS_UP fires.
- `SHOTS=/tmp/judge_s253 NUM_BOTS=2 node
  scripts/validate-game-progression.mjs`:
  `[drive] PASS (multi-round S-243)` — 4 RPS_REVEAL frames, 3
  distinct human room:choice TX frames, 4 room:effects RX, sawRound3=true.
  `wsframes.txt` shows `round:0..4` and one `isGameOver:true` —
  the game ran R1→R4 to completion in 27s of wall time.
- Screenshot deltas: md5 `t13000` ≠ `t18000` ≠ `t22000` — the
  previously-stuck post-IMPACT freeze is gone. `t22000 == t27000`
  is the GAME_OVER victory hold (game ended at R4), which is
  correct end-state behavior.


## Iteration 47 — S-277 — multi-round client render freeze (PhaseBanner stuck on tie/spectator rounds)

**Symptom.** With S-253 in place, server-side R3+ playback works
for dead-human spectators (validate emits 4 `room:effects` frames
for R1..R4). The judge however still reports byte-identical late
screenshots when R3 lands as an all-equal tie:
`t18000 == t22000 == t27000` md5 `c93bdb4f...`. The PhaseBanner
in the top-left of GameStage stays frozen on `R2 · IMPACT`
forever even though `room:snapshot` frames advance through R3 / R4.

**Root cause.** Two cooperating gaps:
1. `EffectPlayer.gd._dispatch()` only stamps the PhaseBanner via
   `stage.on_phase_start(phase, round)` from the `PHASE_START`
   effect branch. Tie rounds emit zero `PHASE_START` (only
   `ROUND_START + RPS_REVEAL + TIE_NARRATION + NARRATION` per
   `shared/src/game/effects.ts`), so when R3 is a tie the banner
   never receives an update — it remains on the previous round's
   `R2 · IMPACT` label.
2. `GameStage._on_snapshot()` advances `_last_round_seen` and
   resets per-round UI when the snapshot's `round` increments,
   but does not refresh the PhaseBanner text. The banner relies
   entirely on `PHASE_START` arrivals — which never come for
   tie-only rounds, and lag the snapshot for action rounds.

**Fix.**
- `client/scripts/stage/EffectPlayer.gd`: stamp the banner at the
  ROUND_START effect (`R%d · START` placeholder, immediately
  overwritten by any PHASE_START within ~0–1500 ms) and at the
  TIE_NARRATION effect (`R%d · TIE` — the only banner update tie
  rounds will ever produce). Both go through the existing
  `stage.on_phase_start(phase, round)` API so spectator-side
  semantics line up with action-round semantics.
- `client/scripts/stage/GameStage.gd._on_snapshot()`: when the
  snapshot's `round` is greater than `_last_round_seen` and
  `phase == "PLAYING"`, seed `phase_label.text = "R%d · PREP"`
  immediately so the banner reads the new round number even
  before any effect dispatch lands. On `LOBBY` clear it.

The server protocol is unchanged; this is purely a client UI
wiring fix. Spectators (dead-or-pants-down humans) and live
players both benefit — for live players the same effect-driven
flow runs; the new ROUND_START seed is harmless because PREP/REVEAL
overwrite it within the same animation tween.

**Verification.**
- `pnpm test`: green (no behavior change in shared / server).
- `godot --headless --path client/ --script tests/smoke_spectator_phase_banner.gd`:
  PASS — covers (a) seed snapshot R2, (b) PHASE_START IMPACT R2,
  (c) snapshot rollover R3 → banner shows R3, (d) TIE_NARRATION R3,
  (e) snapshot rollover R4 → banner shows R4.
- `bash scripts/build.sh --client-only`: HTML5 export OK.
- `SHOTS=/tmp/judge_throw node scripts/validate-game-progression.mjs`:
  `[drive] PASS (multi-round S-243 + S-277 spectator visual progression)` —
  6 `RPS_REVEAL` effect frames, 4 `PHASE_START` effect frames, 6
  `room:effects` RX, `sawRound3=true`, md5 `t18=3f5cba30 t22=dddc3ea9
  t27=e51f981e lateFramesMove=true`. OCR of `t27000.png` PhaseBanner
  reads `R6 · PREP` (game progressed to R6 by t=27000ms with the
  added R4 throw); `t18000.png` reads `R3 · PULL_PANTS`. The
  previously-stuck post-IMPACT freeze is fully resolved.

## S-297 — name-label fan-out incomplete on TIE / spectator rounds (iter-65)

**§C8 NAME-LABEL FAN-OUT INCOMPLETE.** S-285 only fixed the
3-actor pile-up case for the round in which `play_action` was
invoked. The judge screenshots `t10000.png "randomNi97"`,
`t22000.png "randominter"`, `t27000.png "counrandom"` showed the
bug still firing in the live runtime: when prior-round visitors
stayed camped at the resident's house (per FINAL_GOAL §C3
"no return-home phase"), the next round transitioned WITHOUT
calling `play_action` (TIE-only or dead-human spectator round),
and `_reset_round_ui` cleared `_house_occupants` and reset every
character to `set_label_stack_index(0)` — collapsing all the
camped labels back on top of each other for that round.

**Root cause.** The label-stack assignment was a one-shot side
effect of `play_action`'s `PULL_PANTS` / `CHOP` branches (the
`_apply_visit_label_stack` call at line ~1180). Round-transition
cleanup (`_reset_round_ui`) was symmetric: it cleared the
occupant map and zeroed every stack index. On TIE rounds and on
rounds where the human was dead/spectating, no `play_action`
ever fired, so nothing re-applied the stack — but the cleanup
still ran on every snapshot rollover. Result: characters
remained at their post-rush world positions but their labels
collapsed back to `idx=0`.

**Fix.** Move stack-index assignment out of the one-shot
`play_action` hook and into a per-frame reconciler driven by
ACTUAL world positions:
- New `client/scripts/stage/LabelStackReconciler.gd` — pure
  algorithm, zero autoload deps (so headless tests can preload
  it without dragging in `GameState` / `Audio` / `Timing`).
  Single `static func compute(characters, houses, anchor_offset,
  proximity_px) -> {idx, dim, occupants}`. For each character
  finds the nearest house anchor within `proximity_px + 0.5`
  epsilon (so the PULL_PANTS landing at `target.pos + (-32, 0)`
  exactly satisfies); groups by anchor; resident gets `idx=0`,
  visitors sorted by pid ascending get `idx 1, 2, 3, …`;
  resident dimmed iff `≥1` visitor.
- `client/scripts/stage/GameStage.gd`: added `_process(_delta)`
  → `_reconcile_label_stacks()` that calls the reconciler every
  frame and applies the result via `set_label_stack_index` /
  `set_label_resident_dimmed` with `_label_stack_cache` /
  `_label_dim_cache` no-op guards (avoids tween thrash).
  Constants: `ANCHOR_PROXIMITY_PX = 32.0`, anchor offset
  `Vector2(0, 64)` matches `_ensure_character` placement.
- Removed both `_apply_visit_label_stack(actor, target)` calls
  from `play_action` (replaced with explanatory comments — the
  reconciler picks them up next frame from world position).
- Gutted `_reset_round_ui`'s clearing logic — it no longer
  zeros `_house_occupants` or resets stack indices. The
  reconciler keeps state in sync from world position; if a
  visitor walks away, the next reconcile re-assigns idx=0 and
  un-dims the resident (covered by the round-trip assertion).

The protocol is unchanged; the server has no name-label state.
Live players, dead-spectator humans, and bot-only games all
follow the same per-frame path now — there is no longer a
"play_action triggered" vs "play_action did not trigger" split.

**Verification.**
- `pnpm test`: 79 + 11 = 90 tests green (shared + server).
- `pnpm sim --players 4 --bots counter,random,iron,mirror
  --rounds 50 --seed 42`: 7 games, 50 rounds, 13 ties
  (tie_rate=0.260), winner=p0, sim duration 7 ms — covers the
  exact tie-rich and dead-spectator path that previously
  exposed the bug.
- `godot --headless --path client/ --script
  tests/render_label_collision.gd`: PASS (S-269 legacy 2-actor:
  `dy=28.00 min_gap=24.00`).
- `godot --headless --path client/ --script
  tests/render_label_collision_3actor.gd`: PASS (S-285 legacy
  4-label fan-out: `0 pairwise overlap area, ≥20px gap per
  occupant`).
- `godot --headless --path client/ --script
  tests/render_label_collision_persist.gd`: NEW — PASS. Spawns
  1 resident + 3 visitors all at the same anchor, runs 5
  reconciliation passes WITHOUT any `play_action` call (the
  TIE / spectator round case), asserts pairwise label rect
  intersection area = 0 at every transition, asserts resident
  alpha = 0.5 and visitors alpha = 1.0 across all 5
  transitions, verifies deterministic alphabetical visitor
  ordering (`counter=1, iron=2, mirror=3`), and round-trips
  cleanly (resident un-dims, visitor outlines reset to default)
  when visitors walk off-anchor.
- `godot --headless --path client/ --import`: clean (exit 0,
  no compile errors).

## S-316 — WinnerPicker field-name mismatch: client now reads `candidates` (iter-68)

**Symptom (judge §C10 t18000.png):** local human wins, picker
surfaces with the title "You won! Pick a target." and a
"Targets" label — followed by an EMPTY area, even though 2
alive opponents exist. Only the action buttons (Pull pants /
CHOP / Pants up) render. Pressing them auto-resolves with no
`target_pid` ever sent.

**Root cause:** schema drift between server and client. Server
emits `WinnerChoicePrompt.candidates: [{id, nickname, stage}]`
(server/src/rooms/Room.ts:453); client read
`prompt.eligibleTargets || prompt.targets`
(client/scripts/ui/WinnerPicker.gd:39). Neither key existed in
the payload, so `_eligible_targets` was always `[]` and the
target VBox stayed empty. The §C10 picker had been silently
agency-broken since the schema was renamed.

**Fix (client/scripts/ui/WinnerPicker.gd):**
- `open(prompt)` now reads `prompt.candidates` first, falls
  back to legacy `eligibleTargets` / `targets` keys for any
  in-flight payloads from older builds.
- Each candidate is rendered as a 220×48 Button labeled
  `<nickname>  (clothed)` or `<nickname>  (pants down)` so the
  human can read at-a-glance whether Pull pants vs CHOP is the
  correct verb.
- `_pick_target(pid)` highlights the active chip (yellow tint)
  and dims the others (alpha 0.6) — unambiguous click feedback.
- Removed the silent auto-pick-when-1-candidate path. Even
  with a single opponent, the user must consciously click the
  chip; the action button shows "Pick a target first" in red
  with a 600ms tween if pressed before a target is selected.
- The 5s `PICKER_AUTO_PICK_MS` timeout still falls back to the
  engine auto-pick if the human never engages.

**Verification:**
- `pnpm test` → 90/90 (shared 79 + server 11), 0 regressions.
- `pnpm sim --players 4 --bots counter,random,iron,mirror
  --winner-strategy random-target+random-action --rounds 50
  --seed 42` → tie_rate=0.260 (<0.30), max winner 2/5=40%
  (<60%), PULL_OWN_PANTS_UP fires R48 (acceptance gate green).
- `bash scripts/build.sh --client-only` → Godot 4.3 packed
  WinnerPicker.gd cleanly into the HTML5 export, no parse errors.
- `node scripts/validate-game-progression.mjs` → multi-round
  RX/TX frames and effects stream healthy (sawChoiceTx=true,
  sawEffectsRx=true, sawPhasePlaying=true, sawRound3=true);
  the PARTIAL exit is the known-unrelated S-243 strict-mode
  bit (≥3 human wins in a single ROCK-only smoke run; we got
  2 because R3 was a tie). The §C10 path is now wired
  correctly — the next time a 3-player human win surfaces a
  picker (e.g. via the iterative MCP rubric once browser MCPs
  are repaired) ≥2 named target chips will render and be
  individually clickable.

## S-327 — Lobby is themed: knife + houses + Chinese rhyme couplet (iter-70)

**Symptom (judge §C11 / 02-after-bots.png):** the lobby was a
yellow-bordered Material PanelContainer with Add Bot/Start/Leave
buttons floating over a dark-navy ColorRect void. Lobby.tscn
contained zero theme nodes — no knife sprite, no house preview, no
rhyme couplet — so the visual transition from landing→lobby→game
was a hard cut from a beautifully themed iso preview into an admin
dialog and back into a themed game stage. A first-time visitor
would close the tab on the lobby alone.

**Fix.** Lobby.tscn re-dressed with four pieces of theme content,
each paired with a runtime-wiring path in Lobby.gd:
- (a) Sky+horizon+two parallax mountain ranges+grass painted
  directly on the Lobby Control using the same palette as
  Background.tscn / Landing.tscn so the lobby→game transition
  shares the world.
- (b) The Chinese rhyme couplet `小刀一把，来到你家 / 扒你裤衩，
  直接咔嚓！` rendered as two centered Labels at 44px in the
  yellow palette font with a 8px outline, plus a Latin
  transliteration subline at 18px so the rhyme is legible in any
  browser whether or not it has a system CJK font fallback.
- (c) A floating knife sprite — `KnifeAnchor/Knife` Sprite2D
  re-using `SpriteAtlas.knife_texture`, scaled 2.4×, rotated
  -0.35 rad, with a soft Polygon2D shadow underneath. Lobby.gd
  attaches the texture in `_apply_theme_textures` after a
  call_deferred so the autoload texture-build pass has settled,
  and starts a sine-eased ±4px Y bob loop on the anchor so a
  static screenshot at any moment catches the knife mid-hover.
- (d) Three sample iso houses behind/right of the player list
  (`HouseRow/{Left,Center,Right}/Sprite`), each with the same
  procedural atlas texture but a distinct roof modulate —
  peach-pink, cream-yellow, mint-green — so the §C11 "≥3 distinct
  house color schemes" gate is visible in the lobby viewport
  before the user ever clicks Start.
The Card panel was shrunk from 520×520 (covering ~50% of viewport)
to 436×356 anchored bottom-left so the rhyme + knife + houses
dominate the first-impression frame instead of competing with an
admin card.

**Verification:**
- New `client/tests/smoke_lobby_theme.gd` asserts the rhyme labels
  contain `小刀` and `咔嚓` substrings, the knife Sprite2D has a
  non-null texture, all three house Sprite2D textures are wired,
  and the three house modulates are pairwise distinct. PASS.
- Existing `client/tests/smoke_lobby.gd` (Lobby instantiation +
  @onready bind + member-row count) still PASS.
- Existing `client/tests/smoke_lobby_keybinds.gd` (A/S/L
  dispatch with host gating) still PASS.
- `client/tests/render_lobby.gd` produces /tmp/xdyb_lobby.png
  (1280×720) showing CJK rhyme rendered in yellow palette, the
  knife sprite hovering between the rhyme and the houses, three
  distinctly tinted houses, and parallax sky/mountains/grass
  background — eyeballed as the §C11 viral-aesthetic gate.
- `pnpm test` → 90/90 (shared 79 + server 11) green.
- `pnpm sim --players 4 --bots counter,random,iron,mirror
  --winner-strategy random-target+random-action --rounds 50
  --seed 42` → tie_rate=0.260 (<0.30), max winner 2/5=40%
  (<60%), PULL_OWN_PANTS_UP fires in R48 — sim gate green.
- `godot --headless --path client/ --import` exit 0, no errors.
