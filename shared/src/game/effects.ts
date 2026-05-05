// Effect[] — the choreography protocol.
//
// What this is
// ------------
// `resolveRound()` produces a flat, ordered list of `Effect` objects describing
// EVERYTHING that happens in a round, in the order it happens, annotated with
// timing. Three independent consumers read this list:
//
//   1. The headless sim CLI ignores time (just inspects the events).
//   2. The Socket.IO server emits the list to all clients via `round:reveal`.
//   3. The PixiJS EffectPlayer on the client schedules sprite/camera/audio
//      cues by reading `atMs` and `durationMs` and playing them in real time.
//
// All three see the SAME canonical timeline — one source of truth.
//
// Timing semantics
// ----------------
// The 5-phase action timeline (PREP → RUSH → PULL_PANTS → STRIKE → IMPACT)
// totals exactly ACTION_TOTAL_MS by spec; the full round (REVEAL + action)
// totals ROUND_TOTAL_MS. Each `PHASE_START` effect carries `atMs` (offset
// from the round's t=0) and `durationMs` taken literally from `timing.ts`.
// ROUND_START emits at atMs=0; for a tie round, the engine emits
// TIE_NARRATION with `durationMs = TIE_NARRATION_HOLD_MS` and no PHASE_*
// events. For an action round, PHASE_START events emit at REVEAL=0,
// PREP=1500, RUSH=1800, PULL_PANTS=2400, STRIKE=3300, IMPACT=3900; ACTION
// emits at PULL_PANTS=2400 and STAGE_CHANGE emits at STRIKE=3300 for chops
// or at PULL_PANTS + SHAME_FRAME_HOLD_MS for pants_down.
//
// v6 §K2 dropped the trailing RETURN beat: the actor stays at the target's
// house through IMPACT and is teleported home by the next round's PREP.
//
// SET_STAGE is the only effect that mutates persistent player state; the
// rest are advisory (sound/animation triggers). Consumers fold SET_STAGE
// into their own player snapshots if they want — `resolveRound()` already
// hands back an updated `players` array, so server-side this is purely
// informational.

import type { PlayerId, RpsChoice } from './rps.js';
import type { ActionKind, ActionPhase, PlayerStage } from './types.js';

/** Discriminated union covering every choreographed beat in a round. */
export type Effect =
  | RoundStartEffect
  | TieNarrationEffect
  | RpsRevealEffect
  | RpsResolvedEffect
  | PhaseStartEffect
  | ActionEffect
  | SetStageEffect
  | NarrationEffect
  | GameOverEffect;

/** Round wrapper. `atMs: 0` always. */
export interface RoundStartEffect {
  type: 'ROUND_START';
  round: number;
  atMs: 0;
}

/** Emitted only on a tie round. The narration text is a single colloquial
 *  Chinese line drawn from the variant pool by upstream code. */
export interface TieNarrationEffect {
  type: 'TIE_NARRATION';
  round: number;
  atMs: 0;
  durationMs: number;
  text: string;
  /** Echoes resolveRps().reason so consumers can pick visuals (e.g. all-equal
   *  vs all-same vs empty). */
  rpsReason: 'all-same' | 'all-equal' | 'empty';
}

/** Emitted on a non-tie round, immediately after ROUND_START. Carries the
 *  full RPS resolution so the BattleLog can render `R{N}.rps` lines without
 *  needing the engine state separately. */
export interface RpsResolvedEffect {
  type: 'RPS_RESOLVED';
  round: number;
  atMs: 0;
  winners: PlayerId[];
  losers: PlayerId[];
  winningChoice: 'ROCK' | 'PAPER' | 'SCISSORS';
  reason: 'two-way' | 'majority' | 'outlier';
}

/**
 * Emitted on EVERY non-empty RPS round (tie or non-tie) at atMs=0 so
 * consumers can render every alive player's throw simultaneously above
 * their station for the duration of the REVEAL phase (FINAL_GOAL §H2).
 *
 * `throws` carries one (playerId, choice) pair per alive player who
 * submitted a throw, in player-iteration order. Holding the reveal frame
 * for ≥ PHASE_T_REVEAL ms is the single feature that lets a first-time
 * viewer count the distribution before the action timeline starts.
 */
export interface RpsRevealEffect {
  type: 'RPS_REVEAL';
  round: number;
  atMs: 0;
  durationMs: number;
  throws: Array<{ playerId: PlayerId; choice: RpsChoice }>;
}

/** A phase boundary inside the action timeline. Six fire per non-tie round,
 *  in order, with `atMs` matching the timing.ts cumulative offsets. */
export interface PhaseStartEffect {
  type: 'PHASE_START';
  round: number;
  phase: ActionPhase;
  atMs: number;
  durationMs: number;
}

/** Engine-level "this winner does this thing to this loser" record. Fires
 *  at the start of PULL_PANTS (atMs=900). One per actor/target pairing. */
export interface ActionEffect {
  type: 'ACTION';
  round: number;
  atMs: number;
  actor: PlayerId;
  target: PlayerId;
  kind: ActionKind;
}

/** Persistent state mutation: target's lifecycle stage changes. Fires at
 *  the moment the change is "official" in choreography terms (after the
 *  shame hold for PULL_PANTS, at STRIKE start for CHOP). */
export interface SetStageEffect {
  type: 'SET_STAGE';
  round: number;
  atMs: number;
  target: PlayerId;
  stage: PlayerStage;
}

/** A line of human-readable Chinese for the BattleLog. Every action emits
 *  one of these; ties also emit one (via TIE_NARRATION + a NARRATION mirror
 *  for log uniformity). The engine fills `text` from a templated narrator;
 *  tests assert `text.length > 0` rather than exact strings. */
export interface NarrationEffect {
  type: 'NARRATION';
  round: number;
  atMs: number;
  /** Stable hash key for color-coding badges in the BattleLog.
   *  穿 — winner self-restored from ALIVE_PANTS_DOWN to ALIVE_CLOTHED
   *  via PULL_OWN_PANTS_UP (FINAL_GOAL §H7). */
  verb: '扒' | '砍' | '闪' | '平' | '死' | '穿';
  actor?: PlayerId;
  target?: PlayerId;
  text: string;
}

/** Final round-cap effect when ≤ 1 player remains alive. */
export interface GameOverEffect {
  type: 'GAME_OVER';
  round: number;
  atMs: number;
  winnerId: PlayerId | null;
}

/**
 * Type-safe filter helper used by tests + the EffectPlayer to narrow the
 * union without writing inline `e.type === 'X'` everywhere. Generic on the
 * literal `type` so the return type is correctly narrowed.
 */
export function effectsOfType<T extends Effect['type']>(
  effects: readonly Effect[],
  type: T,
): Array<Extract<Effect, { type: T }>> {
  return effects.filter((e): e is Extract<Effect, { type: T }> => e.type === type);
}
