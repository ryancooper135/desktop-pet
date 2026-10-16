// Сценарии ухода из RESEARCH/04 §2.2: ими проверяем баланс и из них же собираем тест-векторы.

import { act, defaultOwner, newPet, stepTo } from './engine.ts';
import type { Action, Owner, PetState } from './engine.ts';
import type { Rules } from './rules.ts';

export interface TimedAction { t: number; action: Action }

/** Полночь по UTC 1 сентября 2026 (вторник) — старт всех сценариев, местное время = UTC. */
export const T0 = Date.UTC(2026, 8, 1) / 1000;
const H = 3600;

export function startAt(r: Rules, hour: number, fill = 80): PetState {
  const s = newPet(r, T0 + hour * H);
  for (const n of ['food', 'clean', 'energy', 'fun', 'love', 'walk'] as const) s.needs[n] = fill;
  return s;
}

/** Обычный заход: покормить по голоду, погладить 3 раза, поиграть, искупать если грязный. */
export function visit(s: PetState, bath: boolean): Action[] {
  const a: Action[] = [];
  if (s.needs.food < 70) a.push({ type: 'feed', item: 'stew' });
  if (s.needs.food < 40) a.push({ type: 'feed', item: 'kibble' });
  a.push({ type: 'pet' });
  if (s.needs.fun < 85) a.push({ type: 'play' });
  if (bath && s.needs.clean < 60) a.push({ type: 'bath' });
  return a;
}

export interface RunResult { state: PetState; log: TimedAction[]; minHearts: number }

/**
 * Прогнать дни ухода: visits — часы заходов, steps — шагов в день (раздаются в 18:00),
 * careless — заход только с едой.
 */
export function runDays(r: Rules, o: Owner, s: PetState, days: number, visits: number[], opts: { steps?: number; careless?: boolean | 2; full?: boolean } = {}): RunResult {
  const log: TimedAction[] = [];
  let minHearts = s.hearts;
  const day0 = Math.floor((s.t - T0) / 86400);
  const plan: { t: number; kind: 'visit' | 'steps'; bath?: boolean }[] = [];
  for (let d = day0; d < day0 + days; d++) {
    visits.forEach((h, i) => plan.push({ t: T0 + d * 86400 + h * H, kind: 'visit', bath: i === 1 || visits.length === 1 }));
    if (opts.steps) plan.push({ t: T0 + d * 86400 + 18 * H, kind: 'steps' });
  }
  plan.sort((a, b) => a.t - b.t);
  const pet = (t: number, action: Action) => {
    if (act(s, r, o, action).ok) log.push({ t, action });
  };
  for (const p of plan) {
    if (p.t < s.t) continue;
    while (s.alive && s.t + 3600 <= p.t) { stepTo(s, r, o, s.t + 3600); minHearts = Math.min(minHearts, s.hearts); }
    stepTo(s, r, o, p.t);
    if (!s.alive) break;
    if (p.kind === 'steps') { pet(s.t, { type: 'steps', count: opts.steps! }); continue; }
    if (opts.careless) { pet(s.t, { type: 'feed', item: 'stew' }); pet(s.t, { type: 'feed', item: 'carrot' }); continue; }
    if (opts.full) { fillUp(s, r, o, pet); continue; }
    for (const a of visit(s, p.bath!)) {
      if (a.type === 'pet') {
        // три поглаживания с паузой в кулдаун
        for (let k = 0; k < 3; k++) { pet(s.t, a); stepTo(s, r, o, s.t + r.petCooldownMin * 60); }
      } else pet(s.t, a);
    }
  }
  const end = T0 + (day0 + days) * 86400;
  while (s.alive && s.t + 3600 <= end) { stepTo(s, r, o, s.t + 3600); minHearts = Math.min(minHearts, s.hearts); }
  return { state: s, log, minHearts };
}

/** Заход «до максимума»: кормить до сытости, гладить и играть до упора, купать. */
function fillUp(s: PetState, r: Rules, o: Owner, pet: (t: number, a: Action) => void) {
  for (let k = 0; k < 4 && s.needs.food < 70; k++) pet(s.t, { type: 'feed', item: 'stew' });
  if (s.needs.clean < 60) { pet(s.t, { type: 'bath' }); stepTo(s, r, o, s.bathUntil ?? s.t); stepTo(s, r, o, s.t + 60); }
  for (let k = 0; k < 6 && s.needs.fun < 90 && s.needs.energy > 25; k++) pet(s.t, { type: 'play' });
  for (let k = 0; k < 10 && s.needs.love < 95; k++) { pet(s.t, { type: 'pet' }); stepTo(s, r, o, s.t + r.petCooldownMin * 60); }
}

export function ignoreUntilDeath(r: Rules, o: Owner, s: PetState, maxH = 200): number | null {
  const start = s.t;
  stepTo(s, r, o, start + maxH * H);
  return s.alive ? null : (s.diedAt! - start) / H;
}

export { defaultOwner };
