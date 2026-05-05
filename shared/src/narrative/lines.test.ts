// FINAL_GOAL §F + S-343 acceptance: the narrative module is a
// first-class shared/ child, not an inline blob in engine.ts. These
// tests pin the public surface (pool size ≥5, exact 扒裤衩 sentence,
// per-round variant rotation) so a regression that re-inlines the
// pool or rewrites a template will fail loud.

import { describe, expect, it } from 'vitest';
import {
  allSameLine,
  chopTemplate,
  deathLine,
  defaultNarrator,
  dodgeTemplate,
  emptyLine,
  pullPantsTemplate,
  tieVariants,
} from './lines.js';

describe('narrative/lines — pool', () => {
  it('tieVariants pool has ≥5 distinct, non-empty colloquial lines', () => {
    expect(tieVariants.length).toBeGreaterThanOrEqual(5);
    const set = new Set(tieVariants);
    expect(set.size).toBe(tieVariants.length);
    for (const line of tieVariants) {
      expect(line.length).toBeGreaterThan(0);
    }
  });

  it('the 5 lines previously inlined in engine.ts are still present', () => {
    // Acceptance test from S-343: pool must include the 5 lines that
    // used to live at engine.ts:103-125 — ensures no flavor regression.
    const inlined = [
      '场上一阵尴尬的沉默',
      '大家面面相觑，谁都没敢出招',
      '风掠过门前，没人动手',
      '所有人都举着手，气氛凝住了',
      '一瞬间，全场齐刷刷地停了下来',
    ];
    for (const line of inlined) {
      expect(tieVariants).toContain(line);
    }
  });

  it('allSameLine is the dedicated unanimity flavor (not in tieVariants)', () => {
    expect(allSameLine).toMatch(/齐/);
    expect(tieVariants).not.toContain(allSameLine);
  });
});

describe('narrative/lines — templates', () => {
  it('pullPantsTemplate produces the canonical S-343 sentence', () => {
    expect(pullPantsTemplate('A', 'B')).toBe('A一个箭步上前，扒下了B的裤衩');
  });

  it('chopTemplate names 家门 (FINAL_GOAL thematic-honesty)', () => {
    const line = chopTemplate('小红', '小明');
    expect(line).toContain('小红');
    expect(line).toContain('小明');
    expect(line).toContain('家门');
    expect(line).toContain('刀');
  });

  it('dodgeTemplate names actor + target', () => {
    const line = dodgeTemplate('攻', '守');
    expect(line).toContain('攻');
    expect(line).toContain('守');
  });

  it('deathLine names the target', () => {
    expect(deathLine('小刚')).toContain('小刚');
  });

  it('emptyLine includes the round number', () => {
    expect(emptyLine(7)).toContain('7');
  });
});

describe('narrative/lines — defaultNarrator', () => {
  it('all-equal: pulls from tieVariants', () => {
    // Sample 12 consecutive rounds; every line must come from the pool.
    for (let r = 1; r <= 12; r++) {
      const line = defaultNarrator.tie(r, 'all-equal');
      expect(tieVariants).toContain(line);
    }
  });

  it('all-equal: produces ≥3 distinct sentences over 12 rounds', () => {
    // FINAL_GOAL §C8: three consecutive ties read as three different
    // sentences. Round-stable rotation gives us pool.length distinct
    // lines per pool.length consecutive rounds.
    const seen = new Set<string>();
    for (let r = 1; r <= 12; r++) {
      seen.add(defaultNarrator.tie(r, 'all-equal'));
    }
    expect(seen.size).toBeGreaterThanOrEqual(3);
  });

  it('all-same: returns the unanimity flavor', () => {
    expect(defaultNarrator.tie(1, 'all-same')).toBe(allSameLine);
    expect(defaultNarrator.tie(99, 'all-same')).toBe(allSameLine);
  });

  it('empty: returns a round-tagged fallback', () => {
    expect(defaultNarrator.tie(3, 'empty')).toContain('3');
  });

  it('pullPants/chop wire to the templates', () => {
    expect(defaultNarrator.pullPants('A', 'B', 1)).toBe(pullPantsTemplate('A', 'B'));
    expect(defaultNarrator.chop('A', 'B', 1)).toBe(chopTemplate('A', 'B'));
  });
});
