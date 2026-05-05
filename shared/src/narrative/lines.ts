// FINAL_GOAL §F file structure: shared/src/narrative/lines.ts
// Tie-variant pool + action narration templates lifted out of the engine
// so server, sim CLI, and client all share one canonical Chinese-prose
// surface. The engine imports `defaultNarrator` from here; richer pools /
// streak-aware pickers can be plugged in by passing a custom Narrator to
// resolveRound.
//
// The templates are deliberately colloquial nursery-rhyme flavored — the
// product is a re-tell of the rhyme "小刀一把，来到你家，扒你裤衩，
// 直接咔嚓！" so the action lines literally name the rhyme's verbs
// (扒/砍) and nouns (裤衩/家门).

/**
 * All-equal tie variants — fired when ≥3 alive players threw a unanimous
 * shape (`unique.size === 1` with N≥3, or any all-equal RPS resolution).
 * Pool size is ≥5 so three consecutive ties read as three distinct
 * sentences (FINAL_GOAL §C8). The engine's default tie picker is round-
 * stable (deterministic by `round % pool.length`), which keeps the headless
 * sim reproducible while still rotating flavor.
 */
export const tieVariants: readonly string[] = [
  '场上一阵尴尬的沉默',
  '大家面面相觑，谁都没敢出招',
  '风掠过门前，没人动手',
  '所有人都举着手，气氛凝住了',
  '一瞬间，全场齐刷刷地停了下来',
  '门口尘土齐飞，谁也没碰到谁',
  '邻居探头："你们到底打不打？"',
  '路中央僵成了一幅画，谁都不敢先伸手',
] as const;

/**
 * "All threw the same shape" line — distinct from the all-equal pool so
 * unanimity reads differently from a generic stalemate. RPS reason
 * `'all-same'` (every alive player picked the identical RpsChoice) maps
 * to this single line.
 */
export const allSameLine = '齐了！所有人不约而同地出了同一招';

/**
 * Fallback for the degenerate `'empty'` tie reason (no alive player
 * submitted a choice — defensive; should not happen in normal play).
 * Takes the round number so the line still reads naturally.
 */
export function emptyLine(round: number): string {
  return `第 ${round} 回合无人出招`;
}

/**
 * 扒裤衩 — the rhyme's signature verb. Round number is accepted for
 * symmetry with the other templates (callers may want round-aware
 * variants later) but the default rendering ignores it.
 */
export function pullPantsTemplate(actor: string, target: string, _round?: number): string {
  return `${actor}一个箭步上前，扒下了${target}的裤衩`;
}

/**
 * 砍 — the rhyme's "直接咔嚓!" beat. The blade lands on the door of the
 * target's home (FINAL_GOAL thematic-honesty rule: visible 家门).
 */
export function chopTemplate(actor: string, target: string, _round?: number): string {
  return `${actor}手起刀落，一刀砍向${target}的家门`;
}

/**
 * 闪 — actor swings, target dodges. Not currently emitted by the default
 * engine (the RPS rule pairs winner→loser deterministically) but kept
 * here so a future "dodge" mechanic has a canonical sentence to use,
 * and so the FINAL_GOAL §C8 verb roster (扒/砍/闪/平/死) all have
 * matching narration templates living together.
 */
export function dodgeTemplate(actor: string, target: string, _round?: number): string {
  return `${target}一个侧身，躲开了${actor}的刀锋`;
}

/**
 * 死 — terminal narration when a player is eliminated. The default
 * engine emits CHOP narration on the kill blow, but this template is
 * available for callers that want a separate "X 倒下了" beat (e.g. a
 * GAME_OVER overlay, or a richer Narrator that splits chop+death).
 */
export function deathLine(target: string): string {
  return `${target}应声倒地，再没起来`;
}

/**
 * 穿好裤衩 — the self-restore variant pool (FINAL_GOAL §H4). Five+
 * colloquial lines so a winner who picks PULL_OWN_PANTS_UP across
 * multiple games / rounds gets flavor variety. Round-stable picker
 * keeps the headless sim reproducible.
 */
export const pullOwnPantsUpVariants: readonly string[] = [
  '蹲下身, 把裤衩捡回来穿好了',
  '一把抓住裤腰，重新提了上去',
  '不慌不忙，把裤衩穿了回去',
  '低头一看, 哎呀, 赶紧把裤衩穿好了',
  '抖了抖裤腰，干净利落地穿了回去',
  '满脸通红，飞快地把裤衩拉了上来',
  '深吸一口气，把裤衩重新整理好',
] as const;

/**
 * 穿好裤衩 template — used by the default narrator when winner.stage
 * is ALIVE_PANTS_DOWN and they pick PULL_OWN_PANTS_UP. `actor` is
 * named at the front; the verb-pool sentence completes the line.
 */
export function pullOwnPantsUpTemplate(actor: string, round: number): string {
  const pool = pullOwnPantsUpVariants;
  const idx = ((round % pool.length) + pool.length) % pool.length;
  return `${actor}${pool[idx]!}`;
}

// ── Narrator binding ────────────────────────────────────────────────────
// Engine imports `defaultNarrator` and uses it as the default narration
// surface. The shape matches `engine.ts#Narrator`.

/** Tie-reason discriminator, mirroring rps.ts. Kept as a string literal
 *  union so this module has zero runtime imports from `../game/`. */
export type TieReason = 'all-same' | 'all-equal' | 'empty';

/** Narrator interface — duplicated structurally from engine.ts so this
 *  module is decoupled (no circular import). The engine asserts the two
 *  shapes are compatible at the call site. */
export interface NarratorShape {
  tie: (round: number, reason: TieReason) => string;
  pullPants: (actor: string, target: string, round: number) => string;
  chop: (actor: string, target: string, round: number) => string;
  pullOwnPantsUp: (actor: string, round: number) => string;
}

/**
 * Default narrator — round-stable variant pick from the all-equal pool,
 * dedicated unanimity line, and the action templates above.
 */
export const defaultNarrator: NarratorShape = {
  tie: (round, reason) => {
    if (reason === 'empty') return emptyLine(round);
    if (reason === 'all-same') return allSameLine;
    // round-stable variant pick from the all-equal pool
    const pool = tieVariants;
    const idx = ((round % pool.length) + pool.length) % pool.length;
    return pool[idx]!;
  },
  pullPants: (actor, target, round) => pullPantsTemplate(actor, target, round),
  chop: (actor, target, round) => chopTemplate(actor, target, round),
  pullOwnPantsUp: (actor, round) => pullOwnPantsUpTemplate(actor, round),
};
