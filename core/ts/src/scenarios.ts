// Сценарии ухода из RESEARCH/04 §2.2: ими проверяем баланс и из них же собираем тест-векторы.

import { STEP, act, defaultOwner, level, newPet, step, stepTo } from './engine.ts';
import type { Action, ActResult, Owner, PetState } from './engine.ts';
import { DISTRESS, NEEDS } from './rules.ts';
import type { Distress, Rules, Vals } from './rules.ts';

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

/** Подмена act: шпион в тестах, варианты баланса в balance.ts. */
export type ActFn = (s: PetState, r: Rules, o: Owner, a: Action) => ActResult;

export interface RunOpts {
  steps?: number;      // шагов в день
  careless?: boolean;  // заход только с едой
  full?: boolean;      // заход «до максимума»
  noBath?: boolean;    // никогда не купает
  away?: [number, number][]; // часы от полуночи первого дня [с, по): заходы в этих окнах пропускаются
  act?: ActFn;
}

export interface RunResult {
  state: PetState;
  log: TimedAction[];
  minHearts: number;
  avgNeeds: Vals;      // среднее по почасовым замерам, пока жив
  firstBadT: number | null;  // первый момент уровня ≥ 2 («Плохо»), с точностью до минуты вне заходов
  firstLossT: number | null; // первое потерянное сердце (целое на экране стало меньше)
  heartsByDay: number[];     // сердца на старте и через 1, 2, … суток; после смерти 0
}

/** Индекс захода, с которым приходят шаги дня: первый заход с 18:00, иначе последний заход дня. */
function stepsVisit(visits: number[]): number {
  const i = visits.findIndex(h => h >= 18);
  return i >= 0 ? i : visits.length - 1;
}

/**
 * Прогнать дни ухода: visits — часы заходов. Шаги дня (opts.steps) приходят при заходе
 * (см. stepsVisit) и начисляются до действий этого захода.
 */
export function runDays(r: Rules, o: Owner, s: PetState, days: number, visits: number[], opts: RunOpts = {}): RunResult {
  const doAct = opts.act ?? act;
  const log: TimedAction[] = [];
  let minHearts = s.hearts;
  const sum = {} as Vals;
  for (const n of NEEDS) sum[n] = 0;
  let samples = 0;
  const tStart = s.t;
  let firstBadT: number | null = null;
  let firstLossT: number | null = null;
  const hc0 = Math.ceil(s.hearts - 1e-9);
  const heartsByDay: number[] = [];
  // то же, что stepTo, но с наблюдением после каждой минуты: «Плохо» и сердца по суткам
  const watch = () => {
    if (firstBadT === null && level(s, r) >= 2) firstBadT = s.t;
    if (firstLossT === null && Math.ceil(s.hearts - 1e-9) < hc0) firstLossT = s.t;
    while (s.t >= tStart + heartsByDay.length * 86400 && heartsByDay.length < days) heartsByDay.push(s.hearts);
  };
  const go = (T: number) => {
    while (s.alive && s.t + STEP <= T) { step(s, r, o); watch(); }
  };
  watch();
  const hour = () => {
    go(s.t + 3600);
    minHearts = Math.min(minHearts, s.hearts);
    if (!s.alive) return;
    for (const n of NEEDS) sum[n] += s.needs[n];
    samples++;
  };
  const day0 = Math.floor((s.t - T0) / 86400);
  const si = stepsVisit(visits);
  const plan: { t: number; bath: boolean; steps: boolean }[] = [];
  const end = T0 + (day0 + days) * 86400;
  const away = (t: number) => (opts.away ?? []).some(([a, b]) => t >= T0 + (day0 * 24 + a) * H && t < T0 + (day0 * 24 + b) * H);
  for (let d = day0; d < day0 + days; d++) {
    visits.forEach((h, i) => {
      const t = T0 + d * 86400 + h * H;
      if (t < end && !away(t)) plan.push({ t, bath: !opts.noBath && (i === 1 || visits.length === 1), steps: !!opts.steps && i === si });
    });
  }
  plan.sort((a, b) => a.t - b.t);
  const pet = (t: number, action: Action) => {
    if (doAct(s, r, o, action).ok) log.push({ t, action });
  };
  for (const p of plan) {
    if (p.t < s.t) continue;
    while (s.alive && s.t + 3600 <= p.t) hour();
    go(p.t);
    if (!s.alive) break;
    if (p.steps) pet(s.t, { type: 'steps', count: opts.steps! });
    if (opts.careless) { pet(s.t, { type: 'feed', item: 'stew' }); pet(s.t, { type: 'feed', item: 'carrot' }); continue; }
    if (opts.full) { fillUp(s, r, o, pet); continue; }
    for (const a of visit(s, p.bath)) {
      if (a.type === 'pet') {
        // три поглаживания с паузой в кулдаун
        for (let k = 0; k < 3; k++) { pet(s.t, a); stepTo(s, r, o, s.t + r.petCooldownMin * 60); }
      } else pet(s.t, a);
    }
  }
  while (s.alive && s.t + 3600 <= end) hour();
  while (heartsByDay.length < days && !s.alive) heartsByDay.push(0);
  const avgNeeds = {} as Vals;
  for (const n of NEEDS) avgNeeds[n] = samples ? sum[n] / samples : s.needs[n];
  return { state: s, log, minHearts, avgNeeds, firstBadT, firstLossT, heartsByDay };
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
  return s.alive ? null : ((s.diedAt ?? s.t) - start) / H;
}

// ---------- именованные сценарии для balance.ts, векторов и тестов ----------

export interface Scenario {
  key: string; title: string; short: string; visits: number[]; opts: RunOpts;
  owner?: { bedMin: number; wakeMin: number };  // свой график сна хозяина (иначе из конфига)
}

/** Все стартуют в 07:30 со шкалами 80. short — заголовок колонки в таблице вариантов. */
export const SCENARIOS: Scenario[] = [
  { key: 'visits4_steps', title: '4 захода (8, 13, 18, 22:30) + 6000 шагов', short: '4 + шаги', visits: [8, 13, 18, 22.5], opts: { steps: 6000 } },
  { key: 'visits3', title: '3 захода (8, 14, 21)', short: '3', visits: [8, 14, 21], opts: {} },
  { key: 'visits2', title: '2 обычных захода (9, 21)', short: '2', visits: [9, 21], opts: {} },
  { key: 'careless2', title: '2 захода (9, 21), только покормить', short: '2, только еда', visits: [9, 21], opts: { careless: true } },
  { key: 'full1_noon', title: '1 заход «до максимума» в 12:00', short: '1 до максимума', visits: [12], opts: { full: true } },
  { key: 'visits1', title: '1 обычный заход в 12:00', short: '1 обычный', visits: [12], opts: {} },
  { key: 'careless1', title: '1 заход в 12:00, только покормить', short: '1, только еда', visits: [12], opts: { careless: true } },
];

export const START_HOUR = 7.5;

/**
 * Образы игроков для выбора строгости смерти (RESEARCH/12-balance-options.md).
 * Старт во вторник 07:30. Окна away — часы от полуночи первого дня: пт 21:30 = 3 × 24 + 21,5.
 */
export const PATTERNS: Scenario[] = [
  { key: 'carer', title: 'Заботливый: 4 захода + 6000 шагов', short: 'заботливый', visits: [8, 13, 18, 22.5], opts: { steps: 6000 } },
  { key: 'regular', title: 'Обычный: 3 захода (8, 14, 21)', short: 'обычный', visits: [8, 14, 21], opts: {} },
  { key: 'busy2', title: 'Занятой: 2 захода (9, 21)', short: 'занятой', visits: [9, 21], opts: {} },
  { key: 'feed2', title: '2 захода (9, 21), только покормить', short: '2 × еда', visits: [9, 21], opts: { careless: true } },
  { key: 'evening1', title: '1 заход в 20:00 после работы', short: '1 вечером', visits: [20], opts: {} },
  { key: 'feed1', title: '1 заход в 12:00, только покормить', short: '1 × еда', visits: [12], opts: { careless: true } },
  { key: 'nobath', title: '3 захода, но не купает', short: 'не купает', visits: [8, 14, 21], opts: { noBath: true } },
  { key: 'owl', title: 'Сова: спит 02:00–10:00, заходы в 12 и 01', short: 'сова', visits: [12, 25], opts: {}, owner: { bedMin: 120, wakeMin: 600 } },
  { key: 'weekend', title: '3 захода, выходные без захода (пт 21 → вс 21, 48 ч)', short: 'выходные 48 ч', visits: [8, 14, 21], opts: { away: [[3 * 24 + 21.5, 5 * 24 + 21]] } },
  { key: 'vacation', title: '3 захода, отпуск 5 суток (пт 21 → ср 21)', short: 'отпуск 5 сут', visits: [8, 14, 21], opts: { away: [[3 * 24 + 21.5, 8 * 24 + 21]] } },
];

export function scenario(key: string): Scenario {
  const sc = SCENARIOS.find(x => x.key === key);
  if (!sc) throw new Error(`нет сценария ${key}`);
  return sc;
}

export interface Summary {
  diedDay: number | null;  // сутки от старта до смерти, null — дожил до конца прогона
  causes: Distress[];      // беды, активные в момент смерти (state.cause — только первая из них)
  minHearts: number;
  avgNeeds: Vals;
  firstBadH: number | null;  // часы от старта до первого «Плохо»
  firstLossH: number | null; // часы от старта до первого потерянного сердца
}

/** Прогнать именованный сценарий с 07:30 на days суток. act — подмена для вариантов баланса. */
export function runScenario(r: Rules, o: Owner, sc: Scenario, days: number, act?: ActFn): RunResult & Summary {
  const s = startAt(r, START_HOUR);
  const t0 = s.t;
  const ow = sc.owner ? { ...o, ...sc.owner } : o;
  const res = runDays(r, ow, s, days, sc.visits, act ? { ...sc.opts, act } : sc.opts);
  const st = res.state;
  const causes = st.alive ? [] : DISTRESS.filter(d => r.distress[d].cond(st.needs));
  const h = (t: number | null) => t === null ? null : (t - t0) / 3600;
  return { ...res, diedDay: st.diedAt === null ? null : (st.diedAt - t0) / 86400, causes, firstBadH: h(res.firstBadT), firstLossH: h(res.firstLossT) };
}

export { defaultOwner };
