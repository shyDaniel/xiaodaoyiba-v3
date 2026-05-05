// sim.test.ts — locks in the strict-mode exit-code policy.
//
// FINAL_GOAL §A2 acceptance gate: a 50-round canonical run (seed=42, four
// bots: counter,random,iron,mirror) must never breach the budget. Conversely,
// a known-bad scenario (a degenerate 2-player mirror,mirror room at seed=1)
// must trip --strict and return exit 1. The known-bad guard proves the CI
// gate actually works — without it, a future refactor could silently turn
// `--strict` into a no-op.
//
// History note: prior to S-334 the canonical 4-bot pool tripped on seeds
// 7,12,15,21,22,24,30,34,39,40,41 due to undiversified bot strategies.
// Those seeds now PASS thanks to per-bot seed-derived hyperparameters and
// a cooperative tie-break escape, so the known-bad guard had to move to a
// pathological 2-player mirror,mirror config (still seed-deterministic).

import { describe, expect, it, afterEach, beforeEach } from 'vitest';
import { main, parseArgs } from './sim.js';

/** Captures stdout + stderr writes during a single sim invocation. */
function withCapturedIO<T>(fn: () => T): { result: T; stdout: string; stderr: string } {
  const realOut = process.stdout.write.bind(process.stdout);
  const realErr = process.stderr.write.bind(process.stderr);
  let stdout = '';
  let stderr = '';
  process.stdout.write = ((chunk: string | Uint8Array): boolean => {
    stdout += typeof chunk === 'string' ? chunk : Buffer.from(chunk).toString();
    return true;
  }) as typeof process.stdout.write;
  process.stderr.write = ((chunk: string | Uint8Array): boolean => {
    stderr += typeof chunk === 'string' ? chunk : Buffer.from(chunk).toString();
    return true;
  }) as typeof process.stderr.write;
  try {
    const result = fn();
    return { result, stdout, stderr };
  } finally {
    process.stdout.write = realOut;
    process.stderr.write = realErr;
  }
}

describe('sim CLI strict-mode exit-code policy', () => {
  it('parses --strict and --no-strict explicitly', () => {
    expect(parseArgs(['--rounds', '5']).strict).toBe(false);
    expect(parseArgs(['--rounds', '20']).strict).toBe(true);
    expect(parseArgs(['--rounds', '50']).strict).toBe(true);
    expect(parseArgs(['--rounds', '5', '--strict']).strict).toBe(true);
    expect(parseArgs(['--rounds', '50', '--no-strict']).strict).toBe(false);
  });

  it('canonical seed=42, 50 rounds, 4 bots: exits 0 (§A2 budget holds)', () => {
    const { result, stdout, stderr } = withCapturedIO(() =>
      main([
        '--players', '4',
        '--bots', 'counter,random,iron,mirror',
        '--rounds', '50',
        '--seed', '42',
        '--quiet',
      ]),
    );
    expect(result).toBe(0);
    expect(stdout).toContain('=== summary ===');
    expect(stdout).toMatch(/seed=42/);
    expect(stderr).not.toContain('FAIL: §A2 budget breach');
  });

  it('known-bad mirror-only room exits 1 under --strict (§A2 breach detected)', () => {
    // 2-player mirror,mirror at seed=1 produces ~46% ties (above the 0.45
    // per-seed budget). This is a degenerate config, not a target for
    // production rooms — it exists purely to prove --strict actually
    // escalates a budget breach to exit-1.
    const { result, stderr } = withCapturedIO(() =>
      main([
        '--players', '2',
        '--bots', 'mirror',
        '--rounds', '50',
        '--seed', '1',
        '--quiet',
      ]),
    );
    expect(result).toBe(1);
    expect(stderr).toContain('FAIL: §A2 budget breach');
  });

  it('known-bad config with --no-strict: warns to stderr but exits 0', () => {
    const { result, stderr } = withCapturedIO(() =>
      main([
        '--players', '2',
        '--bots', 'mirror',
        '--rounds', '50',
        '--seed', '1',
        '--no-strict',
        '--quiet',
      ]),
    );
    expect(result).toBe(0);
    // The warn line is still emitted, just doesn't escalate to a fail.
    expect(stderr).toMatch(/warn: (tie_rate|.*wins).*FINAL_GOAL §A2/);
    expect(stderr).not.toContain('FAIL: §A2 budget breach');
  });

  it('short --rounds 10 run: not strict by default, no exit-1 from breaches', () => {
    const { result } = withCapturedIO(() =>
      main([
        '--players', '4',
        '--bots', 'counter,random,iron,mirror',
        '--rounds', '10',
        '--seed', '7',
        '--quiet',
      ]),
    );
    // Even if seed=7 trips budgets in 10 rounds, default for <20 is non-strict.
    expect(result).toBe(0);
  });

  it('--help exits 0 with no sim run', () => {
    const { result, stdout } = withCapturedIO(() => main(['--help']));
    expect(result).toBe(0);
    expect(stdout).toContain('xdyb-sim');
    expect(stdout).toContain('Registered strategies:');
  });

  it('bad flag exits 2 with usage hint', () => {
    const { result, stderr } = withCapturedIO(() => main(['--garbage']));
    expect(result).toBe(2);
    expect(stderr).toContain('unknown flag');
  });
});

// Restore in case the test process is reused (vitest pools workers).
beforeEach(() => {
  /* noop — withCapturedIO finally-blocks already restore. */
});
afterEach(() => {
  /* noop — withCapturedIO finally-blocks already restore. */
});
