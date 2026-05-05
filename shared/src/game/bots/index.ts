// Bot strategy registry + diversifier.
//
// FINAL_GOAL §A3 mandates that when N bots are added to a room, their
// strategies are diversified by default — round-robin over the registry,
// not all-the-same. The headless sim CLI uses the same diversifier so
// `--bots counter,random,iron,mirror` always produces one of each.

import type { BotKind, BotStrategy } from './types.js';
import { counterStrategy, _resetCounterParams } from './counter.js';
import { ironStrategy, _resetIronFavorites } from './iron.js';
import { mirrorStrategy, _resetMirrorParams } from './mirror.js';
import { randomStrategy } from './random.js';

export type { BotContext, BotKind, BotStrategy, RoundHistoryEntry } from './types.js';
export {
  deriveBotSeed,
  hashString,
  mulberry32,
  pickOne,
  seededRng,
  splitmix32,
  type Rng,
} from './seedRng.js';
export { counterStrategy, _resetCounterParams } from './counter.js';
export { ironStrategy, _resetIronFavorites } from './iron.js';
export { mirrorStrategy, _resetMirrorParams } from './mirror.js';
export { randomStrategy } from './random.js';

/** All registered strategies, in the canonical round-robin order from §A3. */
export const BOT_STRATEGIES: ReadonlyArray<BotStrategy> = [
  counterStrategy,
  randomStrategy,
  ironStrategy,
  mirrorStrategy,
];

const STRATEGY_BY_KIND: Readonly<Record<BotKind, BotStrategy>> = {
  counter: counterStrategy,
  random: randomStrategy,
  iron: ironStrategy,
  mirror: mirrorStrategy,
};

/** Look up a strategy by its CLI / lobby `kind` string. Throws on unknown. */
export function getBotStrategy(kind: BotKind): BotStrategy {
  const s = STRATEGY_BY_KIND[kind];
  if (!s) throw new Error(`unknown bot strategy: ${kind}`);
  return s;
}

/** Validate a CLI string is a known bot kind. */
export function isBotKind(s: string): s is BotKind {
  return s === 'counter' || s === 'random' || s === 'iron' || s === 'mirror';
}

/**
 * Pick a strategy round-robin from the registry by index. Used when the
 * lobby auto-fills bots ("加一个机器人") — successive calls cycle through
 * counter → random → iron → mirror → counter → … so two bots in the same
 * room always have different strategies whenever ≥ 2 strategies are
 * registered.
 */
export function pickStrategyForIndex(index: number): BotStrategy {
  const n = BOT_STRATEGIES.length;
  const i = ((index % n) + n) % n;
  return BOT_STRATEGIES[i]!;
}

/**
 * Reset any per-bot caches that strategies hold across rounds. Called by
 * the sim CLI between runs so a `--seed`-controlled invocation is fully
 * reproducible regardless of process state.
 */
export function resetBotCaches(): void {
  _resetCounterParams();
  _resetIronFavorites();
  _resetMirrorParams();
}
