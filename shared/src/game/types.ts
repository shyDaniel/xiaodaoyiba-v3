// Core game state types shared by engine, sim, server, and client.
//
// Kept intentionally minimal: this is the data the pure resolveRound() function
// reads and writes. Anything that needs more (Socket.IO snapshots, lobby
// metadata, host flags, characters/abilities) layers on top in higher tiers
// without changing the engine signature.
//
// v2 deliberately drops v1's `characterId` / `buffs` / `houseHp` from the core
// state — the FINAL_GOAL spec for v2 collapses elimination to pants-down-then-
// chop and treats characters as visual identity (deterministic from playerId
// hash, see FINAL_GOAL §C9). If/when buffs come back, they'll come back as
// their own module rather than entangling the engine.

// `PlayerId` and `RpsChoice` are canonical in `./rps.js`. This file imports
// them for its own field types but does NOT re-export them — the package
// barrel (`game/index.ts`) re-exports each symbol exactly once from its
// canonical home.
import type { PlayerId, RpsChoice } from './rps.js';

/**
 * Lifecycle stage of a player within a single game.
 *  - ALIVE_CLOTHED:    healthy, pants up. Default action against this target
 *                      is PULL_PANTS.
 *  - ALIVE_PANTS_DOWN: shamed but still in the game. Default action against
 *                      this target is CHOP. The "shame frame" persists across
 *                      rounds (FINAL_GOAL §C7) — the renderer must keep the
 *                      red briefs visible until the player dies or wins.
 *  - DEAD:             eliminated; no longer participates in RPS or actions.
 */
export type PlayerStage = 'ALIVE_CLOTHED' | 'ALIVE_PANTS_DOWN' | 'DEAD';

/**
 * What an actor (round winner) does to a target (round loser).
 *  - PULL_PANTS:        clothed → pants_down. The 扒裤衩 reveal.
 *  - CHOP:              pants_down → dead. The 咔嚓 finisher.
 *  - PULL_OWN_PANTS_UP: SELF action. Winner whose own stage is
 *                       ALIVE_PANTS_DOWN restores themselves to
 *                       ALIVE_CLOTHED instead of acting on a loser
 *                       (FINAL_GOAL §H4). actor === target.
 *  - NONE:              no-op (used when the engine cannot pick a
 *                       valid pairing).
 */
export type ActionKind = 'PULL_PANTS' | 'CHOP' | 'PULL_OWN_PANTS_UP' | 'NONE';

/**
 * 6-phase round timeline (FINAL_GOAL §A5/§B4/§H2/§K2). The engine tags
 * each round with its phase boundaries so sim, server, and client all
 * advance the same timeline. Names match timing.ts constants 1:1. REVEAL
 * is the pre-action hold during which every alive player's RPS choice is
 * rendered as a large glyph above their station so a first-time viewer
 * can scan the field and count the distribution before the rush begins
 * (§H2). The RETURN beat was removed in v6 (§K2): the actor stays at
 * the target's house through IMPACT and the next round's PREP teleports
 * them back home.
 */
export type ActionPhase =
  | 'REVEAL'
  | 'PREP'
  | 'RUSH'
  | 'PULL_PANTS'
  | 'STRIKE'
  | 'IMPACT';

/**
 * A player as the engine sees it. Layered systems (server/Room, client/store)
 * may carry richer state but they MUST embed a PlayerState compatible shape
 * for the engine to mutate-by-clone.
 */
export interface PlayerState {
  id: PlayerId;
  /** Display name. Engine never reads this for logic; it appears only in
   *  narration. */
  nickname: string;
  stage: PlayerStage;
  /** True for server-driven AI players. Engine doesn't use this; it's here
   *  so callers can keep humans/bots in one list. */
  isBot?: boolean;
  /** Last RPS submitted in the most recent round. Optional: engine never
   *  reads it, but populating it is convenient for replays/UI. */
  lastChoice?: RpsChoice;
}

/**
 * Per-round inputs the engine consumes. `choices` covers everyone alive at
 * round start; `targets` lets a winning actor explicitly pick a loser. If a
 * winner doesn't supply a target, the engine picks the first not-yet-claimed
 * loser in winners-iteration order.
 */
export interface RoundInputs {
  choices: Record<PlayerId, RpsChoice>;
  /** Optional: actor → target mapping. Targets must be in the losers set,
   *  EXCEPT when paired with `actions[actor] === 'PULL_OWN_PANTS_UP'` —
   *  that self-action implies actor===target and the engine accepts the
   *  actor as their own target without consulting the losers list. */
  targets?: Record<PlayerId, PlayerId>;
  /** Optional: actor → action override (FINAL_GOAL §H3/§H4). Lets a
   *  winner pick `'PULL_OWN_PANTS_UP'` when their stage is
   *  ALIVE_PANTS_DOWN. Engine validates eligibility and falls back to
   *  the default action (driven by target stage) if invalid. */
  actions?: Record<PlayerId, ActionKind>;
}
