// Pure round engine.
//
// `resolveRound(state, inputs)` is a pure function: same inputs → same outputs,
// no I/O, no clock, no Math.random. The engine wraps `resolveRps` (the RPS
// majority/outlier rule from FINAL_GOAL §A2) with action selection
// (PULL_PANTS / CHOP), narration emission, and 6-phase timeline tagging
// (REVEAL → PREP → RUSH → PULL_PANTS → STRIKE → IMPACT, durations imported
// verbatim from `timing.ts`). It is the single primitive that the headless
// sim CLI, the Socket.IO server, and the client EffectPlayer all advance
// state with — there is no second engine elsewhere.
//
// Design notes
// ------------
// - The function never mutates its inputs. `players` is deep-cloned before
//   any state change, and the returned `players` is the post-round snapshot.
// - Pairing rule: winners[] iterate in their input order; each winner claims
//   the first not-yet-claimed loser as a target (or uses an explicit
//   `inputs.targets[winnerId]` if provided and that loser is still
//   unclaimed). Losers can only be acted on once per round, so in a
//   2-winner / 3-loser round only 2 of the 3 losers are acted on.
// - Default action kind is determined by the *target's pre-round stage*:
//     ALIVE_CLOTHED    → PULL_PANTS
//     ALIVE_PANTS_DOWN → CHOP
//     DEAD             → NONE  (defensive; dead players shouldn't be losers)
// - Narration is emitted as `NARRATION` effects with a `verb` field used by
//   the BattleLog for color-coded badges. The engine ships a small built-in
//   pool here so it stands alone; the broader narrative/lines.ts module
//   (FINAL_GOAL §C8 — ≥5 tie variants etc.) can swap in a richer pool by
//   passing `options.narrator`.

import {
  ACTION_TOTAL_MS,
  PHASE_T_IMPACT,
  PHASE_T_PREP,
  PHASE_T_PULL_PANTS,
  PHASE_T_REVEAL,
  PHASE_T_RUSH,
  PHASE_T_STRIKE,
  ROUND_TOTAL_MS,
  SHAME_FRAME_HOLD_MS,
  TIE_NARRATION_HOLD_MS,
} from './timing.js';
import type { Effect } from './effects.js';
import type {
  ActionKind,
  ActionPhase,
  PlayerState,
  RoundInputs,
} from './types.js';
import { resolveRps, type PlayerId, type RpsChoice, type RpsResolution } from './rps.js';
import { defaultNarrator } from '../narrative/lines.js';

/** Phase boundary (atMs offset, durationMs) — cumulatively sums to
 *  ROUND_TOTAL_MS (REVEAL + ACTION_TOTAL_MS). Computed from timing.ts so
 *  swapping the constants flows everywhere. The REVEAL phase opens every
 *  non-tie round so all players' throws can be displayed simultaneously
 *  above their stations (FINAL_GOAL §H2) before the rush kicks in.
 *
 *  v6 §K2: the RETURN beat was removed. The actor stays at the target's
 *  house through IMPACT and the next round's PREP teleports them home,
 *  so a successful pants-pull or chop lingers on screen instead of being
 *  immediately undone by a return-walk animation. */
const PHASE_TIMELINE: ReadonlyArray<{
  phase: ActionPhase;
  atMs: number;
  durationMs: number;
}> = (() => {
  const phases: Array<{ phase: ActionPhase; durationMs: number }> = [
    { phase: 'REVEAL', durationMs: PHASE_T_REVEAL },
    { phase: 'PREP', durationMs: PHASE_T_PREP },
    { phase: 'RUSH', durationMs: PHASE_T_RUSH },
    { phase: 'PULL_PANTS', durationMs: PHASE_T_PULL_PANTS },
    { phase: 'STRIKE', durationMs: PHASE_T_STRIKE },
    { phase: 'IMPACT', durationMs: PHASE_T_IMPACT },
  ];
  let cursor = 0;
  return phases.map((p) => {
    const at = cursor;
    cursor += p.durationMs;
    return { phase: p.phase, atMs: at, durationMs: p.durationMs };
  });
})();

/** atMs of the start of each phase, for callers that need the offsets
 *  without iterating. Validated as cumulative-sums-to-ROUND_TOTAL_MS at
 *  module load. After §H2/§K2 REVEAL=0, PREP=PHASE_T_REVEAL=1500, …,
 *  IMPACT+PHASE_T_IMPACT=ROUND_TOTAL_MS=4700. */
export const PHASE_OFFSETS: Readonly<Record<ActionPhase, number>> = (() => {
  const out: Record<string, number> = {};
  for (const { phase, atMs } of PHASE_TIMELINE) out[phase] = atMs;
  return out as Record<ActionPhase, number>;
})();

/** Self-test: the 6-phase timeline must sum to exactly ROUND_TOTAL_MS,
 *  and the action sub-segment (PREP→IMPACT, i.e. excluding REVEAL) must
 *  still sum to ACTION_TOTAL_MS so callers reasoning about action
 *  duration in isolation keep working. This runs at import time so a
 *  typo in timing.ts is caught immediately instead of producing a
 *  desynced choreography. */
{
  const last = PHASE_TIMELINE[PHASE_TIMELINE.length - 1]!;
  const total = last.atMs + last.durationMs;
  if (total !== ROUND_TOTAL_MS) {
    throw new Error(
      `[engine] PHASE_TIMELINE sums to ${total}ms but ROUND_TOTAL_MS=${ROUND_TOTAL_MS}; check timing.ts`,
    );
  }
  const actionSegment = total - PHASE_T_REVEAL;
  if (actionSegment !== ACTION_TOTAL_MS) {
    throw new Error(
      `[engine] action sub-segment is ${actionSegment}ms but ACTION_TOTAL_MS=${ACTION_TOTAL_MS}; check timing.ts`,
    );
  }
}

/** Optional plug-in narrator. Default is a small built-in. */
export interface Narrator {
  tie: (round: number, reason: 'all-same' | 'all-equal' | 'empty') => string;
  pullPants: (actorName: string, targetName: string, round: number) => string;
  chop: (actorName: string, targetName: string, round: number) => string;
  pullOwnPantsUp: (actorName: string, round: number) => string;
}

// Default narration is now sourced from `../narrative/lines.ts` (the
// FINAL_GOAL §F-mandated module). The Narrator interface above and the
// `defaultNarrator` shape there are structurally compatible — the import
// statement at the top of this file binds them.
const DEFAULT_NARRATOR: Narrator = defaultNarrator;

export interface ResolveOptions {
  /** Plug a richer narrator from `narrative/lines.ts` once it lands. */
  narrator?: Narrator;
}

export interface ResolveResult {
  /** Post-round player snapshot. Same length as input (DEAD players retained
   *  for history, never removed). Insertion order preserved. */
  players: PlayerState[];
  /** Time-tagged choreography. Always non-empty; first effect is
   *  ROUND_START. */
  effects: Effect[];
  /** Concatenated, newline-joined narration text for the round. Useful for
   *  sim CLI grep-able output. */
  narration: string;
  /** RPS sub-resolution, surfaced for tests + sim CSV. */
  rps: RpsResolution;
  /** True when ≤ 1 player remains alive. */
  isGameOver: boolean;
  /** PlayerId of the sole surviving player, or null on tie/multi-alive. */
  winnerId: PlayerId | null;
}

/**
 * Resolve one round. Pure: never mutates `state` or `inputs`.
 *
 * @param state    Players at the start of the round (alive + dead). Dead
 *                 players are filtered out of RPS but retained in the
 *                 returned `players` array unchanged.
 * @param round    1-based round counter. Used for narration prefixes and
 *                 round-stable variant selection.
 * @param inputs   choices: RPS throws keyed by playerId (DEAD entries
 *                 ignored). targets (optional): actor → loser pairing.
 * @param options  narrator override.
 */
export function resolveRound(
  state: ReadonlyArray<PlayerState>,
  round: number,
  inputs: RoundInputs,
  options: ResolveOptions = {},
): ResolveResult {
  const narrator = options.narrator ?? DEFAULT_NARRATOR;
  const players: PlayerState[] = state.map(clonePlayer);
  const effects: Effect[] = [];
  const narrationLines: string[] = [];

  effects.push({ type: 'ROUND_START', round, atMs: 0 });

  // Filter to alive players for RPS.
  const aliveById = new Map<PlayerId, PlayerState>();
  for (const p of players) if (p.stage !== 'DEAD') aliveById.set(p.id, p);

  // Build the choices map in input-player-order so winners[]/losers[] are
  // deterministic. We iterate `players` (the input-ordered snapshot) and
  // pull whatever they submitted, ignoring stale entries for DEAD players.
  const orderedChoices: Array<readonly [PlayerId, RpsChoice]> = [];
  for (const p of players) {
    if (p.stage === 'DEAD') continue;
    const c = inputs.choices[p.id];
    if (c === undefined) continue;
    orderedChoices.push([p.id, c]);
    p.lastChoice = c; // record on the cloned player for replays
  }

  const rps = resolveRps(orderedChoices);

  // ── REVEAL frame (FINAL_GOAL §H2) ─────────────────────────────────────
  // Emit one RPS_REVEAL effect carrying every alive player's throw so the
  // canvas can render glyphs above each station for the entire reveal
  // hold. We emit on every non-empty round (tie and non-tie). The empty
  // round path (no choices) skips the reveal — there is nothing to show.
  if (orderedChoices.length > 0) {
    effects.push({
      type: 'RPS_REVEAL',
      round,
      atMs: 0,
      durationMs: PHASE_T_REVEAL,
      throws: orderedChoices.map(([playerId, choice]) => ({ playerId, choice })),
    });
  }

  // ── Tie path ──────────────────────────────────────────────────────────
  if (rps.tie) {
    const reason = rps.reason as 'all-same' | 'all-equal' | 'empty';
    const text = narrator.tie(round, reason);
    effects.push({
      type: 'TIE_NARRATION',
      round,
      atMs: 0,
      durationMs: TIE_NARRATION_HOLD_MS,
      text,
      rpsReason: reason,
    });
    effects.push({
      type: 'NARRATION',
      round,
      atMs: 0,
      verb: '平',
      text,
    });
    narrationLines.push(text);
    return finalize(players, round, effects, narrationLines, rps);
  }

  // ── Action path ───────────────────────────────────────────────────────
  // RpsResolution guarantees winningChoice is defined when tie === false.
  effects.push({
    type: 'RPS_RESOLVED',
    round,
    atMs: 0,
    winners: [...rps.winners],
    losers: [...rps.losers],
    winningChoice: rps.winningChoice!,
    reason: rps.reason as 'two-way' | 'majority' | 'outlier',
  });

  // Emit the 6-phase timeline (always emitted on action rounds, regardless
  // of how many winner/loser pairings actually fire — the choreography is a
  // single shared timeline for the round). v6 §K2 dropped the trailing
  // RETURN beat so the actor lingers at the target's house.
  for (const { phase, atMs, durationMs } of PHASE_TIMELINE) {
    effects.push({ type: 'PHASE_START', round, phase, atMs, durationMs });
  }

  // Pair winners → losers in winner-input-order. Each loser can be claimed
  // at most once. Explicit targets in inputs.targets win; otherwise we pick
  // the first not-yet-claimed loser.
  //
  // NEW (FINAL_GOAL §H4): a winner whose own pre-round stage is
  // ALIVE_PANTS_DOWN may opt into the SELF action `PULL_OWN_PANTS_UP` by
  // setting `inputs.actions[winnerId] = 'PULL_OWN_PANTS_UP'`. That winner
  // does NOT consume a loser slot — losers remain available for the next
  // winner in iteration order.
  const claimed = new Set<PlayerId>();
  const targetInputs = inputs.targets ?? {};
  const actionInputs = inputs.actions ?? {};
  const pairings: Array<{ actor: PlayerId; target: PlayerId; kind: ActionKind }> = [];
  for (const actor of rps.winners) {
    const actorPlayer = players.find((p) => p.id === actor)!;
    const requestedAction = actionInputs[actor];

    // Self-action path (PULL_OWN_PANTS_UP). Eligibility: actor is currently
    // pants-down. Requires no loser slot; consumes nothing.
    if (
      requestedAction === 'PULL_OWN_PANTS_UP' &&
      actorPlayer.stage === 'ALIVE_PANTS_DOWN'
    ) {
      pairings.push({
        actor,
        target: actor, // self
        kind: 'PULL_OWN_PANTS_UP',
      });
      continue;
    }

    // Default loser-targeting path.
    let chosen: PlayerId | undefined;
    const requested = targetInputs[actor];
    if (
      requested !== undefined &&
      rps.losers.includes(requested) &&
      !claimed.has(requested)
    ) {
      chosen = requested;
    } else {
      chosen = rps.losers.find((l) => !claimed.has(l));
    }
    if (chosen === undefined) break;
    claimed.add(chosen);
    const targetPlayer = players.find((p) => p.id === chosen)!;
    pairings.push({
      actor,
      target: chosen,
      kind: defaultActionFor(targetPlayer.stage),
    });
  }

  // Emit ACTION + SET_STAGE + NARRATION for each pairing, then mutate the
  // cloned player snapshot.
  const atActionMs = PHASE_OFFSETS.PULL_PANTS;
  for (const pairing of pairings) {
    if (pairing.kind === 'NONE') continue;
    const actor = players.find((p) => p.id === pairing.actor)!;
    const target = players.find((p) => p.id === pairing.target)!;

    effects.push({
      type: 'ACTION',
      round,
      atMs: atActionMs,
      actor: actor.id,
      target: target.id,
      kind: pairing.kind,
    });

    if (pairing.kind === 'PULL_PANTS') {
      // Stage flip officializes after the shame hold so the renderer can
      // hold the reveal frame for SHAME_FRAME_HOLD_MS before mutating UI
      // state. Engine truth still updates here.
      target.stage = 'ALIVE_PANTS_DOWN';
      effects.push({
        type: 'SET_STAGE',
        round,
        atMs: atActionMs + SHAME_FRAME_HOLD_MS,
        target: target.id,
        stage: 'ALIVE_PANTS_DOWN',
      });
      const text = narrator.pullPants(actor.nickname, target.nickname, round);
      effects.push({
        type: 'NARRATION',
        round,
        atMs: atActionMs,
        verb: '扒',
        actor: actor.id,
        target: target.id,
        text,
      });
      narrationLines.push(text);
    } else if (pairing.kind === 'CHOP') {
      // CHOP: stage flip at STRIKE start (the swing connects).
      target.stage = 'DEAD';
      effects.push({
        type: 'SET_STAGE',
        round,
        atMs: PHASE_OFFSETS.STRIKE,
        target: target.id,
        stage: 'DEAD',
      });
      const text = narrator.chop(actor.nickname, target.nickname, round);
      effects.push({
        type: 'NARRATION',
        round,
        atMs: PHASE_OFFSETS.STRIKE,
        verb: '砍',
        actor: actor.id,
        target: target.id,
        text,
      });
      narrationLines.push(text);
    } else if (pairing.kind === 'PULL_OWN_PANTS_UP') {
      // Self-restore: actor === target, no losers affected. Winner's
      // stage flips ALIVE_PANTS_DOWN → ALIVE_CLOTHED at the same atMs as
      // a pull's stage flip (after the shame hold) — the UI gets the
      // same hold-and-reveal beat the pull-pants animation already uses.
      target.stage = 'ALIVE_CLOTHED';
      effects.push({
        type: 'SET_STAGE',
        round,
        atMs: atActionMs + SHAME_FRAME_HOLD_MS,
        target: target.id,
        stage: 'ALIVE_CLOTHED',
      });
      const text = narrator.pullOwnPantsUp(actor.nickname, round);
      effects.push({
        type: 'NARRATION',
        round,
        atMs: atActionMs,
        verb: '穿',
        actor: actor.id,
        target: target.id,
        text,
      });
      narrationLines.push(text);
    }
  }

  return finalize(players, round, effects, narrationLines, rps);
}

function finalize(
  players: PlayerState[],
  round: number,
  effects: Effect[],
  narrationLines: string[],
  rps: RpsResolution,
): ResolveResult {
  const alive = players.filter((p) => p.stage !== 'DEAD');
  const winnerId = alive.length === 1 ? alive[0]!.id : null;
  const isGameOver = alive.length <= 1;

  if (isGameOver) {
    // GAME_OVER fires at the end of the round timeline (REVEAL +
    // ACTION_TOTAL_MS) so the renderer's confetti burst lines up with
    // the final IMPACT beat rather than overlapping the reveal. v6 §K2
    // removed the RETURN beat, so IMPACT is now the closing phase.
    effects.push({
      type: 'GAME_OVER',
      round,
      atMs: ROUND_TOTAL_MS,
      winnerId,
    });
  }

  return {
    players,
    effects,
    narration: narrationLines.join('\n'),
    rps,
    isGameOver,
    winnerId,
  };
}

function clonePlayer(p: PlayerState): PlayerState {
  // Spread is shallow; PlayerState contains only primitives + optional
  // primitives, so this is sufficient. If types.ts grows nested fields, this
  // must grow with it.
  return { ...p };
}

function defaultActionFor(stage: PlayerState['stage']): ActionKind {
  if (stage === 'ALIVE_CLOTHED') return 'PULL_PANTS';
  if (stage === 'ALIVE_PANTS_DOWN') return 'CHOP';
  return 'NONE';
}
