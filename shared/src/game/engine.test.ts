// engine.test.ts — covers the FINAL_GOAL §A acceptance for the round engine.
//
// Key gates this file enforces:
//  - The 4-player ROCK,PAPER,SCISSORS,ROCK scenario from the iteration brief:
//    winner picks loser, PULL_PANTS effect emitted, phase durations match
//    timing.ts.
//  - 20 simulated rounds advance state without exceptions and without
//    infinite loops.
//  - Engine purity: input arrays/maps are not mutated.
//  - 6-phase timeline (REVEAL+PREP→IMPACT, FINAL_GOAL §K2 dropped RETURN)
//    sums to ROUND_TOTAL_MS exactly and the action sub-segment still sums
//    to ACTION_TOTAL_MS (also asserted at module-load in engine.ts, but
//    covered here for visibility).
//  - DEAD players never participate in RPS or get acted on.
//  - PULL_PANTS persists: a player's pants_down stage carries forward to
//    subsequent rounds (FINAL_GOAL §C7 truth-source check at the engine
//    layer; renderer-level persistence is a separate test in client/).

import { describe, expect, it } from 'vitest';
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
import { PHASE_OFFSETS, resolveRound } from './engine.js';
import { effectsOfType, type Effect } from './effects.js';
import type { PlayerState } from './types.js';
import type { RpsChoice } from './rps.js';

function mkPlayers(ids: string[]): PlayerState[] {
  return ids.map((id) => ({ id, nickname: id, stage: 'ALIVE_CLOTHED' as const }));
}

describe('PHASE_OFFSETS', () => {
  it('matches timing.ts cumulative offsets and totals ROUND_TOTAL_MS', () => {
    // REVEAL is the first phase (FINAL_GOAL §H2): 0 → PHASE_T_REVEAL.
    // v6 §K2 removed the trailing RETURN beat, so IMPACT is the closing
    // phase and ROUND_TOTAL_MS = REVEAL + ACTION_TOTAL_MS = 4700.
    expect(PHASE_OFFSETS.REVEAL).toBe(0);
    expect(PHASE_OFFSETS.PREP).toBe(PHASE_T_REVEAL);
    expect(PHASE_OFFSETS.RUSH).toBe(PHASE_T_REVEAL + PHASE_T_PREP);
    expect(PHASE_OFFSETS.PULL_PANTS).toBe(
      PHASE_T_REVEAL + PHASE_T_PREP + PHASE_T_RUSH,
    );
    expect(PHASE_OFFSETS.STRIKE).toBe(
      PHASE_T_REVEAL + PHASE_T_PREP + PHASE_T_RUSH + PHASE_T_PULL_PANTS,
    );
    expect(PHASE_OFFSETS.IMPACT).toBe(
      PHASE_T_REVEAL +
        PHASE_T_PREP +
        PHASE_T_RUSH +
        PHASE_T_PULL_PANTS +
        PHASE_T_STRIKE,
    );
    // Total round timeline closes at ROUND_TOTAL_MS (= 4700), and the
    // action sub-segment (PREP→IMPACT, the part after REVEAL) still
    // totals ACTION_TOTAL_MS (= 3200) so callers reading "action
    // duration" in isolation stay correct.
    expect(PHASE_OFFSETS.IMPACT + PHASE_T_IMPACT).toBe(ROUND_TOTAL_MS);
    expect(ROUND_TOTAL_MS - PHASE_OFFSETS.PREP).toBe(ACTION_TOTAL_MS);
    expect(ACTION_TOTAL_MS).toBe(3200);
    expect(ROUND_TOTAL_MS).toBe(4700);
  });
});

describe('resolveRound — acceptance scenario (4-player RPSR)', () => {
  // 4 players, throws ROCK / PAPER / SCISSORS / ROCK. resolveRps treats this
  // as `unique.size === 3` with majority ROCK (2 ROCKs), so winners are
  // the two ROCK throwers (a, d) and losers are b (PAPER) and c (SCISSORS).
  // Default action against ALIVE_CLOTHED targets is PULL_PANTS.
  const players = mkPlayers(['a', 'b', 'c', 'd']);
  const choices: Record<string, RpsChoice> = {
    a: 'ROCK',
    b: 'PAPER',
    c: 'SCISSORS',
    d: 'ROCK',
  };

  it('produces the expected RPS resolution', () => {
    const out = resolveRound(players, 1, { choices });
    expect(out.rps.tie).toBe(false);
    expect(out.rps.winners).toEqual(['a', 'd']);
    expect(out.rps.losers).toEqual(['b', 'c']);
    expect(out.rps.winningChoice).toBe('ROCK');
    expect(out.rps.reason).toBe('majority');
  });

  it('emits the full phase timeline with timing-constant durations', () => {
    const out = resolveRound(players, 1, { choices });
    const phases = effectsOfType(out.effects, 'PHASE_START');
    // v6 §K2: 6-phase timeline (RETURN dropped). IMPACT is now the closing
    // beat and the actor lingers at the target's house through the full
    // round end.
    expect(phases.map((p) => p.phase)).toEqual([
      'REVEAL', 'PREP', 'RUSH', 'PULL_PANTS', 'STRIKE', 'IMPACT',
    ]);
    expect(phases.map((p) => p.atMs)).toEqual([
      0,
      PHASE_T_REVEAL,
      PHASE_T_REVEAL + PHASE_T_PREP,
      PHASE_T_REVEAL + PHASE_T_PREP + PHASE_T_RUSH,
      PHASE_T_REVEAL + PHASE_T_PREP + PHASE_T_RUSH + PHASE_T_PULL_PANTS,
      PHASE_T_REVEAL + PHASE_T_PREP + PHASE_T_RUSH + PHASE_T_PULL_PANTS + PHASE_T_STRIKE,
    ]);
    expect(phases.map((p) => p.durationMs)).toEqual([
      PHASE_T_REVEAL, PHASE_T_PREP, PHASE_T_RUSH, PHASE_T_PULL_PANTS,
      PHASE_T_STRIKE, PHASE_T_IMPACT,
    ]);
    // Last phase starts + duration sums to the full round timeline
    // (REVEAL + ACTION_TOTAL_MS = ROUND_TOTAL_MS = 4700).
    const last = phases[phases.length - 1]!;
    expect(last.atMs + last.durationMs).toBe(ROUND_TOTAL_MS);
    expect(last.atMs + last.durationMs).toBe(4700);
  });

  it('emits a single RPS_REVEAL effect carrying every alive player\'s throw', () => {
    const out = resolveRound(players, 1, { choices });
    const reveals = effectsOfType(out.effects, 'RPS_REVEAL');
    expect(reveals).toHaveLength(1);
    const reveal = reveals[0]!;
    expect(reveal.atMs).toBe(0);
    expect(reveal.durationMs).toBe(PHASE_T_REVEAL);
    // One row per player, in input order, carrying their throw.
    expect(reveal.throws).toEqual([
      { playerId: 'a', choice: 'ROCK' },
      { playerId: 'b', choice: 'PAPER' },
      { playerId: 'c', choice: 'SCISSORS' },
      { playerId: 'd', choice: 'ROCK' },
    ]);
  });

  it('emits PULL_PANTS ACTION effects pairing winners → losers in order', () => {
    const out = resolveRound(players, 1, { choices });
    const actions = effectsOfType(out.effects, 'ACTION');
    expect(actions).toHaveLength(2);
    expect(actions[0]).toMatchObject({
      actor: 'a',
      target: 'b',
      kind: 'PULL_PANTS',
      atMs: PHASE_OFFSETS.PULL_PANTS,
    });
    expect(actions[1]).toMatchObject({
      actor: 'd',
      target: 'c',
      kind: 'PULL_PANTS',
      atMs: PHASE_OFFSETS.PULL_PANTS,
    });
  });

  it('emits SET_STAGE for each pull_pants target after the shame hold', () => {
    const out = resolveRound(players, 1, { choices });
    const setStage = effectsOfType(out.effects, 'SET_STAGE');
    expect(setStage).toHaveLength(2);
    for (const eff of setStage) {
      expect(eff.stage).toBe('ALIVE_PANTS_DOWN');
      expect(eff.atMs).toBe(PHASE_OFFSETS.PULL_PANTS + SHAME_FRAME_HOLD_MS);
    }
    expect(setStage.map((e) => e.target)).toEqual(['b', 'c']);
  });

  it('emits one human-readable NARRATION per pairing with verb=扒', () => {
    const out = resolveRound(players, 1, { choices });
    const narrations = effectsOfType(out.effects, 'NARRATION');
    expect(narrations).toHaveLength(2);
    for (const n of narrations) {
      expect(n.verb).toBe('扒');
      expect(n.text.length).toBeGreaterThan(0);
    }
    expect(out.narration.split('\n')).toHaveLength(2);
  });

  it('returns a fresh players array with losers set to ALIVE_PANTS_DOWN', () => {
    const out = resolveRound(players, 1, { choices });
    expect(out.players).not.toBe(players);
    expect(out.players.map((p) => p.stage)).toEqual([
      'ALIVE_CLOTHED',
      'ALIVE_PANTS_DOWN',
      'ALIVE_PANTS_DOWN',
      'ALIVE_CLOTHED',
    ]);
  });

  it('does not mutate the input players or choices', () => {
    const beforePlayers = JSON.parse(JSON.stringify(players));
    const beforeChoices = JSON.parse(JSON.stringify(choices));
    resolveRound(players, 1, { choices });
    expect(players).toEqual(beforePlayers);
    expect(choices).toEqual(beforeChoices);
  });

  it('isGameOver is false (4 alive)', () => {
    const out = resolveRound(players, 1, { choices });
    expect(out.isGameOver).toBe(false);
    expect(out.winnerId).toBe(null);
    expect(effectsOfType(out.effects, 'GAME_OVER')).toHaveLength(0);
  });
});

describe('resolveRound — tie path', () => {
  it('all-equal counts → tie, no PHASE_START events, TIE_NARRATION holds for TIE_NARRATION_HOLD_MS', () => {
    const players = mkPlayers(['a', 'b', 'c']);
    const choices: Record<string, RpsChoice> = { a: 'ROCK', b: 'PAPER', c: 'SCISSORS' };
    const out = resolveRound(players, 7, { choices });
    expect(out.rps.tie).toBe(true);
    expect(out.rps.reason).toBe('all-equal');
    expect(effectsOfType(out.effects, 'PHASE_START')).toHaveLength(0);
    const tie = effectsOfType(out.effects, 'TIE_NARRATION');
    expect(tie).toHaveLength(1);
    expect(tie[0]!.durationMs).toBe(TIE_NARRATION_HOLD_MS);
    expect(tie[0]!.text.length).toBeGreaterThan(0);
    const narr = effectsOfType(out.effects, 'NARRATION');
    expect(narr).toHaveLength(1);
    expect(narr[0]!.verb).toBe('平');
    // No state changed.
    expect(out.players.map((p) => p.stage)).toEqual([
      'ALIVE_CLOTHED', 'ALIVE_CLOTHED', 'ALIVE_CLOTHED',
    ]);
  });

  it('all-same → tie, distinct narration variant from all-equal', () => {
    const players = mkPlayers(['a', 'b', 'c']);
    const choices: Record<string, RpsChoice> = { a: 'PAPER', b: 'PAPER', c: 'PAPER' };
    const out = resolveRound(players, 1, { choices });
    expect(out.rps.tie).toBe(true);
    expect(out.rps.reason).toBe('all-same');
    expect(effectsOfType(out.effects, 'TIE_NARRATION')[0]!.text).toContain('齐了');
  });
});

describe('resolveRound — pants_down → CHOP transition', () => {
  it('an already-pants-down loser gets CHOPped, target dies', () => {
    const players: PlayerState[] = [
      { id: 'a', nickname: 'A', stage: 'ALIVE_CLOTHED' },
      { id: 'b', nickname: 'B', stage: 'ALIVE_PANTS_DOWN' },
    ];
    // a=ROCK b=SCISSORS → a wins, b loses; b is pants_down → CHOP
    const out = resolveRound(players, 3, { choices: { a: 'ROCK', b: 'SCISSORS' } });
    expect(out.rps.winners).toEqual(['a']);
    expect(out.rps.losers).toEqual(['b']);
    const actions = effectsOfType(out.effects, 'ACTION');
    expect(actions[0]!.kind).toBe('CHOP');
    const setStage = effectsOfType(out.effects, 'SET_STAGE');
    expect(setStage[0]!.stage).toBe('DEAD');
    expect(setStage[0]!.atMs).toBe(PHASE_OFFSETS.STRIKE);
    const narr = effectsOfType(out.effects, 'NARRATION');
    expect(narr[0]!.verb).toBe('砍');
    expect(out.players.find((p) => p.id === 'b')!.stage).toBe('DEAD');
    expect(out.isGameOver).toBe(true);
    expect(out.winnerId).toBe('a');
    expect(effectsOfType(out.effects, 'GAME_OVER')).toHaveLength(1);
  });
});

describe('resolveRound — DEAD players are skipped', () => {
  it('does not include DEAD players in RPS, even if they have a stale choice', () => {
    const players: PlayerState[] = [
      { id: 'a', nickname: 'A', stage: 'ALIVE_CLOTHED' },
      { id: 'b', nickname: 'B', stage: 'ALIVE_CLOTHED' },
      { id: 'c', nickname: 'C', stage: 'DEAD' },
    ];
    const out = resolveRound(players, 1, {
      choices: { a: 'ROCK', b: 'SCISSORS', c: 'PAPER' /* ignored */ },
    });
    expect(out.rps.winners).toEqual(['a']);
    expect(out.rps.losers).toEqual(['b']);
    // No effect should reference 'c' as actor or target.
    for (const eff of out.effects) {
      if ('actor' in eff && eff.actor !== undefined) expect(eff.actor).not.toBe('c');
      if ('target' in eff && eff.target !== undefined) expect(eff.target).not.toBe('c');
    }
  });
});

describe('resolveRound — PULL_OWN_PANTS_UP self-action (FINAL_GOAL §H4)', () => {
  // §H4: a winner whose pre-round stage is ALIVE_PANTS_DOWN may opt into
  // the SELF action `PULL_OWN_PANTS_UP` via inputs.actions[winnerId]. The
  // engine emits ACTION/SET_STAGE/NARRATION effects with actor===target,
  // flips that winner's stage back to ALIVE_CLOTHED, and does NOT consume
  // a loser slot for that winner.

  it('flips a pants-down winner back to ALIVE_CLOTHED when they self-restore', () => {
    // 2 players: a (pants-down winner) vs b (clothed loser). a throws
    // ROCK, b throws SCISSORS. a wins; instead of pulling b's pants,
    // a opts to pull their own pants up.
    const players: PlayerState[] = [
      { id: 'a', nickname: 'A', stage: 'ALIVE_PANTS_DOWN' },
      { id: 'b', nickname: 'B', stage: 'ALIVE_CLOTHED' },
    ];
    const out = resolveRound(players, 7, {
      choices: { a: 'ROCK', b: 'SCISSORS' },
      actions: { a: 'PULL_OWN_PANTS_UP' },
    });

    expect(out.rps.winners).toEqual(['a']);
    expect(out.rps.losers).toEqual(['b']);

    const actions = effectsOfType(out.effects, 'ACTION');
    expect(actions).toHaveLength(1);
    expect(actions[0]!.actor).toBe('a');
    expect(actions[0]!.target).toBe('a');
    expect(actions[0]!.kind).toBe('PULL_OWN_PANTS_UP');

    const setStages = effectsOfType(out.effects, 'SET_STAGE');
    expect(setStages).toHaveLength(1);
    expect(setStages[0]!.target).toBe('a');
    expect(setStages[0]!.stage).toBe('ALIVE_CLOTHED');
    expect(setStages[0]!.atMs).toBe(PHASE_OFFSETS.PULL_PANTS + SHAME_FRAME_HOLD_MS);

    const narrations = effectsOfType(out.effects, 'NARRATION');
    expect(narrations).toHaveLength(1);
    expect(narrations[0]!.verb).toBe('穿');
    expect(narrations[0]!.actor).toBe('a');
    expect(narrations[0]!.target).toBe('a');
    expect(narrations[0]!.text.length).toBeGreaterThan(0);

    // Post-round stages: a self-restored, b untouched.
    const a = out.players.find((p) => p.id === 'a')!;
    const b = out.players.find((p) => p.id === 'b')!;
    expect(a.stage).toBe('ALIVE_CLOTHED');
    expect(b.stage).toBe('ALIVE_CLOTHED');
  });

  it('ignores PULL_OWN_PANTS_UP when winner is not pants-down (falls back to default)', () => {
    // a is clothed, so the self-action is invalid. Engine must fall back
    // to the default loser pairing (PULL_PANTS on b).
    const players: PlayerState[] = [
      { id: 'a', nickname: 'A', stage: 'ALIVE_CLOTHED' },
      { id: 'b', nickname: 'B', stage: 'ALIVE_CLOTHED' },
    ];
    const out = resolveRound(players, 1, {
      choices: { a: 'ROCK', b: 'SCISSORS' },
      actions: { a: 'PULL_OWN_PANTS_UP' },
    });

    const actions = effectsOfType(out.effects, 'ACTION');
    expect(actions).toHaveLength(1);
    expect(actions[0]!.actor).toBe('a');
    expect(actions[0]!.target).toBe('b');
    expect(actions[0]!.kind).toBe('PULL_PANTS');

    const a = out.players.find((p) => p.id === 'a')!;
    const b = out.players.find((p) => p.id === 'b')!;
    expect(a.stage).toBe('ALIVE_CLOTHED');
    expect(b.stage).toBe('ALIVE_PANTS_DOWN');
  });

  it('a self-restoring winner does not consume a loser slot for other winners', () => {
    // 4 players: a (pants-down) and d (clothed) win against b and c.
    // a opts for self-restore. b should still be available for d to
    // pull-pants — i.e. a's self-action does NOT claim b.
    const players: PlayerState[] = [
      { id: 'a', nickname: 'A', stage: 'ALIVE_PANTS_DOWN' },
      { id: 'b', nickname: 'B', stage: 'ALIVE_CLOTHED' },
      { id: 'c', nickname: 'C', stage: 'ALIVE_CLOTHED' },
      { id: 'd', nickname: 'D', stage: 'ALIVE_CLOTHED' },
    ];
    const out = resolveRound(players, 3, {
      choices: { a: 'ROCK', b: 'PAPER', c: 'SCISSORS', d: 'ROCK' },
      actions: { a: 'PULL_OWN_PANTS_UP' },
    });

    expect(out.rps.winners).toEqual(['a', 'd']);
    expect(out.rps.losers).toEqual(['b', 'c']);

    const actions = effectsOfType(out.effects, 'ACTION');
    // Two actions total: a self-restore + d pulling first available
    // unclaimed loser (b).
    expect(actions).toHaveLength(2);
    const pairings = actions.map((x) => `${x.actor}->${x.target}:${x.kind}`);
    expect(pairings).toEqual([
      'a->a:PULL_OWN_PANTS_UP',
      'd->b:PULL_PANTS',
    ]);

    const a = out.players.find((p) => p.id === 'a')!;
    const b = out.players.find((p) => p.id === 'b')!;
    const c = out.players.find((p) => p.id === 'c')!;
    const d = out.players.find((p) => p.id === 'd')!;
    expect(a.stage).toBe('ALIVE_CLOTHED');
    expect(b.stage).toBe('ALIVE_PANTS_DOWN');
    expect(c.stage).toBe('ALIVE_CLOTHED');
    expect(d.stage).toBe('ALIVE_CLOTHED');
  });
});

describe('resolveRound — explicit target overrides', () => {
  it('uses inputs.targets when valid', () => {
    const players = mkPlayers(['a', 'b', 'c', 'd']);
    // a=ROCK, d=ROCK win against b=PAPER, c=SCISSORS (majority ROCK).
    // Tell `a` to pick `c` (the second loser). `d` defaults to b.
    const out = resolveRound(players, 1, {
      choices: { a: 'ROCK', b: 'PAPER', c: 'SCISSORS', d: 'ROCK' },
      targets: { a: 'c' },
    });
    const actions = effectsOfType(out.effects, 'ACTION');
    expect(actions.map((a) => `${a.actor}->${a.target}`)).toEqual(['a->c', 'd->b']);
  });

  it('falls back to default pairing when target is not a loser', () => {
    const players = mkPlayers(['a', 'b', 'c', 'd']);
    const out = resolveRound(players, 1, {
      choices: { a: 'ROCK', b: 'PAPER', c: 'SCISSORS', d: 'ROCK' },
      // 'a' is a winner, not a loser → invalid target, ignored
      targets: { a: 'd' },
    });
    const actions = effectsOfType(out.effects, 'ACTION');
    expect(actions.map((a) => `${a.actor}->${a.target}`)).toEqual(['a->b', 'd->c']);
  });
});

describe('resolveRound — 20-round simulation', () => {
  // Runs a deterministic random-throw sim for 20 rounds. Asserts:
  //   - no exceptions
  //   - every round emits ROUND_START at atMs 0
  //   - if any single round produces an action timeline, it sums to
  //     ROUND_TOTAL_MS (REVEAL + ACTION_TOTAL_MS) exactly
  //   - state monotonically progresses (no resurrected players, alive count
  //     is non-increasing)
  function mulberry32(seed: number): () => number {
    return function () {
      let t = (seed += 0x6d2b79f5) | 0;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  it('20 rounds advance without exceptions and remain consistent', () => {
    const rng = mulberry32(42);
    let players: PlayerState[] = mkPlayers(['p1', 'p2', 'p3', 'p4']);
    let prevAlive = players.length;
    for (let round = 1; round <= 20; round += 1) {
      const choices: Record<string, RpsChoice> = {};
      const SHAPES: RpsChoice[] = ['ROCK', 'PAPER', 'SCISSORS'];
      for (const p of players) {
        if (p.stage === 'DEAD') continue;
        const idx = Math.floor(rng() * 3) % 3;
        choices[p.id] = SHAPES[idx]!;
      }

      const out = resolveRound(players, round, { choices });

      // ROUND_START is always first effect
      expect(out.effects[0]!.type).toBe('ROUND_START');
      expect((out.effects[0] as Extract<Effect, { type: 'ROUND_START' }>).atMs).toBe(0);

      // If we had an action timeline, it sums to ROUND_TOTAL_MS
      // (REVEAL + ACTION_TOTAL_MS) — see FINAL_GOAL §H2/§K2. v6 §K2
      // dropped the trailing RETURN beat, leaving 6 PHASE_START events
      // per action round.
      const phases = effectsOfType(out.effects, 'PHASE_START');
      if (phases.length > 0) {
        expect(phases).toHaveLength(6);
        const last = phases[phases.length - 1]!;
        expect(last.atMs + last.durationMs).toBe(ROUND_TOTAL_MS);
      }

      // Alive count never increases
      const alive = out.players.filter((p) => p.stage !== 'DEAD').length;
      expect(alive).toBeLessThanOrEqual(prevAlive);
      prevAlive = alive;
      players = out.players;

      if (out.isGameOver) break;
    }
    // After 20 rounds something must have happened — the stage distribution
    // either has at most 1 alive (game ended) or has at least one transition
    // away from the all-clothed start.
    const stages = players.map((p) => p.stage);
    const alive = stages.filter((s) => s !== 'DEAD').length;
    const clothed = stages.filter((s) => s === 'ALIVE_CLOTHED').length;
    expect(alive <= 1 || clothed < players.length).toBe(true);
  });
});
