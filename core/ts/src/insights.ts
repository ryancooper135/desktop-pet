// Что показать и когда позвать: желания для пузыря, одно настроение для реплик, «Пока тебя не было»,
// кнопка «Спасти» и план локальных уведомлений. Всё считается из состояния ядра и не меняет баланс.
// Swift-порт — core/swift/Sources/PetCore/Insights.swift, сверка по общим векторам core/vectors.
// Имена верхнего уровня не должны совпадать с engine.ts и rules.ts: бандл склеивает их в одну область.

import { DISTRESS, NEEDS } from './rules.ts';
import type { Distress, Need, Rules } from './rules.ts';
import { STEP, WATCH, act, advance, clone, forecast, inWindow, level, localMin, maxHearts, mods, observe, petNight, step, tracker } from './engine.ts';
import type { Action, ForecastEvent, Owner, PetState } from './engine.ts';

// Ключи совпадают с content/ru/lines.json: желания — thoughts, настроения — widget/island, триггеры — notifications, экран — away.
export type WantKey = 'food' | 'bath' | 'sleep' | 'play' | 'pet' | 'walk';
export type Mood = 'dead' | 'critical' | 'bath' | 'sleep' | 'nap' | 'hungry' | 'smelly' | 'dirty' | 'tired' | 'bored' | 'wants_love' | 'wants_walk' | 'sulky' | 'ok';
export type Daypart = 'morning' | 'day' | 'evening' | 'night';
export type Trigger = 'hungry' | 'dirty' | 'smelly' | 'bored' | 'wants_love' | 'unwell' | 'heart_lost' | 'critical' | 'last_chance' | 'miss_you';

// Пороги показа (не баланс): from — с какого значения шкалы питомец начинает хотеть,
// mood — ниже какого значения желание становится настроением, w — вес при сортировке.
interface WantSpec { key: WantKey; need: Need; from: number; mood: number; w: number; moodKey: Mood | null }
export const WANT_SPECS: WantSpec[] = [
  { key: 'food', need: 'food', from: 50, mood: 25, w: 1, moodKey: 'hungry' },
  { key: 'bath', need: 'clean', from: 50, mood: 25, w: 0.8, moodKey: 'dirty' }, // ниже SMELLY_BELOW — smelly
  { key: 'sleep', need: 'energy', from: 30, mood: 20, w: 0.6, moodKey: 'tired' },
  { key: 'play', need: 'fun', from: 50, mood: 30, w: 0.7, moodKey: 'bored' },
  { key: 'pet', need: 'love', from: 50, mood: 35, w: 0.7, moodKey: 'wants_love' },
  { key: 'walk', need: 'walk', from: 30, mood: 15, w: 0.4, moodKey: 'wants_walk' },
];
const WANT_DISTRESS: Record<Distress, WantKey[]> = { starve: ['food'], dirty: ['bath'], toska: ['play', 'pet'] };
const SMELLY_BELOW = 10;        // как в moods(): чистота ниже — smelly, ниже 25 — dirty
const PART_MIN = 180;           // утро — 3 ч после подъёма питомца, вечер — 3 ч до отбоя хозяина
const AWAY_SHOW_H = 2;          // экран «Пока тебя не было» — после ≥ 2 ч (04 §6.4)
const AWAY_LONG_H = 24;         // от суток — welcome_long
const N_CARE_DAYS = 3;          // RESEARCH/07 #6: 3 дня без открытий — только «скучаю»
const N_MISS_EVERY_DAYS = 3;    // «скучаю» раз в 3 дня
const N_STOP_DAYS = 14;         // после 14 дней — тишина
const N_LEAD_MIN = 60;          // не звать раньше чем через час после «сейчас»: человек только что всё видел
const NEED_TRIGGER: Partial<Record<Need, Trigger>> = { food: 'hungry', clean: 'dirty', fun: 'bored', love: 'wants_love' };
const DISTRESS_TRIGGER: Record<Distress, Trigger> = { starve: 'hungry', dirty: 'smelly', toska: 'unwell' };

const at = (s: PetState, r: Rules, o: Owner, now?: number) => (now !== undefined && now > s.t ? advance(s, r, o, now) : s);
const sleepingNow = (s: PetState, r: Rules, o: Owner) => petNight(s.t, r, o) || s.napUntil !== null;

// ---------- желания ----------

export interface Want { key: WantKey; strength: number; urgent: boolean }

/** Желания для пузыря мысли: срочные (идёт беда) первыми, дальше по силе 0..1. Пусто — ничего не хочет. */
export function wants(s0: PetState, r: Rules, o: Owner, now?: number): Want[] {
  const s = at(s0, r, o, now);
  if (!s.alive) return [];
  const bathing = s.bathUntil !== null, sleeping = sleepingNow(s, r, o);
  const tired = mods(s, r).refuses_games === true;
  const urgent = new Set<WantKey>();
  for (const d of DISTRESS) if (r.distress[d].cond(s.needs)) for (const k of WANT_DISTRESS[d]) urgent.add(k);
  const out: (Want & { i: number })[] = [];
  WANT_SPECS.forEach((w, i) => {
    if (bathing && (w.key === 'food' || w.key === 'bath' || w.key === 'play')) return;
    if (sleeping && (w.key === 'sleep' || w.key === 'play')) return;
    if (tired && w.key === 'play') return;
    const v = s.needs[w.need];
    if (v >= w.from) return;
    const strength = Math.min(1, w.w * (w.from - v) / w.from);
    out.push({ key: w.key, strength, urgent: urgent.has(w.key), i });
  });
  out.sort((a, b) => (a.urgent !== b.urgent ? (a.urgent ? -1 : 1) : b.strength !== a.strength ? b.strength - a.strength : a.i - b.i));
  return out.map(({ key, strength, urgent }) => ({ key, strength, urgent }));
}

// ---------- настроение ----------

/** Одно настроение для реплик виджета и острова. */
export function mood(s0: PetState, r: Rules, o: Owner, now?: number): Mood {
  const s = at(s0, r, o, now);
  if (!s.alive) return 'dead';
  const lv = level(s, r);
  if (lv === 3) return 'critical';
  if (s.bathUntil !== null) return 'bath';
  if (petNight(s.t, r, o)) return 'sleep';
  if (s.napUntil !== null) return 'nap';
  for (const w of wants(s, r, o)) {
    const spec = WANT_SPECS.find(x => x.key === w.key)!;
    const v = s.needs[spec.need];
    if (spec.key === 'bath' && v < SMELLY_BELOW) return 'smelly';
    if (spec.moodKey !== null && v < spec.mood) return spec.moodKey;
  }
  if (lv === 2) return 'sulky';
  return 'ok';
}

/** Время суток для реплик: утро — 3 ч после подъёма питомца, вечер — 3 ч до отбоя, ночь — питомец спит. */
export function daypart(t: number, r: Rules, o: Owner): Daypart {
  if (petNight(t, r, o)) return 'night';
  const m = localMin(t, o);
  const up = o.wakeMin + r.night.afterWakeMin;
  if (inWindow(m, up, up + PART_MIN)) return 'morning';
  if (inWindow(m, o.bedMin - PART_MIN, o.bedMin + r.night.afterBedMin)) return 'evening';
  return 'day';
}

// ---------- «Спасти» ----------

export interface Rescue { key: WantKey | 'heal'; action: Action; because: Distress | Need | 'hearts' }
export interface RescueOpts { now?: number; food?: string; heal?: string }

const NEED_ACTIONS: Partial<Record<Need, Action[]>> = {
  food: [{ type: 'feed', item: '' }], clean: [{ type: 'bath' }], fun: [{ type: 'play' }], love: [{ type: 'pet' }],
};
const DISTRESS_ACTIONS: Record<Distress, Action[]> = {
  starve: [{ type: 'feed', item: '' }], dirty: [{ type: 'bath' }], toska: [{ type: 'play' }, { type: 'pet' }],
};

function actionKey(a: Action): WantKey | 'heal' {
  switch (a.type) {
    case 'feed': return 'food';
    case 'bath': return 'bath';
    case 'play': return 'play';
    case 'pet': return 'pet';
    default: return 'heal';
  }
}

/**
 * Одно самое срочное действие, которое ядро примет прямо сейчас (проверяется act на копии):
 * беда по скорости урона → шкалы ниже порога регенерации (или ниже warnLow при полных сердцах) в порядке wants →
 * в критичном состоянии лечебный предмет. null — делать нечего или ничего не поможет сейчас (ванна, ночь).
 * food/heal — какой корм и предмет предлагать (что есть в инвентаре — решает приложение).
 */
export function rescue(s0: PetState, r: Rules, o: Owner, opts: RescueOpts = {}): Rescue | null {
  const s = at(s0, r, o, opts.now);
  if (!s.alive) return null;
  const food = opts.food ?? 'kibble', heal = opts.heal ?? 'vitamin';
  const fill = (a: Action): Action => (a.type === 'feed' ? { type: 'feed', item: food } : a);
  const tryAct = (a: Action) => { const c = clone(s); return act(c, r, o, a).ok ? c : null; };

  const dist = DISTRESS.filter(d => r.distress[d].cond(s.needs))
    .map((d, i) => ({ d, i, h: r.distress[d].hoursPerHeart }))
    .sort((a, b) => (a.h !== b.h ? a.h - b.h : a.i - b.i));
  for (const { d } of dist) {
    let first: Action | null = null;
    for (const a0 of DISTRESS_ACTIONS[d]) {
      const a = fill(a0);
      const c = tryAct(a);
      if (!c) continue;
      if (first === null) first = a;
      if (a.type === 'bath' || !r.distress[d].cond(c.needs)) return { key: actionKey(a), action: a, because: d };
    }
    if (first !== null) return { key: actionKey(first), action: first, because: d };
  }

  const maxH = maxHearts(s, r);
  const bar = s.hearts < maxH ? r.hearts.regenAllGe : r.warnLow;
  for (const w of wants(s, r, o)) {
    const n = WANT_SPECS.find(x => x.key === w.key)!.need;
    if (!WATCH.includes(n) || s.needs[n] >= bar) continue;
    for (const a0 of NEED_ACTIONS[n] ?? []) {
      const a = fill(a0);
      if (tryAct(a)) return { key: actionKey(a), action: a, because: n };
    }
  }

  if (level(s, r) === 3 && s.hearts < maxH) {
    const a: Action = { type: 'item', item: heal };
    if (tryAct(a)) return { key: 'heal', action: a, because: 'hearts' };
  }
  return null;
}

// ---------- «Пока тебя не было» ----------

export interface TimedAct { t: number; action: Action }
export type AwayCta = 'cta_hungry' | 'cta_dirty' | 'cta_bored' | 'cta_love' | 'cta_tired' | 'cta_ok';
const WANT_CTA: Record<WantKey, AwayCta> = { food: 'cta_hungry', bath: 'cta_dirty', play: 'cta_bored', pet: 'cta_love', sleep: 'cta_tired', walk: 'cta_ok' };
export type AwayKind = Exclude<ForecastEvent['kind'], 'level'> | 'sleep' | 'wake' | 'nap' | 'heart_up' | 'act';
export interface AwayEvent { t: number; kind: AwayKind; key?: string; value?: number; ok?: boolean }
export interface AwaySummary {
  from: number;
  to: number;
  awayH: number;
  show: boolean;                  // показывать экран (≥ 2 ч)
  greet: 'welcome' | 'welcome_long' | null; // away.welcome / away.welcome_long (≥ 24 ч); null — не показывать или умер
  cta: AwayCta | null;            // away.cta_*: подсказка по главному желанию на now
  sleptH: number;                 // сколько питомец спал (ночь + дрёма)
  heartsFrom: number;
  heartsTo: number;
  needs: Record<Need, number>;    // изменение шкал: было → стало
  events: AwayEvent[];            // по времени; level не включаем — это шум
  died: boolean;
  state: PetState;                // состояние на now: дальше wants / mood / rescue
}

/**
 * Пересчитать отсутствие от prev до now. journal — действия, сделанные без приложения
 * (кнопки виджета и острова, шаги): применяются в своё время, как в векторах (act в момент s.t после stepTo).
 */
export function awaySummary(prev: PetState, r: Rules, o: Owner, now: number, journal: TimedAct[] = []): AwaySummary {
  const s = clone(prev);
  const ev: AwayEvent[] = [];
  let tr = tracker(s, r);
  let wasNight = petNight(s.t, r, o);
  let sleptMin = 0;
  const hc = () => Math.ceil(s.hearts - 1e-9);
  const run = (T: number) => {
    while (s.alive && s.t + STEP <= T) {
      const t0 = s.t, h0 = hc(), nap0 = s.napUntil;
      step(s, r, o);
      const night = petNight(t0, r, o);
      if (night !== wasNight) { ev.push({ t: t0, kind: night ? 'sleep' : 'wake' }); wasNight = night; }
      if (!night && s.napUntil !== null && s.napUntil !== nap0) ev.push({ t: s.t, kind: 'nap' });
      if (night || s.napUntil !== null) sleptMin++;
      if (hc() > h0) ev.push({ t: s.t, kind: 'heart_up', value: hc() });
      observe(tr, s, r, ev as unknown as ForecastEvent[]);
      if (!s.alive) ev.push({ t: s.diedAt ?? s.t, kind: 'death', key: s.cause ?? undefined });
    }
  };
  const acts = journal.map((a, i) => ({ a, i })).filter(x => x.a.t >= prev.t && x.a.t <= now)
    .sort((x, y) => (x.a.t !== y.a.t ? x.a.t - y.a.t : x.i - y.i));
  for (const { a } of acts) {
    run(a.t);
    if (!s.alive) break;
    const h0 = hc();
    const res = act(s, r, o, a.action);
    ev.push({ t: s.t, kind: 'act', key: a.action.type, ok: res.ok });
    if (hc() > h0) ev.push({ t: s.t, kind: 'heart_up', value: hc() });
    tr = tracker(s, r);
  }
  run(now);
  const needs = {} as Record<Need, number>;
  for (const n of NEEDS) needs[n] = s.needs[n] - prev.needs[n];
  const awayH = (now - prev.t) / 3600;
  const died = prev.alive && !s.alive;
  const show = awayH >= AWAY_SHOW_H;
  const live = show && s.alive;
  const top = live ? wants(s, r, o)[0] : undefined;
  return {
    from: prev.t, to: now, awayH, show, greet: live ? (awayH >= AWAY_LONG_H ? 'welcome_long' : 'welcome') : null,
    cta: live ? (top ? WANT_CTA[top.key] : 'cta_ok') : null,
    sleptH: sleptMin / 60, heartsFrom: prev.hearts, heartsTo: s.hearts, needs,
    events: ev.filter(e => (e.kind as string) !== 'level'), died, state: s,
  };
}

// ---------- план уведомлений ----------

export interface NotifyOpts {
  horizonH?: number;        // на сколько часов вперёд (по умолчанию 72; для полного «скучаю» — 14 × 24)
  lastOpenT?: number;       // когда открывали приложение в последний раз (по умолчанию now)
  lastSentT?: number | null; // когда ушло последнее уведомление: в этот местный день больше не зовём
  quietFromMin?: number;    // тихие часы, местные минуты от полуночи (по умолчанию сон хозяина)
  quietToMin?: number;
}
export interface PlannedNotification { at: number; trigger: Trigger; kind: 'low' | 'distress' | 'heart' | 'level' | 'last_chance' | 'absent'; key?: string }

const localDay = (t: number, o: Owner) => Math.floor((Math.floor(t / 60) + o.tzOffsetMin) / 1440);

/**
 * Локальные уведомления по прогнозу без ухода (RESEARCH/07 #6):
 * не больше 1 в местный день (самое серьёзное, при равенстве — раньшее), тихие часы переносят на их конец;
 * первые 3 дня после открытия — по событиям прогноза, с 3-го по 14-й — только «скучаю» раз в 3 дня, дальше тишина.
 * После смерти по прогнозу не зовём.
 */
export function notificationPlan(s0: PetState, r: Rules, o: Owner, now: number, opts: NotifyOpts = {}): PlannedNotification[] {
  const s = at(s0, r, o, now);
  if (!s.alive) return [];
  const horizonH = opts.horizonH ?? 72;
  const lastOpen = opts.lastOpenT ?? now;
  const qFrom = opts.quietFromMin ?? o.bedMin, qTo = opts.quietToMin ?? o.wakeMin;
  const end = now + horizonH * 3600;
  const careUntil = lastOpen + N_CARE_DAYS * 86400, stopAt = lastOpen + N_STOP_DAYS * 86400;
  const quiet = (t: number) => {
    const m = localMin(t, o);
    return inWindow(m, qFrom, qTo) ? t + ((((qTo - m) % 1440) + 1440) % 1440) * 60 : t;
  };
  const ev = forecast(s, r, o, horizonH);
  const death = ev.find(e => e.kind === 'death');
  const deathT = death ? death.t : Infinity;
  const cands: (PlannedNotification & { sev: number })[] = [];
  for (const e of ev) {
    let trigger: Trigger | undefined, sev = 0;
    if (e.kind === 'low') { trigger = NEED_TRIGGER[e.key as Need]; sev = 1; }
    else if (e.kind === 'distress') { trigger = DISTRESS_TRIGGER[e.key as Distress]; sev = 2; }
    else if (e.kind === 'heart') { trigger = 'heart_lost'; sev = 2; }
    else if (e.kind === 'level' && e.value === 3) { trigger = 'critical'; sev = 3; }
    else if (e.kind === 'last_chance') { trigger = 'last_chance'; sev = 4; }
    if (trigger === undefined) continue;
    const t = quiet(e.t);
    if (t >= careUntil) continue;
    const c: PlannedNotification & { sev: number } = { at: t, trigger, kind: e.kind as PlannedNotification['kind'], sev };
    if (e.key !== undefined) c.key = e.key;
    cands.push(c);
  }
  for (let k = 1; lastOpen + k * N_MISS_EVERY_DAYS * 86400 < stopAt; k++) {
    const t = quiet(lastOpen + k * N_MISS_EVERY_DAYS * 86400);
    if (t < stopAt) cands.push({ at: t, trigger: 'miss_you', kind: 'absent', sev: 0 });
  }
  const sentDay = opts.lastSentT !== undefined && opts.lastSentT !== null ? localDay(opts.lastSentT, o) : null;
  const ok = cands.filter(c => c.at >= now + N_LEAD_MIN * 60 && c.at <= end && c.at < deathT && localDay(c.at, o) !== sentDay)
    .map((c, i) => ({ c, i }))
    .sort((a, b) => (a.c.at !== b.c.at ? a.c.at - b.c.at : a.i - b.i));
  const byDay = new Map<number, PlannedNotification & { sev: number }>();
  for (const { c } of ok) {
    const d = localDay(c.at, o);
    const cur = byDay.get(d);
    if (cur === undefined || c.sev > cur.sev) byDay.set(d, c);
  }
  return [...byDay.values()].sort((a, b) => a.at - b.at).map(({ sev, ...p }) => p);
}
