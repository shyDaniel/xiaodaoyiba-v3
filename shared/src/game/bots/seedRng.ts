// Deterministic, seeded PRNGs.
//
// Why this lives here:
// FINAL_GOAL §A4 mandates a per-bot seeded RNG so that two bots in the same
// room with the same strategy still throw independent shapes, AND so the
// `--seed` flag on the headless sim CLI makes a full run reproducible.
//
// We expose two primitives:
//
//   1. `mulberry32(seed)` — small, fast, well-distributed 32-bit PRNG. It is
//      the workhorse for bot decision streams. Its statistical quality is
//      more than enough for nursery-rhyme RPS bots and it serializes to a
//      single 32-bit integer so the same seed always produces the same
//      stream.
//
//   2. `splitmix32(seed)` — a one-shot mixer. Used by `deriveBotSeed` to
//      derive a unique seed from a (botId, roomId, runSeed) triple without
//      collisions, even when two of the three are identical.
//
// Neither is cryptographically secure. Do NOT use these for anything other
// than gameplay determinism.

export type Rng = () => number;

/**
 * Mulberry32 — a tiny 32-bit PRNG.
 * Returns a function that yields a uniform float in [0, 1) per call.
 * Reference: Tommy Ettinger / Chris Doty-Humphrey common-domain.
 */
export function mulberry32(seed: number): Rng {
  let state = seed >>> 0;
  return function rand(): number {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * One-shot 32-bit mixer derived from SplitMix64. Used to derive sub-seeds
 * from a parent seed without bias when two bots share most of the input.
 */
export function splitmix32(seed: number): number {
  let z = (seed + 0x9e3779b9) >>> 0;
  z = Math.imul(z ^ (z >>> 16), 0x85ebca6b) >>> 0;
  z = Math.imul(z ^ (z >>> 13), 0xc2b2ae35) >>> 0;
  return (z ^ (z >>> 16)) >>> 0;
}

/**
 * Cheap deterministic 32-bit hash of a string. Used so a bot's `id`
 * ("bot-3", "iron-2") contributes uniquely to its seed. Not collision-
 * resistant, but easily good enough for "two strings → two seeds."
 */
export function hashString(s: string): number {
  let h = 0x811c9dc5; // FNV-1a 32-bit offset basis
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

/**
 * Derive a per-bot seed from (runSeed, roomId, botId). Mixing the inputs
 * via FNV-1a + splitmix32 ensures swapping any one component produces an
 * essentially independent stream. `roomId` may be empty for the headless
 * sim; that's fine — splitmix will still spread the result.
 */
export function deriveBotSeed(
  runSeed: number,
  roomId: string,
  botId: string,
): number {
  const mixed = (hashString(roomId) ^ hashString(botId) ^ (runSeed >>> 0)) >>> 0;
  return splitmix32(mixed);
}

/**
 * Seed an RNG bundle. Convenience wrapper that calls `deriveBotSeed` then
 * `mulberry32`.
 */
export function seededRng(
  runSeed: number,
  roomId: string,
  botId: string,
): Rng {
  return mulberry32(deriveBotSeed(runSeed, roomId, botId));
}

/** Pick one item from an array uniformly. */
export function pickOne<T>(rng: Rng, xs: readonly T[]): T {
  if (xs.length === 0) throw new Error('pickOne: empty array');
  return xs[Math.floor(rng() * xs.length)]!;
}
