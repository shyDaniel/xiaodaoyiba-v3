// Game-logic barrel. Re-exports every concrete module under shared/game/*
// so consumers can write `import { ACTION_TOTAL_MS, resolveRps } from
// '@xdyb/shared'` without reaching into deep paths.
export * from './timing.js';
export * from './rps.js';
export * from './types.js';
export * from './effects.js';
export * from './engine.js';
export * from './bots/index.js';
