// @xdyb/server — Socket.IO entry point.
//
// HTTP server + Socket.IO bind on :3000 (override with PORT). Hosts the
// matchmaking room registry and bridges Socket.IO events to the Room class
// in `rooms/Room.ts`. Handles connection lifecycle (connect, disconnect,
// reconnect-cleanup), room creation/joining/leaving, host-only gameplay
// controls (start, addBot, rematch), and per-player choice submission.
//
// Effect[] choreography is computed by the shared `resolveRound()` and
// emitted verbatim via `room:effects` — the client's EffectPlayer schedules
// canvas calls at each Effect.atMs offset, so server timing only has to
// throttle round-to-round transitions, not per-phase ticks.

import { createServer } from 'node:http';
import { Server, type Socket } from 'socket.io';
import {
  SHARED_PACKAGE_VERSION,
  type ActionKind,
  type RpsChoice,
} from '@xdyb/shared';
import { Room, type RoomBroadcaster } from './rooms/Room.js';
import { RoomRegistry } from './matchmaking.js';

const PORT = Number(process.env.PORT ?? 3000);
const CORS_ORIGIN = process.env.CORS_ORIGIN ?? '*';

interface CreateRoomPayload {
  nickname: string;
}
interface JoinRoomPayload {
  code: string;
  nickname: string;
}
interface ChoicePayload {
  choice: RpsChoice;
}
interface WinnerChoicePayload {
  target: string | null;
  action: ActionKind | null;
}

/** Shape of the event the server emits when something the client did is invalid. */
interface ServerError {
  code: string;
  message: string;
}

function isString(x: unknown): x is string {
  return typeof x === 'string';
}
function isNonEmptyString(x: unknown, max = 32): x is string {
  return isString(x) && x.trim().length > 0 && x.length <= max;
}
function isRpsChoice(x: unknown): x is RpsChoice {
  return x === 'ROCK' || x === 'PAPER' || x === 'SCISSORS';
}
function isActionKind(x: unknown): x is ActionKind {
  return (
    x === 'PULL_PANTS' ||
    x === 'CHOP' ||
    x === 'PULL_OWN_PANTS_UP' ||
    x === 'NONE'
  );
}

export interface ServerHandle {
  port: number;
  /** Active room count (snapshot — for /healthz and tests). */
  roomCount(): number;
  /** Stop the server. Resolves once both Socket.IO and the http listener have closed. */
  close(): Promise<void>;
}

/** Create + start the server. Exported so tests can drive it programmatically. */
export function startServer(opts: { port?: number; corsOrigin?: string } = {}): Promise<ServerHandle> {
  const port = opts.port ?? PORT;
  const corsOrigin = opts.corsOrigin ?? CORS_ORIGIN;

  const registry = new RoomRegistry();

  const httpServer = createServer((req, res) => {
    if (req.url === '/healthz') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(
        JSON.stringify({
          ok: true,
          shared: SHARED_PACKAGE_VERSION,
          rooms: registry.count(),
          uptimeSec: Math.floor(process.uptime()),
        }),
      );
      return;
    }
    res.writeHead(404, { 'content-type': 'text/plain' });
    res.end('xiaodaoyiba-v2 server — see /healthz');
  });

  const io = new Server(httpServer, {
    cors: { origin: corsOrigin, methods: ['GET', 'POST'] },
    serveClient: false,
  });

  function broadcasterFor(code: string): RoomBroadcaster {
    return {
      emitSnapshot: (snapshot) => {
        io.to(`room:${code}`).emit('room:snapshot', snapshot);
      },
      emitRound: (payload) => {
        io.to(`room:${code}`).emit('room:effects', payload);
      },
      emitError: (socketId, message) => {
        io.to(socketId).emit('room:error', { code: 'ROOM_ERROR', message } satisfies ServerError);
      },
      emitWinnerChoice: (socketId, prompt) => {
        io.to(socketId).emit('room:winnerChoice', prompt);
      },
    };
  }

  function leaveRoom(socket: Socket): void {
    const code = registry.socketRoom(socket.id);
    if (!code) return;
    const room = registry.get(code);
    registry.unbindSocket(socket.id);
    if (!room) return;
    room.remove(socket.id);
    void socket.leave(`room:${code}`);
    if (room.isAbandoned()) {
      registry.delete(code);
    }
  }

  io.on('connection', (socket) => {
    const reply = (event: 'room:created' | 'room:joined', payload: object): void => {
      socket.emit(event, payload);
    };
    const fail = (code: string, message: string): void => {
      socket.emit('room:error', { code, message } satisfies ServerError);
    };

    socket.on('room:create', (raw: unknown) => {
      const payload = raw as Partial<CreateRoomPayload>;
      if (!isNonEmptyString(payload?.nickname)) {
        fail('BAD_NICKNAME', 'nickname must be 1-32 chars');
        return;
      }
      const code = registry.generateCode();
      const room = new Room({
        roomId: code,
        hostId: socket.id,
        hostNickname: payload.nickname.trim(),
        hostSocketId: socket.id,
        broadcaster: broadcasterFor(code),
      });
      registry.set(code, room);
      registry.bindSocket(socket.id, code);
      void socket.join(`room:${code}`);
      reply('room:created', { code, snapshot: room.snapshot() });
    });

    socket.on('room:join', (raw: unknown) => {
      const payload = raw as Partial<JoinRoomPayload>;
      if (!isString(payload?.code) || payload.code.length !== 4) {
        fail('BAD_CODE', 'room code must be 4 letters');
        return;
      }
      if (!isNonEmptyString(payload?.nickname)) {
        fail('BAD_NICKNAME', 'nickname must be 1-32 chars');
        return;
      }
      const room = registry.get(payload.code);
      if (!room) {
        fail('NO_ROOM', `no room with code ${payload.code.toUpperCase()}`);
        return;
      }
      const ok = room.addHuman(socket.id, payload.nickname.trim(), socket.id);
      if (!ok) {
        fail('ROOM_FULL_OR_IN_PROGRESS', 'room is full or game already started');
        return;
      }
      registry.bindSocket(socket.id, payload.code);
      void socket.join(`room:${payload.code.toUpperCase()}`);
      reply('room:joined', { code: payload.code.toUpperCase(), snapshot: room.snapshot() });
    });

    socket.on('room:leave', () => leaveRoom(socket));

    socket.on('room:addBot', () => {
      const code = registry.socketRoom(socket.id);
      if (!code) return fail('NOT_IN_ROOM', 'join or create a room first');
      const room = registry.get(code);
      if (!room) return fail('NO_ROOM', 'room no longer exists');
      const id = room.addBot();
      if (!id) fail('CANNOT_ADD_BOT', 'room is full or game in progress');
    });

    socket.on('room:start', () => {
      const code = registry.socketRoom(socket.id);
      if (!code) return fail('NOT_IN_ROOM', 'join or create a room first');
      const room = registry.get(code);
      if (!room) return fail('NO_ROOM', 'room no longer exists');
      const ok = room.start(socket.id);
      if (!ok) fail('CANNOT_START', 'must be host with ≥2 players in lobby');
    });

    socket.on('room:choice', (raw: unknown) => {
      const payload = raw as Partial<ChoicePayload>;
      if (!isRpsChoice(payload?.choice)) return fail('BAD_CHOICE', 'choice must be ROCK/PAPER/SCISSORS');
      const code = registry.socketRoom(socket.id);
      if (!code) return fail('NOT_IN_ROOM', 'join or create a room first');
      const room = registry.get(code);
      if (!room) return fail('NO_ROOM', 'room no longer exists');
      const ok = room.submitChoice(socket.id, payload.choice);
      if (!ok) fail('CANNOT_SUBMIT', 'not your turn or game not in progress');
    });

    socket.on('room:winnerChoice', (raw: unknown) => {
      const payload = raw as Partial<WinnerChoicePayload>;
      const target =
        payload?.target === null
          ? null
          : isString(payload?.target)
            ? payload.target
            : null;
      const action =
        payload?.action === null
          ? null
          : isActionKind(payload?.action)
            ? payload.action
            : null;
      const code = registry.socketRoom(socket.id);
      if (!code) return fail('NOT_IN_ROOM', 'join or create a room first');
      const room = registry.get(code);
      if (!room) return fail('NO_ROOM', 'room no longer exists');
      const ok = room.submitWinnerChoice(socket.id, { target, action });
      if (!ok) fail('CANNOT_SUBMIT_CHOICE', 'no winner-choice window open for you');
    });

    socket.on('room:rematch', () => {
      const code = registry.socketRoom(socket.id);
      if (!code) return fail('NOT_IN_ROOM', 'join or create a room first');
      const room = registry.get(code);
      if (!room) return fail('NO_ROOM', 'room no longer exists');
      const ok = room.rematch(socket.id);
      if (!ok) fail('CANNOT_REMATCH', 'must be host with ENDED room');
    });

    socket.on('disconnect', () => {
      leaveRoom(socket);
    });
  });

  return new Promise<ServerHandle>((resolve) => {
    httpServer.listen(port, () => {
      const addr = httpServer.address();
      const actualPort = typeof addr === 'object' && addr !== null ? addr.port : port;
      // eslint-disable-next-line no-console
      console.log(
        `[xdyb-server] listening on :${actualPort} (shared@${SHARED_PACKAGE_VERSION}, cors=${corsOrigin})`,
      );
      resolve({
        port: actualPort,
        roomCount: () => registry.count(),
        close: () =>
          new Promise<void>((closeResolve, closeReject) => {
            // io.close() also closes the underlying httpServer it was attached
            // to, so we don't call httpServer.close() separately.
            io.close((err) => {
              if (err) closeReject(err);
              else closeResolve();
            });
          }),
      });
    });
  });
}

const isDirect = (() => {
  const entry = process.argv[1] ?? '';
  return entry.endsWith('index.ts') || entry.endsWith('index.js');
})();

if (isDirect) {
  void startServer().catch((err: unknown) => {
    // eslint-disable-next-line no-console
    console.error('[xdyb-server] fatal:', err);
    process.exit(1);
  });
}
