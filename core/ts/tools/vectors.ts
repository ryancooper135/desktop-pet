// Генератор общих тест-векторов: node core/ts/tools/vectors.ts
// TS прогоняет сценарии и записывает контрольные состояния; Swift (core/swift) обязан их повторить.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { makeRules } from '../src/rules.ts';
import { act, clone, defaultOwner, forecast, level, moods, stepTo } from '../src/engine.ts';
import type { Action, Owner, PetState } from '../src/engine.ts';
import { awaySummary, daypart, mood, notificationPlan, rescue, wants } from '../src/insights.ts';
import type { NotifyOpts } from '../src/insights.ts';
import { T0, runDays, scenario, startAt } from '../src/scenarios.ts';
import type { TimedAction } from '../src/scenarios.ts';

const cfgUrl = new URL('../../../config/economy.json', import.meta.url);
const cfg = JSON.parse(readFileSync(cfgUrl, 'utf8'));
let r = makeRules(cfg);
const preset0 = r.preset;
const outDir = new URL('../../vectors/', import.meta.url);
mkdirSync(outDir, { recursive: true });
const H = 3600;

type Step = { t: number; do: Action; ok: boolean; reason?: string } | { t: number; expect: PetState; level: number; moods: string[]; [k: string]: unknown };

/** Случаи плана уведомлений: свежий заход, 2,5 дня без открытий (порог «скучаю»), конец сценария. */
function notifyCases(o: Owner, start: PetState, end: PetState) {
  const cases: { from: PetState; now: number; opts: NotifyOpts }[] = [
    { from: start, now: start.t, opts: { horizonH: 14 * 24 } },
    { from: start, now: start.t, opts: { horizonH: 14 * 24, lastOpenT: start.t - 2.5 * 86400, lastSentT: start.t - H } },
    { from: end, now: end.t + 30, opts: { horizonH: 72, quietFromMin: 22 * 60, quietToMin: 9 * 60 } },
  ];
  return cases.map(c => ({ ...c, from: clone(c.from), plan: notificationPlan(c.from, r, o, c.now, c.opts) }));
}

/** Переиграть действия с нуля, вставляя контрольные точки каждые checkH часов. */
function record(name: string, o: Owner, start: PetState, actions: TimedAction[], endT: number, checkH = 6, extra: (s: PetState) => void = () => {}) {
  const s = clone(start);
  const steps: Step[] = [];
  const check = (t: number) => {
    stepTo(s, r, o, t);
    steps.push({
      t, expect: clone(s), level: level(s, r), moods: moods(s, r, o),
      mood: mood(s, r, o), daypart: daypart(s.t, r, o), wants: wants(s, r, o), rescue: rescue(s, r, o),
    });
  };
  let nextCheck = start.t + checkH * H;
  for (const a of actions) {
    while (nextCheck <= a.t) { check(nextCheck); nextCheck += checkH * H; }
    stepTo(s, r, o, a.t);
    const res = act(s, r, o, a.action);
    steps.push({ t: a.t, do: a.action, ok: res.ok, ...(res.reason ? { reason: res.reason } : {}) });
  }
  while (nextCheck <= endT) { check(nextCheck); nextCheck += checkH * H; }
  check(endT);
  extra(s);
  const fc = forecast(s, r, o, 72);
  const away = { now: endT, journal: actions, ...awaySummary(start, r, o, endT, actions) };
  const notify = notifyCases(o, start, s);
  writeFileSync(new URL(`${name}.json`, outDir), JSON.stringify({ name, ...(r.preset !== preset0 ? { preset: r.preset } : {}), owner: o, start, steps, forecast: { from: clone(s), horizonH: 72, events: fc }, away, notify }, null, 1) + '\n');
  console.log(name, steps.length, 'шагов,', fc.length, 'событий прогноза');
}

const o = defaultOwner(r);
const oKiev = defaultOwner(r, 180);

// 1. полный игнор до смерти
{ const s = startAt(r, 7.5); record('ignore_0730', o, s, [], s.t + 62 * H); }
// 2. будка L4 + UTC+3 + нестандартный график
{ const s = startAt(r, 14); s.home.kennel = 3; s.home.bed = 2; const ow = { ...oKiev, bedMin: 60, wakeMin: 9 * 60 }; record('kennel4_tz180', ow, s, [], s.t + 90 * H); }
// 3. 4 захода + шаги, 4 дня (шаги начисляются в начале захода в 18:00)
{ const sc = scenario('visits4_steps'); const s = startAt(r, 7.5); const res = runDays(r, o, clone(s), 4, sc.visits, sc.opts); record('visits4_steps', o, s, res.log, T0 + 4 * 86400); }
// 4. один небрежный заход до смерти
{ const s = startAt(r, 7.5); const res = runDays(r, o, clone(s), 5, [12], { careless: true }); record('careless1', o, s, res.log, res.state.diedAt ?? T0 + 5 * 86400, 12); }
// 5. один заход «до максимума», улучшенный дом
{ const s = startAt(r, 7.5); s.home.bath = 2; s.home.play = 1; s.home.kitchen = 1; s.home.yard = 3; const res = runDays(r, o, clone(s), 3, [19], { full: true }); record('full1_home', o, s, res.log, T0 + 3 * 86400); }
// 6. ручные действия, включая отказы
{
  const s = startAt(r, 10.25);
  s.needs.clean = 20; s.needs.energy = 16; s.hearts = 3.2;
  const t = s.t + 17; // не на границе минуты
  const A = (dt: number, action: Action): TimedAction => ({ t: t + dt, action });
  record('actions_misc', o, s, [
    A(0, { type: 'pet' }), A(30, { type: 'pet' }), A(200, { type: 'pet' }),
    A(240, { type: 'bath' }), A(300, { type: 'feed', item: 'stew' }), A(320, { type: 'play' }),
    A(1.5 * H, { type: 'feed', item: 'gold_bone' }), A(1.5 * H + 60, { type: 'feed', item: 'gold_bone' }), A(1.5 * H + 90, { type: 'feed', item: 'nope' }),
    A(1.5 * H + 120, { type: 'item', item: 'vitamin' }), A(1.5 * H + 150, { type: 'item', item: 'vitamin' }), A(2 * H, { type: 'play' }), A(2 * H + 60, { type: 'play' }), A(2 * H + 120, { type: 'play' }),
    A(3 * H, { type: 'wake' }), A(5 * H, { type: 'steps', count: 2345 }), A(6 * H, { type: 'feed', item: 'milk' }), A(9 * H, { type: 'feed', item: 'cake' }),
  ], t + 30 * H, 2);
}
// 7. два захода «только покормить» до смерти
{ const sc = scenario('careless2'); const s = startAt(r, 7.5); const res = runDays(r, o, clone(s), 6, sc.visits, sc.opts); record('careless2', o, s, res.log, res.state.diedAt ?? T0 + 6 * 86400, 12); }
// 8. один заход «до максимума» в 12:00, дом стартовый
{ const sc = scenario('full1_noon'); const s = startAt(r, 7.5); const res = runDays(r, o, clone(s), 4, sc.visits, sc.opts); record('full1_noon', o, s, res.log, T0 + 4 * 86400, 12); }
// 9. прогулка с находкой: отказы (мало шкал, ванна, away), шаги на прогулке, три прогулки (последняя обрезана ночью)
{
  const s = startAt(r, 9.5); s.needs.clean = 25;
  const t = s.t + 17;
  const A = (dt: number, action: Action): TimedAction => ({ t: t + dt, action });
  const W: Action = { type: 'walk' };
  record('walk_find', o, s, [
    A(0, W), A(60, { type: 'bath' }), A(120, W), A(H + 120, W), A(H + 180, { type: 'feed', item: 'stew' }),
    A(H + 240, { type: 'steps', count: 800 }), A(H + 300, { type: 'pet' }),
    A(5 * H, { type: 'feed', item: 'stew' }), A(5 * H + 60, { type: 'pet' }), A(5 * H + 120, W),
    A(12.85 * H, { type: 'feed', item: 'cake' }), A(12.85 * H + 60, W), A(12.85 * H + 120, { type: 'feed', item: 'cake' }),
  ], t + 13.5 * H, 1); // конец на третьей прогулке: в прогнозе возвращение к ночи (back_home)
}
// 10. поздно для прогулки: до ночи питомца меньше часа
{ const s = startAt(r, 22 + 50 / 60); record('walk_late', o, s, [{ t: s.t, action: { type: 'walk' } }, { t: s.t + 60, action: { type: 'pet' } }], s.t + 10 * H, 2); }

// 13. кухня L3: покормил и ушёл на 3 суток — автокормушка ест из запаса (60 = 3 порции), потом голод
{ const s = startAt(r, 7.5); s.home.kitchen = 3; record('kitchen3_autofeed', o, s, [
  { t: s.t, action: { type: 'feed', item: 'stew' } }, { t: s.t + 60, action: { type: 'pet' } },
], s.t + 3 * 86400, 6); }
// кухня L2 и обед в ванне: порция ждёт конца мытья
{ const s = startAt(r, 7.5); s.home.kitchen = 2; s.needs.food = 30; record('kitchen2_bath', o, s, [
  { t: s.t, action: { type: 'feed', item: 'stew' } }, { t: s.t + 10 * H, action: { type: 'bath' } },
], s.t + 30 * H, 2); }

// 14. расчесать: грязный (love_gain_x 0.7) и почти полная ласка (потолок считается от «Погладить»), откат 6 ч,
// «Погладить» и «Расчесать» не мешают друг другу, отказы: дрёма, ванна, ночь; потом беда (сердечки ≤ 2) и витаминка
{
  const s = startAt(r, 9.25); s.needs.clean = 20; s.needs.love = 97; s.needs.energy = 16;
  const t = s.t + 17;
  const A = (dt: number, action: Action): TimedAction => ({ t: t + dt, action });
  const B: Action = { type: 'brush' };
  record('brush_misc', o, s, [
    A(0, B), A(60, B), A(120, { type: 'pet' }), A(180, B),
    A(30 * 60, B), A(30 * 60 + 60, { type: 'wake' }), A(40 * 60, { type: 'bath' }), A(45 * 60, B),
    A(6 * H - 60, B), A(6 * H + 60, B), A(6 * H + 120, { type: 'pet' }),
    A(15 * H, B),
  ], t + 16 * H, 2);
}
{
  const s = startAt(r, 11); s.hearts = 2; s.needs.love = 30;
  const t = s.t + 17;
  const A = (dt: number, action: Action): TimedAction => ({ t: t + dt, action });
  record('brush_unwell', o, s, [
    A(0, { type: 'brush' }), A(60, { type: 'item', item: 'vitamin' }), A(120, { type: 'brush' }), A(180, { type: 'item', item: 'brush' }),
  ], t + 4 * H, 1);
}

// 11–12. пресеты строгости: Swift строит правила по полю preset
r = makeRules(cfg, 'medium');
{ const sc = scenario('careless2'); const s = startAt(r, 7.5); const res = runDays(r, o, clone(s), 10, sc.visits, sc.opts); record('careless2_medium', o, s, res.log, res.state.diedAt ?? T0 + 10 * 86400, 12); }
r = makeRules(cfg, 'soft');
{ const s = startAt(r, 7.5); const res = runDays(r, o, clone(s), 12, [12], { careless: true }); record('careless1_soft', o, s, res.log, res.state.diedAt ?? T0 + 12 * 86400, 12); }
