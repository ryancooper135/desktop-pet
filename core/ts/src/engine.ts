// Ядро питомца: состояние считается от времени (ленивый пересчёт), а не тикает в фоне.
// Шаг — ровно 1 минута, состояние двигается только целыми минутами, поэтому
// «посчитать сразу до T» и «посчитать по кускам до T» дают одно и то же.
// Порядок операций с плавающей точкой должен совпадать со Swift-версией (core/swift):
// общие тест-векторы в core/vectors сверяют обе.

import { DISTRESS, HOME_LINES, NEEDS } from './rules.ts';
import type { Distress, Effect, HomeLine, Need, Rules, Vals } from './rules.ts';

export interface Owner {
  bedMin: number;      // во сколько хозяин ложится, минуты от полуночи
  wakeMin: number;     // во сколько встаёт
  tzOffsetMin: number; // смещение местного времени от UTC
}

export interface PetState {
  t: number;                        // unix-секунды, до которых всё посчитано
  needs: Vals;
  hearts: number;                   // дробное, на экране половинки
  grace: Record<Distress, number>;  // бодрые часы хозяина подряд в беде
  lastChanceH: number | null;       // остаток «последнего шанса» на 1 сердце
  napUntil: number | null;
  bathUntil: number | null;
  lastHeartLossT: number | null;
  cooldowns: Record<string, number>; // действие или предмет → до какого t нельзя
  home: Record<HomeLine, number>;   // уровни улучшений, 0 — стартовый
  alive: boolean;
  diedAt: number | null;
  cause: Distress | null;
}

export type Action =
  | { type: 'feed'; item: string }
  | { type: 'item'; item: string }
  | { type: 'pet' }
  | { type: 'play' }
  | { type: 'bath' }
  | { type: 'steps'; count: number }
  | { type: 'wake' };

export interface ActResult { ok: boolean; reason?: string }

export const STEP = 60;
const DH = 1 / 60;
const CARE: Need[] = ['food', 'clean', 'fun', 'love', 'walk'];
export const WATCH: Need[] = ['food', 'clean', 'fun', 'love'];

export function defaultOwner(r: Rules, tzOffsetMin = 0): Owner {
  return { bedMin: r.night.bedMin, wakeMin: r.night.wakeMin, tzOffsetMin };
}

export function newPet(r: Rules, t: number): PetState {
  const needs = {} as Vals;
  for (const n of NEEDS) needs[n] = r.needs[n].start;
  const home = {} as Record<HomeLine, number>;
  for (const l of HOME_LINES) home[l] = 0;
  return {
    t, needs, hearts: r.hearts.max, grace: { starve: 0, dirty: 0, toska: 0 },
    lastChanceH: null, napUntil: null, bathUntil: null, lastHeartLossT: null, cooldowns: {},
    home, alive: true, diedAt: null, cause: null,
  };
}

export function clone(s: PetState): PetState {
  return structuredClone(s);
}

// ---------- время суток ----------

export function localMin(t: number, o: Owner): number {
  return (((Math.floor(t / 60) + o.tzOffsetMin) % 1440) + 1440) % 1440;
}

export function inWindow(m: number, from: number, to: number): boolean {
  const a = ((from % 1440) + 1440) % 1440, b = ((to % 1440) + 1440) % 1440;
  return a <= b ? m >= a && m < b : m >= a || m < b;
}

export function ownerAsleep(t: number, o: Owner): boolean {
  return inWindow(localMin(t, o), o.bedMin, o.wakeMin);
}

export function petNight(t: number, r: Rules, o: Owner): boolean {
  return inWindow(localMin(t, o), o.bedMin + r.night.afterBedMin, o.wakeMin + r.night.afterWakeMin);
}

// ---------- множители ----------

const clamp = (v: number) => (v < 0 ? 0 : v > 100 ? 100 : v);

function homeBuff(s: PetState, r: Rules, line: HomeLine): Effect {
  return r.home[line][s.home[line]] ?? {};
}

// Улучшения дома (по линиям в порядке HOME_LINES), затем перекрёстные эффекты в порядке конфига.
export function mods(s: PetState, r: Rules): Effect {
  const m: Effect = {};
  const add = (e: Effect) => {
    for (const k of Object.keys(e)) {
      const v = e[k];
      if (typeof v === 'number' && k.endsWith('_x')) m[k] = ((m[k] as number | undefined) ?? 1) * v;
      else m[k] = v;
    }
  };
  for (const l of HOME_LINES) add(homeBuff(s, r, l));
  for (const c of r.cross) if (c.cond(s.needs)) add(c.then);
  return m;
}

const x = (m: Effect, k: string) => (typeof m[k] === 'number' ? (m[k] as number) : 1);
const num = (m: Effect, k: string) => (typeof m[k] === 'number' ? (m[k] as number) : 0);

export function maxHearts(s: PetState, r: Rules): number {
  const b = homeBuff(s, r, 'kennel');
  return typeof b.max_hearts === 'number' ? b.max_hearts : r.hearts.max;
}

// ---------- шаг ----------

function finishBath(s: PetState, r: Rules) {
  const b = homeBuff(s, r, 'bath');
  s.needs.clean = 100;
  s.needs.fun = clamp(s.needs.fun + num(b, 'fun_after_bath'));
  s.needs.look = clamp(s.needs.look + num(b, 'look_after_bath'));
  s.bathUntil = null;
}

/** Один шаг в 1 минуту (на месте). Снаружи ядра зовите stepTo/advance. */
export function step(s: PetState, r: Rules, o: Owner) {
  const t = s.t;
  if (s.napUntil !== null && t >= s.napUntil) s.napUntil = null;
  if (s.bathUntil !== null && t >= s.bathUntil) finishBath(s, r);

  const asleep = ownerAsleep(t, o);
  const night = petNight(t, r, o);
  if (!night && petNight(t - STEP, r, o)) {
    s.needs.love = clamp(s.needs.love + num(homeBuff(s, r, 'bed'), 'love_on_wake'));
  }
  const en = r.needs.energy;
  if (!night && s.napUntil === null && s.bathUntil === null && s.needs.energy < en.nap_below) {
    s.napUntil = t + en.nap_minutes * 60;
  }
  const sleeping = night || s.napUntil !== null;
  const md = mods(s, r);
  const active = DISTRESS.map(d => r.distress[d].cond(s.needs));
  const ge = r.hearts.regenAllGe;
  const regenOk = WATCH.every(n => s.needs[n] >= ge);

  // шкалы
  for (const n of CARE) {
    const c = r.needs[n];
    const rate = sleeping ? c.night_per_h : c.day_per_h;
    let k = x(md, n + '_decay_x');
    if (n === 'food' && night) k = k * x(md, 'night_food_decay_x');
    s.needs[n] = clamp(s.needs[n] - rate * k * DH);
  }
  if (night) s.needs.energy = clamp(s.needs.energy + en.night_regen_per_h * x(md, 'night_energy_regen_x') * x(md, 'sleep_regen_x') * DH);
  else if (s.napUntil !== null) s.needs.energy = clamp(s.needs.energy + en.nap_regen_per_h * DH);
  else s.needs.energy = clamp(s.needs.energy - en.day_per_h * x(md, 'energy_decay_x') * DH);
  s.needs.look = clamp(s.needs.look - r.needs.look.per_day / 24 * DH);

  // сердца: урон и «льготы» копятся только в бодрые часы хозяина
  const h = r.hearts;
  let dmg = 0;
  let anyActive = false;
  DISTRESS.forEach((d, i) => {
    if (!active[i]) { s.grace[d] = 0; return; }
    anyActive = true;
    if (asleep) return;
    s.grace[d] = s.grace[d] + DH;
    const rd = r.distress[d];
    if (s.grace[d] > rd.graceH) dmg = dmg + DH / rd.hoursPerHeart;
  });
  if (dmg > 0 && s.hearts > 1) {
    const before = s.hearts;
    s.hearts = Math.max(1, s.hearts - dmg * x(md, 'heart_damage_x'));
    if (Math.ceil(s.hearts - 1e-9) < Math.ceil(before - 1e-9)) s.lastHeartLossT = t;
  }
  const maxH = maxHearts(s, r);
  if (!anyActive && regenOk && s.hearts < maxH) {
    s.hearts = Math.min(maxH, s.hearts + h.regenPerH * (asleep ? h.regenNightX : 1) * x(md, 'heart_regen_x') * DH);
  }

  // последнее сердце: таймер на бодрые часы, смерть не раньше чем через 3 ч после подъёма
  if (s.hearts > 1) s.lastChanceH = null;
  else {
    if (s.lastChanceH === null) s.lastChanceH = h.lastChanceH;
    if (!asleep && anyActive) {
      s.lastChanceH = s.lastChanceH - DH;
      const sinceWake = (localMin(t, o) - o.wakeMin + 1440) % 1440;
      if (s.lastChanceH <= 0 && sinceWake >= h.noDeathAfterWakeH * 60) {
        s.alive = false;
        s.diedAt = t + STEP;
        s.cause = DISTRESS[active.indexOf(true)];
      }
    }
  }
  s.t = t + STEP;
}

/** Досчитать состояние до момента T (на месте). Остаток меньше минуты ждёт следующего вызова. */
export function stepTo(s: PetState, r: Rules, o: Owner, T: number): PetState {
  while (s.alive && s.t + STEP <= T) step(s, r, o);
  return s;
}

export function advance(s: PetState, r: Rules, o: Owner, T: number): PetState {
  return stepTo(clone(s), r, o, T);
}

// ---------- действия ----------

function applyEffect(s: PetState, e: Effect, maxH: number) {
  for (const n of NEEDS) if (typeof e[n] === 'number') s.needs[n] = clamp(s.needs[n] + (e[n] as number));
  if (typeof e.hearts === 'number') s.hearts = Math.min(maxH, s.hearts + e.hearts);
}

/** Действие в момент s.t (сначала досчитай stepTo). Меняет s на месте. */
export function act(s: PetState, r: Rules, o: Owner, a: Action): ActResult {
  if (!s.alive) return { ok: false, reason: 'dead' };
  const t = s.t;
  const md = mods(s, r);
  const cooling = (k: string) => s.cooldowns[k] !== undefined && s.cooldowns[k] > t;
  switch (a.type) {
    case 'feed':
    case 'item': {
      const e = a.type === 'feed' ? r.food[a.item] : r.items[a.item];
      if (!e) return { ok: false, reason: 'unknown_item' };
      if (s.bathUntil !== null) return { ok: false, reason: 'bathing' };
      if (cooling(a.item)) return { ok: false, reason: 'cooldown' };
      if (a.type === 'feed') s.napUntil = null;
      applyEffect(s, e, maxHearts(s, r));
      if (typeof e.cooldown_h === 'number') s.cooldowns[a.item] = t + e.cooldown_h * 3600;
      return { ok: true };
    }
    case 'pet': {
      if (cooling('pet')) return { ok: false, reason: 'cooldown' };
      s.needs.love = clamp(s.needs.love + r.petLove * x(md, 'love_gain_x'));
      s.cooldowns.pet = t + r.petCooldownMin * 60;
      return { ok: true };
    }
    case 'play': {
      if (s.bathUntil !== null) return { ok: false, reason: 'bathing' };
      if (s.napUntil !== null || petNight(t, r, o)) return { ok: false, reason: 'asleep' };
      if (md.refuses_games === true) return { ok: false, reason: 'tired' };
      s.needs.fun = clamp(s.needs.fun + r.play.funGain * x(md, 'fun_gain_x'));
      s.needs.energy = clamp(s.needs.energy - r.play.energyCost);
      return { ok: true };
    }
    case 'bath': {
      if (s.bathUntil !== null) return { ok: false, reason: 'bathing' };
      s.napUntil = null;
      s.bathUntil = t + r.bathMinutes[s.home.bath] * 60;
      return { ok: true };
    }
    case 'steps': {
      s.needs.walk = clamp(s.needs.walk + a.count / r.needs.walk.steps_per_point);
      return { ok: true };
    }
    case 'wake': {
      if (s.napUntil === null) return { ok: false, reason: 'not_napping' };
      s.napUntil = null;
      return { ok: true };
    }
  }
}

// ---------- что показывать ----------

/** 0 — всё хорошо, 1 «Просит», 2 «Плохо», 3 «Критично». */
export function level(s: PetState, r: Rules): number {
  if (!s.alive || s.hearts <= 2) return 3;
  if (DISTRESS.some(d => r.distress[d].cond(s.needs))) return 2;
  if (s.lastHeartLossT !== null && s.t - s.lastHeartLossT < 12 * 3600) return 2;
  if (WATCH.some(n => s.needs[n] < r.warnLow)) return 1;
  return 0;
}

/** Видимые состояния для виджета и острова. */
export function moods(s: PetState, r: Rules, o: Owner): string[] {
  if (!s.alive) return ['dead'];
  const out: string[] = [];
  if (s.bathUntil !== null) out.push('bath');
  if (petNight(s.t, r, o)) out.push('sleep');
  else if (s.napUntil !== null) out.push('nap');
  if (level(s, r) === 3) out.push('critical');
  const v = s.needs;
  if (v.food < 25) out.push('hungry');
  if (v.clean < 10) out.push('smelly');
  else if (v.clean < 25) out.push('dirty');
  if (v.energy < 20) out.push('tired');
  if (v.fun < 30) out.push('bored');
  if (v.love < 35) out.push('wants_love');
  return out;
}

export interface ForecastEvent {
  t: number;
  kind: 'low' | 'distress' | 'heart' | 'last_chance' | 'level' | 'death';
  key?: string;
  value?: number;
}

/** Что уже было до начала наблюдения: от этого считаются новые события прогноза. */
export interface Tracker { low: Set<Need>; dist: Set<Distress>; lvl: number; hc: number; lc: boolean }

export function tracker(s: PetState, r: Rules): Tracker {
  return {
    low: new Set(WATCH.filter(n => s.needs[n] < r.warnLow)),
    dist: new Set(DISTRESS.filter(d => r.distress[d].cond(s.needs))),
    lvl: level(s, r),
    hc: Math.ceil(s.hearts - 1e-9),
    lc: s.lastChanceH !== null,
  };
}

/** После шага: дописать в ev новые события (low, distress, heart, last_chance, level). */
export function observe(tr: Tracker, s: PetState, r: Rules, ev: ForecastEvent[]) {
  for (const n of WATCH) if (s.needs[n] < r.warnLow && !tr.low.has(n)) { tr.low.add(n); ev.push({ t: s.t, kind: 'low', key: n }); }
  for (const d of DISTRESS) {
    const on = r.distress[d].cond(s.needs);
    if (on && !tr.dist.has(d)) { tr.dist.add(d); ev.push({ t: s.t, kind: 'distress', key: d }); }
    if (!on) tr.dist.delete(d);
  }
  const c = Math.ceil(s.hearts - 1e-9);
  if (c < tr.hc) ev.push({ t: s.t, kind: 'heart', value: c });
  tr.hc = c;
  if (s.lastChanceH !== null && !tr.lc) ev.push({ t: s.t, kind: 'last_chance' });
  tr.lc = s.lastChanceH !== null;
  const l = level(s, r);
  if (l !== tr.lvl) { ev.push({ t: s.t, kind: 'level', value: l }); tr.lvl = l; }
}

/** Что случится, если никто не придёт: для локальных уведомлений и «умрёт в чт ~15:00». */
export function forecast(s0: PetState, r: Rules, o: Owner, horizonH = 72): ForecastEvent[] {
  const s = clone(s0);
  const end = s.t + horizonH * 3600;
  const ev: ForecastEvent[] = [];
  const tr = tracker(s, r);
  while (s.alive && s.t + STEP <= end) {
    step(s, r, o);
    observe(tr, s, r, ev);
  }
  if (!s.alive) ev.push({ t: s.diedAt ?? s.t, kind: 'death', key: s.cause ?? undefined });
  return ev;
}
