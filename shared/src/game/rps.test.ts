// Truth-table tests for resolveRps over the 1/2/3-distinct × 2/3/4/5/6-player
// matrix. The v1 bug — `unique.size !== 2 → tie` — is the regression we
// guard against; every "all three shapes thrown" case here MUST produce
// a non-tie outcome unless the counts are pathologically equal.

import { describe, expect, it } from 'vitest';
import { resolveRps, RPS_CHOICES, type PlayerId, type RpsChoice } from './rps.js';

/** Helper: build a Record<PlayerId, RpsChoice> from an array of choices.
 *  Player ids are p0, p1, p2, … in order. */
function room(choices: RpsChoice[]): Record<PlayerId, RpsChoice> {
  const out: Record<PlayerId, RpsChoice> = {};
  choices.forEach((c, i) => {
    out[`p${i}`] = c;
  });
  return out;
}

describe('resolveRps — sanity', () => {
  it('exports the canonical shape order', () => {
    expect(RPS_CHOICES).toEqual(['ROCK', 'PAPER', 'SCISSORS']);
  });

  it('handles empty input as a degenerate tie', () => {
    const r = resolveRps({});
    expect(r.tie).toBe(true);
    expect(r.reason).toBe('empty');
    expect(r.winners).toEqual([]);
    expect(r.losers).toEqual([]);
  });
});

describe('resolveRps — 1 distinct shape (always tie)', () => {
  for (const n of [2, 3, 4, 5, 6]) {
    for (const shape of RPS_CHOICES) {
      it(`${n} players all throwing ${shape} → tie (all-same)`, () => {
        const r = resolveRps(room(Array.from({ length: n }, () => shape)));
        expect(r.tie).toBe(true);
        expect(r.reason).toBe('all-same');
        expect(r.winners).toEqual([]);
        expect(r.losers).toEqual([]);
        expect(r.winningChoice).toBeUndefined();
      });
    }
  }
});

describe('resolveRps — 2 distinct shapes (classical RPS)', () => {
  // 2 players: every adjacent pair across the 3 shapes.
  it('2 players: ROCK vs SCISSORS → ROCK wins', () => {
    const r = resolveRps(room(['ROCK', 'SCISSORS']));
    expect(r.tie).toBe(false);
    expect(r.reason).toBe('two-way');
    expect(r.winningChoice).toBe('ROCK');
    expect(r.winners).toEqual(['p0']);
    expect(r.losers).toEqual(['p1']);
  });

  it('2 players: SCISSORS vs PAPER → SCISSORS wins', () => {
    const r = resolveRps(room(['PAPER', 'SCISSORS']));
    expect(r.tie).toBe(false);
    expect(r.winningChoice).toBe('SCISSORS');
    expect(r.winners).toEqual(['p1']);
    expect(r.losers).toEqual(['p0']);
  });

  it('2 players: PAPER vs ROCK → PAPER wins', () => {
    const r = resolveRps(room(['ROCK', 'PAPER']));
    expect(r.tie).toBe(false);
    expect(r.winningChoice).toBe('PAPER');
    expect(r.winners).toEqual(['p1']);
    expect(r.losers).toEqual(['p0']);
  });

  // 3-6 players, 2 shapes, varying splits.
  it('3 players: 2 ROCK + 1 SCISSORS → ROCK group wins', () => {
    const r = resolveRps(room(['ROCK', 'ROCK', 'SCISSORS']));
    expect(r.tie).toBe(false);
    expect(r.winningChoice).toBe('ROCK');
    expect(r.winners).toEqual(['p0', 'p1']);
    expect(r.losers).toEqual(['p2']);
  });

  it('3 players: 1 ROCK + 2 PAPER → PAPER group wins', () => {
    const r = resolveRps(room(['ROCK', 'PAPER', 'PAPER']));
    expect(r.winningChoice).toBe('PAPER');
    expect(r.winners).toEqual(['p1', 'p2']);
    expect(r.losers).toEqual(['p0']);
  });

  it('4 players: 2 PAPER + 2 SCISSORS → SCISSORS wins (cuts paper)', () => {
    const r = resolveRps(room(['PAPER', 'SCISSORS', 'PAPER', 'SCISSORS']));
    expect(r.winningChoice).toBe('SCISSORS');
    expect(r.winners).toEqual(['p1', 'p3']);
    expect(r.losers).toEqual(['p0', 'p2']);
  });

  it('5 players: 3 ROCK + 2 PAPER → PAPER wins (covers rock)', () => {
    const r = resolveRps(room(['ROCK', 'ROCK', 'ROCK', 'PAPER', 'PAPER']));
    expect(r.winningChoice).toBe('PAPER');
    expect(r.winners).toEqual(['p3', 'p4']);
    expect(r.losers).toEqual(['p0', 'p1', 'p2']);
  });

  it('6 players: 4 SCISSORS + 2 ROCK → ROCK wins (smashes scissors) even though scissors is the majority shape', () => {
    // Crucial: in 2-way, the rule is "winning shape beats losing shape",
    // NOT majority. ROCK > SCISSORS regardless of headcount.
    const r = resolveRps(room(['SCISSORS', 'SCISSORS', 'SCISSORS', 'SCISSORS', 'ROCK', 'ROCK']));
    expect(r.tie).toBe(false);
    expect(r.winningChoice).toBe('ROCK');
    expect(r.winners).toEqual(['p4', 'p5']);
    expect(r.losers).toEqual(['p0', 'p1', 'p2', 'p3']);
  });
});

describe('resolveRps — 3 distinct shapes (the v1 bug zone)', () => {
  // The v1 bug: ANY of these would have been forced into a tie. Each test
  // here MUST produce a non-tie outcome (or, where all three counts are
  // equal, a documented tie with reason='all-equal' — never the bogus
  // unique.size!==2 tie).

  it('3 players: 1R + 1P + 1S (each unique) → all-equal tie', () => {
    const r = resolveRps(room(['ROCK', 'PAPER', 'SCISSORS']));
    expect(r.tie).toBe(true);
    expect(r.reason).toBe('all-equal');
    expect(r.winners).toEqual([]);
    expect(r.losers).toEqual([]);
  });

  it('4 players: 2R + 1P + 1S → ROCK majority wins', () => {
    const r = resolveRps(room(['ROCK', 'ROCK', 'PAPER', 'SCISSORS']));
    expect(r.tie).toBe(false);
    expect(r.reason).toBe('majority');
    expect(r.winningChoice).toBe('ROCK');
    expect(r.winners).toEqual(['p0', 'p1']);
    expect(r.losers).toEqual(['p2', 'p3']);
  });

  it('4 players: 1R + 2P + 1S → PAPER majority wins', () => {
    const r = resolveRps(room(['ROCK', 'PAPER', 'PAPER', 'SCISSORS']));
    expect(r.tie).toBe(false);
    expect(r.reason).toBe('majority');
    expect(r.winningChoice).toBe('PAPER');
    expect(r.winners).toEqual(['p1', 'p2']);
    expect(r.losers).toEqual(['p0', 'p3']);
  });

  it('4 players: 1R + 1P + 2S → SCISSORS majority wins', () => {
    const r = resolveRps(room(['ROCK', 'PAPER', 'SCISSORS', 'SCISSORS']));
    expect(r.tie).toBe(false);
    expect(r.reason).toBe('majority');
    expect(r.winningChoice).toBe('SCISSORS');
    expect(r.winners).toEqual(['p2', 'p3']);
    expect(r.losers).toEqual(['p0', 'p1']);
  });

  it('5 players: 2R + 2P + 1S → SCISSORS lone-outlier wins', () => {
    const r = resolveRps(room(['ROCK', 'ROCK', 'PAPER', 'PAPER', 'SCISSORS']));
    expect(r.tie).toBe(false);
    expect(r.reason).toBe('outlier');
    expect(r.winningChoice).toBe('SCISSORS');
    expect(r.winners).toEqual(['p4']);
    expect(r.losers).toEqual(['p0', 'p1', 'p2', 'p3']);
  });

  it('5 players: 2R + 1P + 2S → PAPER lone-outlier wins', () => {
    const r = resolveRps(room(['ROCK', 'ROCK', 'PAPER', 'SCISSORS', 'SCISSORS']));
    expect(r.tie).toBe(false);
    expect(r.reason).toBe('outlier');
    expect(r.winningChoice).toBe('PAPER');
    expect(r.winners).toEqual(['p2']);
    expect(r.losers).toEqual(['p0', 'p1', 'p3', 'p4']);
  });

  it('5 players: 1R + 2P + 2S → ROCK lone-outlier wins', () => {
    const r = resolveRps(room(['ROCK', 'PAPER', 'PAPER', 'SCISSORS', 'SCISSORS']));
    expect(r.tie).toBe(false);
    expect(r.reason).toBe('outlier');
    expect(r.winningChoice).toBe('ROCK');
    expect(r.winners).toEqual(['p0']);
    expect(r.losers).toEqual(['p1', 'p2', 'p3', 'p4']);
  });

  it('5 players: 3R + 1P + 1S → ROCK majority wins', () => {
    const r = resolveRps(room(['ROCK', 'ROCK', 'ROCK', 'PAPER', 'SCISSORS']));
    expect(r.tie).toBe(false);
    expect(r.reason).toBe('majority');
    expect(r.winningChoice).toBe('ROCK');
    expect(r.winners).toEqual(['p0', 'p1', 'p2']);
    expect(r.losers).toEqual(['p3', 'p4']);
  });

  it('6 players: 3R + 2P + 1S → ROCK majority wins', () => {
    const r = resolveRps(room(['ROCK', 'ROCK', 'ROCK', 'PAPER', 'PAPER', 'SCISSORS']));
    expect(r.tie).toBe(false);
    expect(r.reason).toBe('majority');
    expect(r.winningChoice).toBe('ROCK');
    expect(r.winners).toEqual(['p0', 'p1', 'p2']);
    expect(r.losers).toEqual(['p3', 'p4', 'p5']);
  });

  it('6 players: 2R + 2P + 2S → all-equal tie (every shape has 2)', () => {
    const r = resolveRps(room(['ROCK', 'ROCK', 'PAPER', 'PAPER', 'SCISSORS', 'SCISSORS']));
    expect(r.tie).toBe(true);
    expect(r.reason).toBe('all-equal');
  });

  it('6 players: 4R + 1P + 1S → ROCK majority wins', () => {
    const r = resolveRps(room(['ROCK', 'ROCK', 'ROCK', 'ROCK', 'PAPER', 'SCISSORS']));
    expect(r.tie).toBe(false);
    expect(r.reason).toBe('majority');
    expect(r.winningChoice).toBe('ROCK');
    expect(r.winners).toEqual(['p0', 'p1', 'p2', 'p3']);
    expect(r.losers).toEqual(['p4', 'p5']);
  });
});

describe('resolveRps — purity + determinism', () => {
  it('does not mutate its input record', () => {
    const input = room(['ROCK', 'PAPER', 'SCISSORS']);
    const snapshot = JSON.stringify(input);
    resolveRps(input);
    expect(JSON.stringify(input)).toBe(snapshot);
  });

  it('returns identical structure for identical input across calls', () => {
    const input = room(['ROCK', 'ROCK', 'PAPER', 'SCISSORS']);
    const a = resolveRps(input);
    const b = resolveRps(input);
    expect(a).toEqual(b);
  });

  it('preserves caller insertion order in winners[] and losers[]', () => {
    // Players p2, p0, p1 in that submission order.
    const r = resolveRps([
      ['p2', 'ROCK'],
      ['p0', 'ROCK'],
      ['p1', 'SCISSORS'],
    ] as Iterable<[PlayerId, RpsChoice]>);
    expect(r.winners).toEqual(['p2', 'p0']);
    expect(r.losers).toEqual(['p1']);
  });
});

describe('resolveRps — v1 regression guard', () => {
  // Each of these inputs would have been a tie under v1's
  // `unique.size !== 2` rule. They MUST resolve cleanly here.
  const v1WouldHaveTied: Array<{ name: string; input: RpsChoice[]; expectTie: boolean }> = [
    { name: '4p 2R/1P/1S', input: ['ROCK', 'ROCK', 'PAPER', 'SCISSORS'], expectTie: false },
    { name: '4p 1R/2P/1S', input: ['ROCK', 'PAPER', 'PAPER', 'SCISSORS'], expectTie: false },
    { name: '5p 3R/1P/1S', input: ['ROCK', 'ROCK', 'ROCK', 'PAPER', 'SCISSORS'], expectTie: false },
    { name: '5p 2R/2P/1S', input: ['ROCK', 'ROCK', 'PAPER', 'PAPER', 'SCISSORS'], expectTie: false },
    { name: '6p 4R/1P/1S', input: ['ROCK', 'ROCK', 'ROCK', 'ROCK', 'PAPER', 'SCISSORS'], expectTie: false },
    // True ties under the new rule (counts genuinely equal):
    { name: '3p 1R/1P/1S', input: ['ROCK', 'PAPER', 'SCISSORS'], expectTie: true },
    { name: '6p 2R/2P/2S', input: ['ROCK', 'ROCK', 'PAPER', 'PAPER', 'SCISSORS', 'SCISSORS'], expectTie: true },
  ];
  for (const tc of v1WouldHaveTied) {
    it(`${tc.name} → tie=${tc.expectTie}`, () => {
      const r = resolveRps(room(tc.input));
      expect(r.tie).toBe(tc.expectTie);
    });
  }
});
