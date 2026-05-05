// Mirror bot — copies whatever the most recent winning shape was. If the
// last round was a tie or the first round, picks randomly. Tends to
// converge with other mirrors which is why we deliberately diversify
// strategies via the registry.
//
// S-334 made the noise rate AND the mirror flavour seed-derived so two
// `mirror` bots in different rooms/seeds don't converge. The 'beats-winner'
// flavour throws the shape that BEATS the last winning shape — useful when
// counter bots are also chasing the winner; mirror-beats-winner pre-empts
// them. The 'follow-winner' flavour is the classic v1 behavior.

import { RPS_CHOICES, type RpsChoice } from '../rps.js';
import { hashString, pickOne, type Rng } from './seedRng.js';
import type { BotContext, BotStrategy } from './types.js';

const BEATEN_BY: Readonly<Record<RpsChoice, RpsChoice>> = {
  ROCK: 'PAPER',
  PAPER: 'SCISSORS',
  SCISSORS: 'ROCK',
};

interface MirrorParams {
  /** 1 in N rounds, deviate randomly to avoid being trivially countered. */
  noiseDenominator: number;
  /** 'follow-winner' = mirror the winner, 'beats-winner' = throw what beats it. */
  flavour: 'follow-winner' | 'beats-winner';
}

const NOISE_DENOMINATORS = [4, 5, 6, 7] as const;
const FLAVOURS = ['follow-winner', 'beats-winner'] as const;

const paramsCache = new Map<string, MirrorParams>();

function paramsFor(selfId: string, rng: Rng): MirrorParams {
  let p = paramsCache.get(selfId);
  if (p === undefined) {
    p = {
      noiseDenominator: pickOne(rng, NOISE_DENOMINATORS),
      flavour: pickOne(rng, FLAVOURS),
    };
    paramsCache.set(selfId, p);
  }
  return p;
}

export const mirrorStrategy: BotStrategy = {
  kind: 'mirror',
  pickChoice(ctx: BotContext, rng: Rng): RpsChoice {
    const p = paramsFor(ctx.selfId, rng);
    if (ctx.history.length === 0) return pickOne(rng, RPS_CHOICES);
    // Endgame escape: in 1v1, mirror's "follow last winner" can lock-step
    // with the opponent and produce same-shape ties indefinitely. Random
    // for 1v1 keeps the game terminating cleanly.
    const aliveOpponents = ctx.players.filter(
      (pl) => pl.stage !== 'DEAD' && pl.id !== ctx.selfId,
    ).length;
    if (aliveOpponents <= 1) return pickOne(rng, RPS_CHOICES);
    // Tie-break escape: after a tie, mirror's "follow last winner" would
    // happily re-throw the previous winning shape (which everyone already
    // converged on to produce the tie). Randomize once to break the lock.
    const lastEntry = ctx.history[ctx.history.length - 1];
    if (lastEntry !== undefined && lastEntry.winningChoice === undefined) {
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
    if (Math.floor(rng() * p.noiseDenominator) === 0) return pickOne(rng, RPS_CHOICES);

    // Walk back from latest to earliest looking for the last decisive round.
    for (let i = ctx.history.length - 1; i >= 0; i--) {
      const w = ctx.history[i]!.winningChoice;
      if (w !== undefined) {
        return p.flavour === 'beats-winner' ? BEATEN_BY[w] : w;
      }
    }
    return pickOne(rng, RPS_CHOICES);
  },
};

/** Test/sim helper: clear the params cache between sim runs so seeded
 *  reproducibility holds across multiple invocations in the same process. */
export function _resetMirrorParams(): void {
  paramsCache.clear();
}
