// @xdyb/shared — entry point.
// Re-exports the public surface: game logic primitives and narrative pools.
// Every consumer (server, sim CLI, client) imports timing/RPS/engine/bots
// through this barrel so there is exactly one source of truth.
//
// Ported verbatim from xiaodaoyiba-v2/packages/shared/ in subtask S-002.

export const SHARED_PACKAGE_VERSION = '0.0.1' as const;

export * from './game/index.js';
export * from './narrative/index.js';
