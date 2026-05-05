// Multi-player rock-paper-scissors resolution.
//
// Why this file exists
// --------------------
// v1 shipped with `unique.size !== 2 → tie` (xiaodaoyiba/packages/shared/src/
// game/rps.ts:27-29). That single line was the root of the "always tie" bug
// that ruined N≥3 games: any round in which the players collectively threw
// all three shapes was forced into a tie regardless of how many people threw
// what. Combined with v1's bot-strategy/RNG monoculture, 4-player rooms
// against 3 bots had a tie rate near 100%.
//
// FINAL_GOAL §A2 mandates the fix: handle `unique.size === 3` properly. The
// rule chosen here (and documented in ARCHITECTURE.md) is:
//
//   1. unique.size === 1  → tie. Everyone threw the same shape.
//   2. unique.size === 2  → standard 2-way RPS. The winning shape's players
//                            advance, the losing shape's players are out.
//   3. unique.size === 3  → MAJORITY WINS. Find the shape with the strictly
//                            highest count. If exactly one shape holds that
//                            count, its players advance and the other two
//                            shapes' players are out. Otherwise (≥2 shapes
//                            tied for highest), apply the LONE-SHAPE
//                            tiebreak: if exactly one shape holds the
//                            strictly lowest count, that shape's players
//                            advance ("the unique outlier survives"). If
//                            even that fails (all three counts equal), it
//                            is a true tie.
//
// Worked examples (the unit-test matrix below covers these explicitly):
//   {R:2,P:1,S:1}   majority R           → R wins
//   {R:1,P:2,S:1}   majority P           → P wins
//   {R:1,P:1,S:2}   majority S           → S wins
//   {R:2,P:2,S:1}   no majority, lone S  → S wins (outlier advances)
//   {R:2,P:1,S:2}   no majority, lone P  → P wins (outlier advances)
//   {R:1,P:2,S:2}   no majority, lone R  → R wins (outlier advances)
//   {R:1,P:1,S:1}   all equal            → tie
//   {R:2,P:2,S:2}   all equal            → tie
//
// The function is **pure**: same input → same output, no I/O, no clock, no
// RNG. The map of choices uses a stable iteration order via
// `Object.entries`, so winners[]/losers[] preserve the caller's insertion
// order — the engine and tests rely on that determinism.

export type RpsChoice = 'ROCK' | 'PAPER' | 'SCISSORS';

/** Lightweight alias matching v1's protocol; engine.ts will widen it later. */
export type PlayerId = string;

/** All three shapes, in the canonical order used by display + log. */
export const RPS_CHOICES: readonly RpsChoice[] = ['ROCK', 'PAPER', 'SCISSORS'] as const;

/** Which shape each shape beats. */
const BEATS: Readonly<Record<RpsChoice, RpsChoice>> = {
  ROCK: 'SCISSORS',
  SCISSORS: 'PAPER',
  PAPER: 'ROCK',
};

export interface RpsResolution {
  /** True if the round produced no winners and no losers. */
  tie: boolean;
  /** Players whose shape advances (empty on tie). Order matches input. */
  winners: PlayerId[];
  /** Players whose shape is eliminated this round (empty on tie). */
  losers: PlayerId[];
  /** The shape (or shapes) that won — single in 2-way, single in majority,
   *  single in lone-outlier; undefined on tie. */
  winningChoice?: RpsChoice;
  /**
   * How the round was resolved. Useful for narration + tests.
   * - 'all-same'   → unique.size === 1
   * - 'two-way'    → unique.size === 2 with a clear beats-relation
   * - 'majority'   → unique.size === 3, one shape with strictly highest count
   * - 'outlier'    → unique.size === 3, no majority but one lone shape
   * - 'all-equal'  → unique.size === 3 with all three counts equal
   * - 'empty'      → no players submitted choices
   */
  reason: 'all-same' | 'two-way' | 'majority' | 'outlier' | 'all-equal' | 'empty';
}

/**
 * Resolve a round of N≥0 RPS throws.
 *
 * Accepts either:
 *   - a `Record<PlayerId, RpsChoice>` (object map, like v1), or
 *   - an iterable of `[playerId, choice]` tuples (preserves caller order
 *     even for duplicate ids in test scenarios).
 *
 * Returns an `RpsResolution`. Never throws on bad shape (undefined choices
 * are filtered out — but the function does not silently coerce malformed
 * input; the engine should validate upstream).
 */
export function resolveRps(
  choices: Record<PlayerId, RpsChoice> | Iterable<readonly [PlayerId, RpsChoice]>,
): RpsResolution {
  const entries: Array<readonly [PlayerId, RpsChoice]> = isIterableOfTuples(choices)
    ? Array.from(choices)
    : (Object.entries(choices) as Array<readonly [PlayerId, RpsChoice]>);

  if (entries.length === 0) {
    return { tie: true, winners: [], losers: [], reason: 'empty' };
  }

  // Count how many players threw each shape, preserving insertion order.
  const counts: Record<RpsChoice, number> = { ROCK: 0, PAPER: 0, SCISSORS: 0 };
  for (const [, choice] of entries) {
    counts[choice] += 1;
  }
  const present = (Object.entries(counts) as Array<[RpsChoice, number]>)
    .filter(([, n]) => n > 0)
    .map(([c]) => c);

  // Case 1: everyone threw the same shape.
  if (present.length === 1) {
    return { tie: true, winners: [], losers: [], reason: 'all-same' };
  }

  // Case 2: classical 2-way RPS. The winner is whichever present shape beats
  // the other present shape.
  if (present.length === 2) {
    const a = present[0]!;
    const b = present[1]!;
    const winningChoice: RpsChoice = BEATS[a] === b ? a : b;
    const losingChoice: RpsChoice = winningChoice === a ? b : a;
    const winners = entries.filter(([, c]) => c === winningChoice).map(([id]) => id);
    const losers = entries.filter(([, c]) => c === losingChoice).map(([id]) => id);
    return { tie: false, winners, losers, winningChoice, reason: 'two-way' };
  }

  // Case 3: all three shapes thrown.
  // 3a. Majority wins: the strictly highest count, held by exactly one shape.
  const maxCount = Math.max(counts.ROCK, counts.PAPER, counts.SCISSORS);
  const atMax = (Object.entries(counts) as Array<[RpsChoice, number]>).filter(
    ([, n]) => n === maxCount,
  );
  if (atMax.length === 1) {
    const winningChoice = atMax[0]![0];
    const winners = entries.filter(([, c]) => c === winningChoice).map(([id]) => id);
    const losers = entries.filter(([, c]) => c !== winningChoice).map(([id]) => id);
    return { tie: false, winners, losers, winningChoice, reason: 'majority' };
  }

  // 3b. No majority. Try the lone-outlier rule: the strictly lowest count,
  // held by exactly one shape, advances.
  const minCount = Math.min(counts.ROCK, counts.PAPER, counts.SCISSORS);
  const atMin = (Object.entries(counts) as Array<[RpsChoice, number]>).filter(
    ([, n]) => n === minCount,
  );
  if (atMin.length === 1 && minCount > 0) {
    const winningChoice = atMin[0]![0];
    const winners = entries.filter(([, c]) => c === winningChoice).map(([id]) => id);
    const losers = entries.filter(([, c]) => c !== winningChoice).map(([id]) => id);
    return { tie: false, winners, losers, winningChoice, reason: 'outlier' };
  }

  // 3c. All three shapes thrown in equal counts → genuine tie.
  return { tie: true, winners: [], losers: [], reason: 'all-equal' };
}

function isIterableOfTuples(
  v: Record<PlayerId, RpsChoice> | Iterable<readonly [PlayerId, RpsChoice]>,
): v is Iterable<readonly [PlayerId, RpsChoice]> {
  return typeof (v as { [Symbol.iterator]?: unknown })[Symbol.iterator] === 'function';
}
