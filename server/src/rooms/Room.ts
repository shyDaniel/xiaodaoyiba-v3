// Room — server-side game state for one match.
//
// Holds the player roster, collects RPS choices each round, runs the engine
// when all alive players have submitted, and broadcasts the resulting
// Effect[] choreography to every socket. The client's EffectPlayer schedules
// canvas calls at each Effect.atMs offset; the server is purely a coordinator.
//
// Bots are first-class room members with their own seeded RNG (FINAL_GOAL §A4)
// and diversified strategies (§A3) — exactly what `pnpm sim` uses, just over
// a Socket.IO transport instead of stdout.

import {
  ROUND_TOTAL_MS,
  TIE_NARRATION_HOLD_MS,
  WINNER_CHOICE_BUDGET_MS,
  resolveRps,
  type ActionKind,
  type BotKind,
  type BotStrategy,
  type Effect,
  type PlayerState,
  type RoundHistoryEntry,
  type RoundInputs,
  type RpsChoice,
  type Rng,
  getBotStrategy,
  pickStrategyForIndex,
  resolveRound,
  seededRng,
} from '@xdyb/shared';

// §H3 winner-choice budget (the room waits this long for human winners
// to submit a target+action before falling back to engine auto-pick) is
// imported from shared/game/timing.ts so it stays in lockstep with the
// generated Timing.gd and the client picker UI hold.

export interface RoomMember {
  /** Stable id; matches socket.id for humans, derived id for bots. */
  id: string;
  nickname: string;
  isBot: boolean;
  /** undefined for bots; socket.id for humans (1:1 with id today). */
  socketId: string | undefined;
  /** undefined for humans; populated for bots. */
  bot?: {
    kind: BotKind;
    strategy: BotStrategy;
    rng: Rng;
  };
}

/** Public-facing snapshot of a room (broadcast to clients on changes). */
export interface RoomSnapshot {
  roomId: string;
  hostId: string;
  phase: 'LOBBY' | 'PLAYING' | 'ENDED';
  round: number;
  players: ReadonlyArray<{
    id: string;
    nickname: string;
    isBot: boolean;
    stage: PlayerState['stage'];
    isHost: boolean;
    hasSubmitted: boolean;
    /** S-430 stable join-order index (0-based, position in members[]).
     *  Drives the client's per-player accent palette so a 6-bot room
     *  always has 6 distinct hues regardless of name collisions. */
    joinOrder: number;
  }>;
  /** Last-round narration (for late joiners / reconnects); empty during LOBBY. */
  lastNarration: string;
  winnerId: string | null;
}

/** Effect-list payload broadcast each round. Mirrors the sim CLI's per-round emission. */
export interface RoundBroadcast {
  round: number;
  effects: ReadonlyArray<Effect>;
  narration: string;
  isGameOver: boolean;
  winnerId: string | null;
}

/** §H3 winner-agency prompt — sent to each human winner after RPS
 *  resolves but before the action timeline plays. Listing of eligible
 *  losers and whether the SELF action is unlocked. The client renders a
 *  TargetPicker / ActionPicker and emits room:winnerChoice within
 *  WINNER_CHOICE_BUDGET_MS or accepts the auto-pick. */
export interface WinnerChoicePrompt {
  round: number;
  winnerId: string;
  winnerStage: PlayerState['stage'];
  candidates: ReadonlyArray<{
    id: string;
    nickname: string;
    stage: PlayerState['stage'];
  }>;
  /** True iff winner.stage === ALIVE_PANTS_DOWN — unlocks 穿好裤衩. */
  canSelfRestore: boolean;
  budgetMs: number;
}

export interface RoomBroadcaster {
  emitSnapshot(snapshot: RoomSnapshot): void;
  emitRound(payload: RoundBroadcast): void;
  emitError(socketId: string, message: string): void;
  /** Send a winner-agency prompt to one specific socket. Optional to
   *  preserve backward compat with broadcasters that haven't been
   *  updated; missing implementation = engine auto-pick everywhere. */
  emitWinnerChoice?(socketId: string, prompt: WinnerChoicePrompt): void;
}

export interface RoomOptions {
  roomId: string;
  hostId: string;
  hostNickname: string;
  hostSocketId: string;
  /** Optional fixed seed (debugging / reproducible E2E). */
  seed?: number;
  broadcaster: RoomBroadcaster;
}

const MAX_PLAYERS = 6;

export class Room {
  readonly roomId: string;
  readonly seed: number;
  private hostId: string;
  private members: RoomMember[] = [];
  private players: PlayerState[] = [];
  private history: RoundHistoryEntry[] = [];
  private choices: Record<string, RpsChoice> = {};
  private phase: RoomSnapshot['phase'] = 'LOBBY';
  private round = 0;
  private lastNarration = '';
  /** §H3 collected winner choices for the in-flight round. Populated
   *  via submitWinnerChoice(); consumed when the choice window closes
   *  (either all human winners replied, or budget elapsed). */
  private pendingWinnerChoices: Record<
    string,
    { target: string | null; action: ActionKind | null }
  > = {};
  /** Set of human-winner ids we are waiting on this round. Empty when
   *  no choice window is open. */
  private awaitingWinners: Set<string> = new Set();
  /** Timer that fires the auto-pick fallback when the choice window
   *  expires. Reset every round. */
  private winnerChoiceTimer: ReturnType<typeof setTimeout> | null = null;
  private winnerId: string | null = null;
  private readonly broadcaster: RoomBroadcaster;

  constructor(opts: RoomOptions) {
    this.roomId = opts.roomId;
    this.hostId = opts.hostId;
    this.seed = opts.seed ?? ((Date.now() & 0x7fffffff) >>> 0);
    this.broadcaster = opts.broadcaster;
    this.addHuman(opts.hostId, opts.hostNickname, opts.hostSocketId);
  }

  /** Total members (humans + bots). */
  size(): number {
    return this.members.length;
  }

  isEmpty(): boolean {
    return this.members.filter((m) => !m.isBot).length === 0;
  }

  hasMember(id: string): boolean {
    return this.members.some((m) => m.id === id);
  }

  /** True if no human is left in the room (used by the server to GC empty rooms). */
  isAbandoned(): boolean {
    return this.members.every((m) => m.isBot);
  }

  /** Add a human player. Returns false if the room is full or game in progress. */
  addHuman(id: string, nickname: string, socketId: string): boolean {
    if (this.phase !== 'LOBBY') return false;
    if (this.members.length >= MAX_PLAYERS) return false;
    if (this.hasMember(id)) return false;
    this.members.push({ id, nickname, isBot: false, socketId });
    this.players.push({ id, nickname, stage: 'ALIVE_CLOTHED', isBot: false });
    this.broadcastSnapshot();
    return true;
  }

  /** Add a bot with a diversified strategy. Returns the bot's id, or null if full. */
  addBot(): string | null {
    if (this.phase !== 'LOBBY') return null;
    if (this.members.length >= MAX_PLAYERS) return null;
    const botIndex = this.members.filter((m) => m.isBot).length;
    const strategy = pickStrategyForIndex(botIndex);
    const id = `bot-${this.members.length}-${strategy.kind}`;
    const nickname = this.dedupeBotNickname(strategy.kind);
    const member: RoomMember = {
      id,
      nickname,
      isBot: true,
      socketId: undefined,
      bot: {
        kind: strategy.kind,
        strategy,
        rng: seededRng(this.seed, this.roomId, id),
      },
    };
    this.members.push(member);
    this.players.push({ id, nickname: member.nickname, stage: 'ALIVE_CLOTHED', isBot: true });
    this.broadcastSnapshot();
    return id;
  }

  /** §H1 dedupe — when 5+ bots are added we exhaust the 4-strategy
   *  registry and `pickStrategyForIndex(4)` returns the same kind as
   *  index 0, producing two bots with nickname 'counter'. To keep
   *  nameplates and roster lists disambiguated we suffix `#N` for the
   *  Nth duplicate (counter, counter#2, counter#3, …). */
  private dedupeBotNickname(baseKind: string): string {
    const used = new Set(this.members.map((m) => m.nickname));
    if (!used.has(baseKind)) return baseKind;
    for (let n = 2; n < 100; n++) {
      const candidate = `${baseKind}#${n}`;
      if (!used.has(candidate)) return candidate;
    }
    return baseKind;
  }

  /** Force a specific bot kind (admin / test path). */
  addBotOfKind(kind: BotKind): string | null {
    if (this.phase !== 'LOBBY') return null;
    if (this.members.length >= MAX_PLAYERS) return null;
    const strategy = getBotStrategy(kind);
    const id = `bot-${this.members.length}-${kind}`;
    const nickname = this.dedupeBotNickname(kind);
    const member: RoomMember = {
      id,
      nickname,
      isBot: true,
      socketId: undefined,
      bot: { kind, strategy, rng: seededRng(this.seed, this.roomId, id) },
    };
    this.members.push(member);
    this.players.push({ id, nickname: member.nickname, stage: 'ALIVE_CLOTHED', isBot: true });
    this.broadcastSnapshot();
    return id;
  }

  /** Remove a member (disconnect or kick). Returns true if the member was found. */
  remove(id: string): boolean {
    const idx = this.members.findIndex((m) => m.id === id);
    if (idx === -1) return false;
    this.members.splice(idx, 1);
    this.players = this.players.filter((p) => p.id !== id);
    delete this.choices[id];
    delete this.pendingWinnerChoices[id];
    if (this.awaitingWinners.delete(id) && this.awaitingWinners.size === 0) {
      // The departing player was the last winner blocking the choice
      // window; close it so the round can advance.
      this.closeWinnerChoiceWindow();
    }
    if (this.hostId === id && this.members.length > 0) {
      // Promote the first remaining human as new host; if no humans left,
      // pick the first member.
      const newHost = this.members.find((m) => !m.isBot) ?? this.members[0]!;
      this.hostId = newHost.id;
    }
    this.broadcastSnapshot();
    return true;
  }

  /** Host triggers game start. Returns false if not host or invalid state. */
  start(actorId: string): boolean {
    if (actorId !== this.hostId) return false;
    if (this.phase !== 'LOBBY') return false;
    if (this.members.length < 2) return false;
    this.phase = 'PLAYING';
    this.round = 0;
    this.history = [];
    this.choices = {};
    this.players = this.members.map((m) => ({
      id: m.id,
      nickname: m.nickname,
      stage: 'ALIVE_CLOTHED',
      isBot: m.isBot,
    }));
    this.lastNarration = '';
    this.winnerId = null;
    this.broadcastSnapshot();
    this.beginRound();
    return true;
  }

  /** A human submits an RPS choice. Bots auto-submit via beginRound. */
  submitChoice(actorId: string, choice: RpsChoice): boolean {
    if (this.phase !== 'PLAYING') return false;
    const member = this.members.find((m) => m.id === actorId);
    if (!member || member.isBot) return false;
    const player = this.players.find((p) => p.id === actorId);
    if (!player || player.stage === 'DEAD') return false;
    this.choices[actorId] = choice;
    this.broadcastSnapshot();
    if (this.allAliveSubmitted()) {
      this.openWinnerChoiceWindow();
    }
    return true;
  }

  /** §H3 a human winner submits their target+action choice. Either field
   *  may be null = leave it to engine auto-pick. Once every awaited
   *  winner has answered, the round resolves immediately (don't wait for
   *  the budget to expire). */
  submitWinnerChoice(
    actorId: string,
    payload: { target: string | null; action: ActionKind | null },
  ): boolean {
    if (this.phase !== 'PLAYING') return false;
    if (!this.awaitingWinners.has(actorId)) return false;
    this.pendingWinnerChoices[actorId] = {
      target: payload.target ?? null,
      action: payload.action ?? null,
    };
    this.awaitingWinners.delete(actorId);
    if (this.awaitingWinners.size === 0) {
      this.closeWinnerChoiceWindow();
    }
    return true;
  }

  /** Reset the room to LOBBY for a rematch (host only). */
  rematch(actorId: string): boolean {
    if (actorId !== this.hostId) return false;
    if (this.phase !== 'ENDED') return false;
    this.phase = 'LOBBY';
    this.round = 0;
    this.history = [];
    this.choices = {};
    this.players = this.members.map((m) => ({
      id: m.id,
      nickname: m.nickname,
      stage: 'ALIVE_CLOTHED',
      isBot: m.isBot,
    }));
    this.lastNarration = '';
    this.winnerId = null;
    this.broadcastSnapshot();
    return true;
  }

  // --- Internals ---------------------------------------------------------

  private beginRound(): void {
    this.round += 1;
    this.choices = {};
    // Auto-submit on behalf of every alive bot.
    for (const member of this.members) {
      if (!member.isBot || !member.bot) continue;
      const player = this.players.find((p) => p.id === member.id);
      if (!player || player.stage === 'DEAD') continue;
      const choice = member.bot.strategy.pickChoice(
        {
          selfId: member.id,
          round: this.round,
          players: this.players,
          history: this.history,
        },
        member.bot.rng,
      );
      this.choices[member.id] = choice;
    }
    this.broadcastSnapshot();
    // S-253 — spectator-mode auto-advance. When no humans are alive
    // (or no humans remain in the room at all), bots are the only
    // submitters; without this kick the round hangs forever waiting
    // for a human submitChoice() that will never come and the dead
    // human's client never sees R3+ effects. Defer one tick so the
    // snapshot broadcast above lands first (clients render the new
    // round number / hasSubmitted=true on bots before the effects
    // payload arrives).
    if (this.allAliveSubmitted()) {
      setImmediate(() => {
        if (this.phase === 'PLAYING' && this.allAliveSubmitted()) {
          this.openWinnerChoiceWindow();
        }
      });
    }
  }

  private allAliveSubmitted(): boolean {
    for (const player of this.players) {
      if (player.stage === 'DEAD') continue;
      if (this.choices[player.id] === undefined) return false;
    }
    return true;
  }

  /** §H3 begin the winner-choice window. Identifies human winners with
   *  meaningful agency (≥ 2 eligible targets OR self-restore unlocked)
   *  and broadcasts a WinnerChoicePrompt to each. Sets up a fallback
   *  timer that closes the window with whatever choices arrived. If no
   *  human has agency this round, resolve immediately. */
  private openWinnerChoiceWindow(): void {
    this.pendingWinnerChoices = {};
    this.awaitingWinners.clear();
    if (this.winnerChoiceTimer !== null) {
      clearTimeout(this.winnerChoiceTimer);
      this.winnerChoiceTimer = null;
    }

    // Preview RPS so we know the winners + losers up front. Engine's
    // resolveRps is pure — same call resolveRound makes downstream.
    const orderedChoices: Array<readonly [string, RpsChoice]> = [];
    for (const p of this.players) {
      if (p.stage === 'DEAD') continue;
      const c = this.choices[p.id];
      if (c === undefined) continue;
      orderedChoices.push([p.id, c]);
    }
    const preview = resolveRps(orderedChoices);

    // No agency on tie or empty rounds — resolve immediately.
    if (preview.tie) {
      this.resolveCurrentRound();
      return;
    }

    const losers = preview.losers
      .map((id) => this.players.find((p) => p.id === id))
      .filter((p): p is PlayerState => Boolean(p));

    // Find every human winner with meaningful agency.
    const promptsToSend: Array<{
      socketId: string;
      prompt: WinnerChoicePrompt;
    }> = [];
    for (const winnerId of preview.winners) {
      const member = this.members.find((m) => m.id === winnerId);
      if (!member || member.isBot || !member.socketId) continue;
      const winnerPlayer = this.players.find((p) => p.id === winnerId);
      if (!winnerPlayer) continue;
      const canSelfRestore = winnerPlayer.stage === 'ALIVE_PANTS_DOWN';
      const hasMultipleTargets = losers.length >= 2;
      // Even with one target the action picker can be valuable when
      // self-restore is on the table; otherwise skip.
      if (!hasMultipleTargets && !canSelfRestore) continue;
      this.awaitingWinners.add(winnerId);
      promptsToSend.push({
        socketId: member.socketId,
        prompt: {
          round: this.round,
          winnerId,
          winnerStage: winnerPlayer.stage,
          candidates: losers.map((p) => ({
            id: p.id,
            nickname: p.nickname,
            stage: p.stage,
          })),
          canSelfRestore,
          budgetMs: WINNER_CHOICE_BUDGET_MS,
        },
      });
    }

    if (this.awaitingWinners.size === 0) {
      this.resolveCurrentRound();
      return;
    }

    for (const { socketId, prompt } of promptsToSend) {
      this.broadcaster.emitWinnerChoice?.(socketId, prompt);
    }

    // Hard deadline — even if a client never replies, the room moves
    // forward. The engine's auto-pick takes over for any missing entry.
    this.winnerChoiceTimer = setTimeout(() => {
      this.closeWinnerChoiceWindow();
    }, WINNER_CHOICE_BUDGET_MS);
  }

  /** §H3 close the winner-choice window and resolve. Idempotent — safe
   *  to call from both the timer and the all-winners-replied path. */
  private closeWinnerChoiceWindow(): void {
    if (this.winnerChoiceTimer !== null) {
      clearTimeout(this.winnerChoiceTimer);
      this.winnerChoiceTimer = null;
    }
    this.awaitingWinners.clear();
    this.resolveCurrentRound();
  }

  private resolveCurrentRound(): void {
    const targets: Record<string, string> = {};
    const actions: Record<string, ActionKind> = {};
    for (const [winnerId, choice] of Object.entries(this.pendingWinnerChoices)) {
      if (choice.target !== null) targets[winnerId] = choice.target;
      if (choice.action !== null) actions[winnerId] = choice.action;
    }
    this.pendingWinnerChoices = {};
    const inputs: RoundInputs = {
      choices: { ...this.choices },
      targets,
      actions,
    };
    const result = resolveRound(this.players, this.round, inputs);
    this.players = result.players;
    this.lastNarration = result.narration;
    this.history = [
      ...this.history,
      {
        round: this.round,
        choices: { ...this.choices },
        ...(result.rps.winningChoice ? { winningChoice: result.rps.winningChoice } : {}),
      },
    ];

    this.broadcaster.emitRound({
      round: this.round,
      effects: result.effects,
      narration: result.narration,
      isGameOver: result.isGameOver,
      winnerId: result.winnerId,
    });

    if (result.isGameOver) {
      this.phase = 'ENDED';
      this.winnerId = result.winnerId;
      this.broadcastSnapshot();
      return;
    }

    // Schedule the next round to begin only after the current round's animation
    // finishes — uses the same canonical timing.ts constants the client honors.
    const isTie = result.rps.tie;
    const holdMs = isTie ? TIE_NARRATION_HOLD_MS : ROUND_TOTAL_MS;
    setTimeout(() => {
      if (this.phase === 'PLAYING') this.beginRound();
    }, holdMs);
  }

  private broadcastSnapshot(): void {
    this.broadcaster.emitSnapshot(this.snapshot());
  }

  snapshot(): RoomSnapshot {
    return {
      roomId: this.roomId,
      hostId: this.hostId,
      phase: this.phase,
      round: this.round,
      players: this.members.map((m, idx) => {
        const p = this.players.find((pp) => pp.id === m.id);
        return {
          id: m.id,
          nickname: m.nickname,
          isBot: m.isBot,
          stage: p?.stage ?? 'DEAD',
          isHost: m.id === this.hostId,
          hasSubmitted: this.choices[m.id] !== undefined,
          // S-430 — index into members[] is the canonical join order.
          // Removals shift indices but preserve relative order, which
          // matches the client's expectation that color stability is
          // per-room, not per-id forever.
          joinOrder: idx,
        };
      }),
      lastNarration: this.lastNarration,
      winnerId: this.winnerId,
    };
  }
}
