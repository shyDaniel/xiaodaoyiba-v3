// Random bot — uniform over {ROCK, PAPER, SCISSORS} per round.
//
// Baseline strategy. Acts as the control in mixed-bot evaluations: any
// "smart" strategy that doesn't outperform `random` over hundreds of rounds
// is not actually smart.

import { RPS_CHOICES, type RpsChoice } from '../rps.js';
import { pickOne, type Rng } from './seedRng.js';
import type { BotContext, BotStrategy } from './types.js';

export const randomStrategy: BotStrategy = {
  kind: 'random',
  pickChoice(_ctx: BotContext, rng: Rng): RpsChoice {
    return pickOne(rng, RPS_CHOICES);
  },
};
