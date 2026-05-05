// Iron bot — picks a single favorite shape on creation and mostly throws
// it. Behaves as a stubborn opponent that exploits players who try to be
// too clever. The deviation rate AND the deviation strategy are now both
// seed-derived so two `iron` bots in different rooms/seeds don't make
// counter's job trivial.
//
// The favorite shape is derived from the RNG's first value, which means
// the per-bot seed (deriveBotSeed) determines whether this iron is a
// rock, paper, or scissors iron. Two `iron` bots in the same room with
// different ids therefore favor different shapes.
//
// Why the params changed in S-334:
// The previous fixed deviation rate of 1/5 with uniform-random fallback
// was deterministically beatable: a `counter` bot would learn the
// favorite within ~3 rounds and then win 80% of head-to-head exchanges,
// producing the 11/50 strict-budget failures observed (seeds 7, 12, 15,
// 21, 22, 24, 30, 34, 39, 40, 41). Diversifying both the rate AND the
// fallback shape (counter-the-counter vs uniform random) breaks the
// equilibrium without making iron unrecognisable.

import { RPS_CHOICES, type RpsChoice } from '../rps.js';
import { hashString, pickOne, type Rng } from './seedRng.js';
import type { BotContext, BotStrategy } from './types.js';

const BEATEN_BY: Readonly<Record<RpsChoice, RpsChoice>> = {
  ROCK: 'PAPER',
  PAPER: 'SCISSORS',
  SCISSORS: 'ROCK',
};

/** Per-bot derived hyperparameters, cached on first decision call. */
interface IronParams {
  favorite: RpsChoice;
  /** 1 in N rounds, deviate. Lower N (3,4) makes iron less stubborn. */
  deviationDenominator: number;
  /**
   * Deviation flavour:
   *   - 'random'        : pick uniformly from the other two shapes
   *   - 'counter-counter' : assume the opponent is countering the favorite
   *                         and throw what beats THAT counter (i.e., throw
   *                         the shape that beats `BEATEN_BY[favorite]`)
   *
   * Mixing both flavours across the bot pool means a counter bot can't
   * settle on a stable exploit.
   */
  deviationMode: 'random' | 'counter-counter';
}

const DEVIATION_DENOMINATORS = [4, 5, 6] as const;
const DEVIATION_MODES = ['random', 'counter-counter', 'counter-counter'] as const;

// Per-bot favorite + params cache. Keyed by `selfId` so we don't recompute
// every round and so the favorite is stable across rounds for the same bot.
const paramsCache = new Map<string, IronParams>();

function paramsFor(selfId: string, rng: Rng): IronParams {
  let p = paramsCache.get(selfId);
  if (p === undefined) {
    p = {
      favorite: pickOne(rng, RPS_CHOICES),
      deviationDenominator: pickOne(rng, DEVIATION_DENOMINATORS),
      deviationMode: pickOne(rng, DEVIATION_MODES),
    };
    paramsCache.set(selfId, p);
  }
  return p;
}

export const ironStrategy: BotStrategy = {
  kind: 'iron',
  pickChoice(ctx: BotContext, rng: Rng): RpsChoice {
    const p = paramsFor(ctx.selfId, rng);
    // Endgame escape: in 1v1, iron's stubbornness causes long stalemates
    // when the opponent also locks (mirror, counter, or a coincidental
    // random streak). Random for 1v1 keeps the game terminating without
    // changing the strategy's identity in normal multi-player play.
    const aliveOpponents = ctx.players.filter(
      (pl) => pl.stage !== 'DEAD' && pl.id !== ctx.selfId,
    ).length;
    if (aliveOpponents <= 1) return pickOne(rng, RPS_CHOICES);
    // Tie-break escape: after a tie, iron's stubbornness is exactly what
    // contributed to the tie (everyone threw the favorite or the
    // counter-counter). Randomize once to shake the lock; the favorite
    // resumes next round.
    const lastTieEntry = ctx.history[ctx.history.length - 1];
    if (lastTieEntry !== undefined && lastTieEntry.winningChoice === undefined) {
      // After two-or-more consecutive ties: coordinated exclude-one-shape
      // tie-break (see counter.ts). Single ties just randomize.
      let consecutiveTies = 0;
      for (let i = ctx.history.length - 1; i >= 0; i--) {
        if (ctx.history[i]!.winningChoice === undefined) consecutiveTies += 1;
        else break;
      }
      if (consecutiveTies >= 2) {
        const exclude = ctx.history.length % RPS_CHOICES.length;
        const allowed: RpsChoice[] = [];
        for (let i = 0; i < RPS_CHOICES.length; i++) {
          if (i !== exclude) allowed.push(RPS_CHOICES[i]!);
        }
        const idx = hashString(ctx.selfId) % allowed.length;
        return allowed[idx]!;
      }
      return pickOne(rng, RPS_CHOICES);
    }
    if (Math.floor(rng() * p.deviationDenominator) === 0) {
      if (p.deviationMode === 'counter-counter') {
        // The counter-of-the-counter: a counter bot will throw
        // BEATEN_BY[favorite] against us; we throw the shape that beats
        // THAT, which is BEATEN_BY[BEATEN_BY[favorite]].
        return BEATEN_BY[BEATEN_BY[p.favorite]];
      }
      const others = RPS_CHOICES.filter((c) => c !== p.favorite);
      return pickOne(rng, others);
    }
    return p.favorite;
  },
};

/** Test/sim helper: clear the favorite cache between sim runs so seeded
 *  reproducibility holds across multiple invocations in the same process. */
export function _resetIronFavorites(): void {
  paramsCache.clear();
}
