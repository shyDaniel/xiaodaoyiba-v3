// Bot strategy contract.
//
// A bot strategy is a pure function: (context, rng) → RpsChoice. It never
// reads global state, never touches the clock, never mutates the round
// engine. The sim CLI and the live server hand it the same shape of input,
// so a bot's behavior is identical in both environments.

import type { RpsChoice } from '../rps.js';
import type { PlayerState } from '../types.js';
import type { Rng } from './seedRng.js';

/**
 * Lightweight read-only history of past rounds, given to bots that want
 * to react to opponents (counter, mirror). Each entry is the throw map
 * from a single completed round, in player-id-order.
 *
 * NOTE: dead players' last throws stay in history. Strategies that care
 * should filter on the live `players` snapshot.
 */
export interface RoundHistoryEntry {
  /** 1-based round number. */
  round: number;
  /** What every alive-at-the-time player threw, by playerId. */
  choices: Readonly<Record<string, RpsChoice>>;
  /** Winning shape, or undefined for tie rounds. */
  winningChoice?: RpsChoice;
}

/**
 * Per-decision context handed to the bot. The bot is `selfId` and is
 * choosing for round `round`. `players` is the alive-at-round-start
 * snapshot. `history` is rounds 1..round-1 in chronological order.
 */
export interface BotContext {
  selfId: string;
  round: number;
  players: ReadonlyArray<PlayerState>;
  history: ReadonlyArray<RoundHistoryEntry>;
}

/** A named strategy. `kind` doubles as the registry key + sim CLI flag value. */
export interface BotStrategy {
  readonly kind: BotKind;
  pickChoice(ctx: BotContext, rng: Rng): RpsChoice;
}

export type BotKind = 'counter' | 'random' | 'iron' | 'mirror';
