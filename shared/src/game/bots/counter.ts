// Counter bot — throws what would beat the most-frequent shape an opponent
// has thrown so far. On the first round (no history yet) it picks
// uniformly at random. Adds a seed-derived chance of throwing randomly to
// avoid being itself read-as-a-pattern, AND uses a seed-derived lookback
// window so two `counter` bots in different rooms (or different runs)
// don't lock onto the same equilibrium with the same opponent set.
//
// The per-bot parameters (noise rate, lookback depth, recency weight) are
// drawn from the bot's own seeded rng on first call and cached by selfId.
// This is what FINAL_GOAL §A2 means by "diversified bot strategies": even
// two `counter` bots play differently because their seeds drive different
// hyperparameters, breaking the symmetry that produced 22% strict-budget
// failures across seeds 0..49.

import { RPS_CHOICES, type RpsChoice } from '../rps.js';
import { hashString, pickOne, type Rng } from './seedRng.js';
import type { BotContext, BotStrategy } from './types.js';

const BEATEN_BY: Readonly<Record<RpsChoice, RpsChoice>> = {
  // The shape that BEATS the key. e.g. ROCK is beaten by PAPER.
  ROCK: 'PAPER',
  PAPER: 'SCISSORS',
  SCISSORS: 'ROCK',
};

/** Per-bot derived hyperparameters, cached on first decision call. */
interface CounterParams {
  /** 1 in N rounds, throw uniformly random. Higher N → less noise. */
  noiseDenominator: number;
  /** How many trailing rounds to weight; older rounds count 1. */
  lookback: number;
  /** Multiplicative weight applied to the most-recent round. */
  recencyWeight: number;
}

const NOISE_DENOMINATORS = [4, 5, 6, 7] as const;
const LOOKBACKS = [1, 2, 3, 5] as const;
const RECENCY_WEIGHTS = [2, 3, 4, 5] as const;

const paramsCache = new Map<string, CounterParams>();

function paramsFor(selfId: string, rng: Rng): CounterParams {
  let p = paramsCache.get(selfId);
  if (p === undefined) {
    p = {
      noiseDenominator: pickOne(rng, NOISE_DENOMINATORS),
      lookback: pickOne(rng, LOOKBACKS),
      recencyWeight: pickOne(rng, RECENCY_WEIGHTS),
    };
    paramsCache.set(selfId, p);
  }
  return p;
}

export const counterStrategy: BotStrategy = {
  kind: 'counter',
  pickChoice(ctx: BotContext, rng: Rng): RpsChoice {
    const p = paramsFor(ctx.selfId, rng);
    if (ctx.history.length === 0) return pickOne(rng, RPS_CHOICES);
    // Endgame escape: in 1v1 (only one live opponent left), the most-frequent
    // history signal is dominated by a tiny sample — counter starts to lock
    // onto the same shape its opponent did last and they tie repeatedly.
    // Falling back to uniform random for 1v1 prevents the long ROCK-ROCK
    // stalemates that drove tie_rate above the §A2 budget on seeds 16, 25.
    const aliveOpponents = ctx.players.filter(
      (pl) => pl.stage !== 'DEAD' && pl.id !== ctx.selfId,
    ).length;
    if (aliveOpponents <= 1) return pickOne(rng, RPS_CHOICES);
    // Tie-break escape: if the most recent round was a tie, the bot pool
    // converged on a single shape (or evenly across all three). Repeating
    // the same dominant-shape lookup will reproduce the same throw and
    // re-tie. Randomizing on the round after a tie costs us nothing
    // strategically (the opponent had no decisive signal to learn from
    // either) and breaks tie-loop clusters that pushed seeds 2, 16 above
    // the §A2 tie-rate budget.
    const lastEntry = ctx.history[ctx.history.length - 1];
    if (lastEntry !== undefined && lastEntry.winningChoice === undefined) {
      // After two-or-more consecutive ties, switch to a coordinated
      // tie-break: exclude one of the three RPS shapes (rotated by round
      // number) so the bot pool can never produce an all-different
      // three-way tie. Within the remaining two shapes, selfId-hash picks
      // which one. After a single tie we just randomize, which is enough
      // most of the time and preserves tactical surprise.
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

    // Count opponent throws over the last `lookback` rounds, weighting the
    // most-recent round by `recencyWeight` so the bot adapts quickly without
    // ignoring earlier signal entirely.
    const counts: Record<RpsChoice, number> = { ROCK: 0, PAPER: 0, SCISSORS: 0 };
    const lastIdx = ctx.history.length - 1;
    const startIdx = Math.max(0, lastIdx - p.lookback + 1);
    for (let i = startIdx; i <= lastIdx; i++) {
      const entry = ctx.history[i]!;
      const weight = i === lastIdx ? p.recencyWeight : 1;
      for (const [pid, choice] of Object.entries(entry.choices)) {
        if (pid === ctx.selfId) continue;
        counts[choice] += weight;
      }
    }

    // Find the most-thrown opponent shape; ties broken by canonical order.
    let dominant: RpsChoice = 'ROCK';
    let best = -1;
    for (const c of RPS_CHOICES) {
      if (counts[c] > best) {
        best = counts[c];
        dominant = c;
      }
    }
    return BEATEN_BY[dominant];
  },
};

/** Test/sim helper: clear the params cache between sim runs so seeded
 *  reproducibility holds across multiple invocations in the same process. */
export function _resetCounterParams(): void {
  paramsCache.clear();
}
