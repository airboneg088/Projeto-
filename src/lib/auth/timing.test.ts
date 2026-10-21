import { describe, expect, it } from "vitest";

import {
  PASSWORD_RESET_MIN_MS,
  SIGN_IN_FAILURE_MIN_MS,
  startTimer,
  waitUntilElapsed,
} from "./timing";

function fakeClock(start = 1000) {
  let now = start;
  const sleeps: number[] = [];
  return {
    sleeps,
    advance: (ms: number) => {
      now += ms;
    },
    clock: {
      now: () => now,
      sleep: async (ms: number) => {
        sleeps.push(ms);
        now += ms;
      },
    },
  };
}

describe("waitUntilElapsed", () => {
  it("completa o tempo que falta até o piso", async () => {
    const { clock, advance, sleeps } = fakeClock();
    const started = startTimer(clock);
    advance(120); // resposta rápida (ex.: e-mail que não existe)
    await waitUntilElapsed(started, SIGN_IN_FAILURE_MIN_MS, clock);
    expect(sleeps).toEqual([SIGN_IN_FAILURE_MIN_MS - 120]);
    expect(clock.now() - started).toBe(SIGN_IN_FAILURE_MIN_MS);
  });

  it("respostas rápidas e lentas terminam no mesmo tempo", async () => {
    const totals: number[] = [];
    for (const natural of [5, 80, 400]) {
      const { clock, advance } = fakeClock();
      const started = startTimer(clock);
      advance(natural);
      await waitUntilElapsed(started, PASSWORD_RESET_MIN_MS, clock);
      totals.push(clock.now() - started);
    }
    expect(new Set(totals)).toEqual(new Set([PASSWORD_RESET_MIN_MS]));
  });

  it("não espera quando o piso já passou", async () => {
    const { clock, advance, sleeps } = fakeClock();
    const started = startTimer(clock);
    advance(SIGN_IN_FAILURE_MIN_MS + 50);
    await waitUntilElapsed(started, SIGN_IN_FAILURE_MIN_MS, clock);
    expect(sleeps).toEqual([]);
  });

  it("usa o relógio real por padrão", async () => {
    const started = startTimer();
    await waitUntilElapsed(started, 30);
    expect(performance.now() - started).toBeGreaterThanOrEqual(30);
  });
});
