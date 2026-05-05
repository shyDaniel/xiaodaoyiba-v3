// Matchmaking — minimal room registry.
//
// v2 matchmaking is intentionally simple: the host generates a 4-letter
// room code; everyone else types it in. No queue, no skill matching, no
// regional sharding. The Room class owns gameplay state; this file only
// owns the {code → Room} index and the code-generator.
//
// Expansion path (out of scope for now): replace `RoomRegistry` with a
// Redis-backed registry to enable horizontal scale. The Room interface
// is already serializable through `snapshot()`.

import type { Room } from './rooms/Room.js';

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no I/O/0/1
const CODE_LENGTH = 4;

export class RoomRegistry {
  private byCode = new Map<string, Room>();
  private bySocket = new Map<string, string>(); // socketId → code

  /** Generate a unique room code that doesn't collide with existing rooms. */
  generateCode(): string {
    for (let attempt = 0; attempt < 64; attempt++) {
      let code = '';
      for (let i = 0; i < CODE_LENGTH; i++) {
        code += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
      }
      if (!this.byCode.has(code)) return code;
    }
    throw new Error('matchmaking: could not generate a unique room code after 64 attempts');
  }

  /** Get room by its uppercase code; returns undefined if not found. */
  get(code: string): Room | undefined {
    return this.byCode.get(code.toUpperCase());
  }

  /** Register a new room under its code. */
  set(code: string, room: Room): void {
    this.byCode.set(code.toUpperCase(), room);
  }

  /** Track which room a socket joined (for fast disconnect lookup). */
  bindSocket(socketId: string, code: string): void {
    this.bySocket.set(socketId, code.toUpperCase());
  }

  /** Returns the code the socket joined, or undefined. */
  socketRoom(socketId: string): string | undefined {
    return this.bySocket.get(socketId);
  }

  /** Untrack a socket (called on disconnect). */
  unbindSocket(socketId: string): void {
    this.bySocket.delete(socketId);
  }

  /** Remove a room. Idempotent. */
  delete(code: string): void {
    this.byCode.delete(code.toUpperCase());
  }

  /** Total number of active rooms (used by /healthz). */
  count(): number {
    return this.byCode.size;
  }

  /** Iterate room codes (used by /healthz / admin). */
  codes(): IterableIterator<string> {
    return this.byCode.keys();
  }
}
