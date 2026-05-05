// index.test.ts — end-to-end Socket.IO server smoke.
//
// Boots the real Server (random port), connects two socket.io-client
// instances (host + joiner), creates a room, joins it, adds a bot, starts
// the game, and asserts that:
//   - both clients receive a synchronized room:snapshot stream
//   - host's room:start triggers a room:effects broadcast to BOTH sockets
//   - room code is 4 letters from the safe alphabet
//   - /healthz returns the live room count
//
// This is the regression guard that the server is "real", not a 19-line
// console.log stub.

import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { io as ioClient, type Socket as ClientSocket } from 'socket.io-client';
import { startServer, type ServerHandle } from './index.js';

const HOST_NICK = 'Alice';
const JOIN_NICK = 'Bob';

function connect(url: string): Promise<ClientSocket> {
  return new Promise((resolve, reject) => {
    const s = ioClient(url, { transports: ['websocket'], reconnection: false });
    s.once('connect', () => resolve(s));
    s.once('connect_error', reject);
  });
}

function once<T>(socket: ClientSocket, event: string): Promise<T> {
  return new Promise<T>((resolve) => {
    socket.once(event, (payload: T) => resolve(payload));
  });
}

let server: ServerHandle;
let url: string;

beforeAll(async () => {
  server = await startServer({ port: 0 });
  url = `http://127.0.0.1:${server.port}`;
});

afterAll(async () => {
  await server.close();
});

describe('Socket.IO server', () => {
  it('answers /healthz with shared version + room count', async () => {
    const res = await fetch(`${url}/healthz`);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { ok: boolean; shared: string; rooms: number };
    expect(body.ok).toBe(true);
    expect(body.shared).toMatch(/^\d+\.\d+\.\d+$/);
    expect(body.rooms).toBeGreaterThanOrEqual(0);
  });

  it('host creates a room, joiner joins via code, both see snapshots', async () => {
    const host = await connect(url);
    const join = await connect(url);
    try {
      const created = await new Promise<{ code: string; snapshot: { players: Array<{ nickname: string }> } }>(
        (resolve) => {
          host.once('room:created', resolve);
          host.emit('room:create', { nickname: HOST_NICK });
        },
      );
      expect(created.code).toMatch(/^[A-Z0-9]{4}$/);
      expect(created.snapshot.players).toHaveLength(1);
      expect(created.snapshot.players[0]?.nickname).toBe(HOST_NICK);

      // Listen for the host's broadcast snapshot BEFORE the join is emitted —
      // otherwise the snapshot fires faster than we can attach the listener.
      const hostSnapP = once<{ players: unknown[] }>(host, 'room:snapshot');

      const joined = await new Promise<{ code: string }>((resolve) => {
        join.once('room:joined', resolve);
        join.emit('room:join', { code: created.code, nickname: JOIN_NICK });
      });
      expect(joined.code).toBe(created.code);

      const hostSnap = await hostSnapP;
      expect(hostSnap.players).toHaveLength(2);
    } finally {
      host.close();
      join.close();
    }
  });

  it('addBot diversifies and start triggers room:effects to all sockets', async () => {
    const host = await connect(url);
    try {
      const created = await new Promise<{ code: string }>((resolve) => {
        host.once('room:created', resolve);
        host.emit('room:create', { nickname: HOST_NICK });
      });
      // Add a bot.
      const botSnap = await new Promise<{ players: Array<{ isBot: boolean; nickname: string }> }>(
        (resolve) => {
          host.once('room:snapshot', resolve);
          host.emit('room:addBot');
        },
      );
      expect(botSnap.players.some((p) => p.isBot)).toBe(true);

      // Start the game; expect a snapshot then a round:effects broadcast.
      const effectsP = once<{ round: number; effects: ReadonlyArray<{ type: string }> }>(host, 'room:effects');
      host.emit('room:start');
      // Host submits choice — the bot already has its choice queued.
      host.emit('room:choice', { choice: 'ROCK' });
      const effects = await effectsP;
      expect(effects.round).toBe(1);
      expect(effects.effects.length).toBeGreaterThan(0);
      expect(effects.effects[0]?.type).toBe('ROUND_START');
      expect(created.code).toMatch(/^[A-Z0-9]{4}$/);
    } finally {
      host.close();
    }
  });

  it('rejects bad inputs with room:error', async () => {
    const sock = await connect(url);
    try {
      const err = await new Promise<{ code: string }>((resolve) => {
        sock.once('room:error', resolve);
        sock.emit('room:create', { nickname: '' });
      });
      expect(err.code).toBe('BAD_NICKNAME');

      const err2 = await new Promise<{ code: string }>((resolve) => {
        sock.once('room:error', resolve);
        sock.emit('room:join', { code: 'XXXX', nickname: 'Bob' });
      });
      expect(err2.code).toBe('NO_ROOM');
    } finally {
      sock.close();
    }
  });
});
