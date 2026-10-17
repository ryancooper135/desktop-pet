// Прогулка с находкой (care.walk_out): отказы, длительность от сида, шкалы вне дома, возвращение, прогноз.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { makeRules } from '../src/rules.ts';
import { act, advance, clone, defaultOwner, forecast, moods, stepTo, walksDone } from '../src/engine.ts';
import type { Action, PetState } from '../src/engine.ts';
import { awaySummary, mood, rescue, wants } from '../src/insights.ts';
import { T0, startAt } from '../src/scenarios.ts';

const cfg = JSON.parse(readFileSync(new URL('../../../config/economy.json', import.meta.url), 'utf8'));
const r = makeRules(cfg);
const o = defaultOwner(r);
const H = 3600;
const W: Action = { type: 'walk' };
const FINDS = cfg.care.walk_out.finds.map((f: any) => f.id);

const walking = (hour = 10, fill = 80) => { const s = startAt(r, hour, fill); assert.equal(act(s, r, o, W).ok, true); return s; };

test('отказы: смерть, ванна, дрёма, ночь, беда, мало шкал, нет блока в конфиге', () => {
  const why = (s: PetState, rr = r) => { const c = clone(s); const res = act(c, rr, o, W); if (!res.ok) assert.deepEqual(c, s, 'отказ не меняет состояние'); return res.reason; };
  const dead = startAt(r, 10); dead.alive = false;
  assert.equal(why(dead), 'dead');
  const bath = startAt(r, 10); act(bath, r, o, { type: 'bath' });
  assert.equal(why(bath), 'bathing');
  const nap = startAt(r, 10); nap.napUntil = nap.t + 1800;
  assert.equal(why(nap), 'asleep');
  assert.equal(why(startAt(r, 2)), 'asleep');
  const crit = startAt(r, 10); crit.hearts = 2;
  assert.equal(why(crit), 'unwell');
  const starving = startAt(r, 10); starving.needs.food = 0;
  assert.equal(why(starving), 'unwell');
  for (const n of ['food', 'clean', 'energy'] as const) {
    const s = startAt(r, 10); s.needs[n] = 25;
    assert.equal(why(s), 'not_ready', n);
  }
  // fun и love не мешают: на прогулке они не падают
  const sad = startAt(r, 10); sad.needs.fun = 20; sad.needs.love = 20;
  assert.equal(why(sad), undefined);
  const noBlock = makeRules({ ...cfg, care: { ...cfg.care, walk_out: undefined } });
  assert.equal(noBlock.walkOut, null);
  assert.equal(why(startAt(r, 10), noBlock), 'unavailable');
  assert.equal(why(walking()), 'away');
});

test('длительность 1–3 ч и находка детерминированы, разные старты дают разное', () => {
  const durs = new Set<number>(), finds = new Set<string>();
  for (let m = 0; m < 240; m++) {
    const s = startAt(r, 9); s.t += m * 60;
    const a = clone(s), b = clone(s);
    assert.equal(act(a, r, o, W).ok, true);
    act(b, r, o, W);
    assert.deepEqual(a.outing, b.outing);
    const d = (a.outing!.until - a.outing!.from) / 60;
    assert.ok(d >= 60 && d <= 180 && Number.isInteger(d), `${d}`);
    assert.ok(FINDS.includes(a.outing!.find));
    durs.add(d); finds.add(a.outing!.find);
  }
  assert.ok(durs.size > 30, `мало разных длительностей: ${durs.size}`);
  assert.equal(finds.size, FINDS.length, 'выпадает каждая находка');
  // тот же старт после прошлой прогулки — другой сид
  const s = startAt(r, 9), s2 = clone(s);
  s2.finds = { stick: 1 };
  act(s, r, o, W); act(s2, r, o, W);
  assert.notDeepEqual(s.outing, s2.outing);
});

test('пока гуляет: другие действия — away, шаги принимаются, шкалы по своим множителям', () => {
  const s = walking();
  const t0 = s.t, n0 = { ...s.needs };
  for (const a of [{ type: 'feed', item: 'stew' }, { type: 'item', item: 'vitamin' }, { type: 'pet' }, { type: 'play' }, { type: 'bath' }, { type: 'wake' }, W] as Action[]) {
    const c = clone(s);
    assert.deepEqual(act(c, r, o, a), { ok: false, reason: 'away' }, a.type);
    assert.deepEqual(c, s);
  }
  assert.equal(act(clone(s), r, o, { type: 'steps', count: 800 }).ok, true);
  assert.deepEqual(moods(s, r, o)[0], 'walking');
  assert.equal(mood(s, r, o), 'walking');
  assert.deepEqual(wants(s, r, o), []);
  assert.equal(rescue(s, r, o), null);
  stepTo(s, r, o, t0 + 50 * 60); // короче любой прогулки
  assert.notEqual(s.outing, null);
  const dh = 50 / 60;
  assert.equal(s.needs.fun, n0.fun);
  assert.equal(s.needs.love, n0.love);
  assert.equal(s.needs.walk, n0.walk);
  assert.ok(Math.abs((n0.food - s.needs.food) - 5 * 1.5 * dh) < 1e-6, `food ${n0.food - s.needs.food}`);
  assert.ok(Math.abs((n0.clean - s.needs.clean) - 2.5 * 2 * dh) < 1e-6, `clean ${n0.clean - s.needs.clean}`);
  assert.ok(Math.abs((n0.energy - s.needs.energy) - 3.5 * 1.5 * dh) < 1e-6, `energy ${n0.energy - s.needs.energy}`);
});

test('возвращение в until: находка в альбом, прибавка, событие прогноза и «Пока тебя не было»', () => {
  const s0 = walking(10, 50);
  const { until, find } = s0.outing!;
  const fc = forecast(s0, r, o, 6);
  const back = fc.filter(e => e.kind === 'back_home');
  assert.deepEqual(back, [{ t: until, kind: 'back_home', key: find }]);
  const before = advance(s0, r, o, until);
  assert.notEqual(before.outing, null);
  const after = advance(s0, r, o, until + 60);
  assert.equal(after.outing, null);
  assert.deepEqual(after.finds, { [find]: 1 });
  assert.equal(walksDone(after), 1);
  assert.ok(after.needs.walk > before.needs.walk + 39);
  const away = awaySummary(s0, r, o, until + 3 * H);
  assert.deepEqual(away.events.filter(e => e.kind === 'back_home'), back);
  // дома снова принимает действия
  assert.equal(act(after, r, o, { type: 'pet' }).ok, true);
});

test('журнал: прогулка с виджета попадает в «Пока тебя не было»', () => {
  const s = startAt(r, 10);
  const a = awaySummary(s, r, o, s.t + 5 * H, [{ t: s.t + H, action: W }]);
  const ks = a.events.map(e => e.kind);
  assert.ok(ks.includes('act') && ks.includes('back_home'), ks.join());
  assert.equal(a.events.find(e => e.kind === 'act')!.key, 'walk');
  assert.equal(a.state.outing, null);
  assert.equal(walksDone(a.state), 1);
});

test('на прогулке урона нет; беда возвращает домой раньше срока', () => {
  const s = walking(10);
  s.hearts = 3; s.needs.food = 1;
  const back = forecast(s, r, o, 6).find(e => e.kind === 'back_home')!;
  assert.ok(back.t < s.outing!.until, 'вернулся раньше: голод');
  const atDoor = advance(s, r, o, back.t);
  assert.notEqual(atDoor.outing, null);
  assert.equal(atDoor.needs.food, 0);
  assert.equal(atDoor.hearts, 3);
  assert.equal(atDoor.grace.starve, 0, 'льготы не копятся');
  assert.equal(advance(s, r, o, back.t + 60).outing, null);
});

test('ночь обрезает прогулку, поздно — too_late', () => {
  // ночь питомца с 23:45
  const late = startAt(r, 22 + 50 / 60);
  assert.deepEqual(act(clone(late), r, o, W), { ok: false, reason: 'too_late' });
  for (let m = 0; m < 30; m++) {
    const s = startAt(r, 22); s.t += m * 60;
    if (!act(s, r, o, W).ok) { assert.ok(105 - m < 60); continue; }
    assert.ok(s.outing!.until <= T0 + 23.75 * H, 'вернётся к ночи');
    const back = advance(s, r, o, T0 + 24 * H);
    assert.equal(back.outing, null);
    assert.equal(walksDone(back), 1);
  }
});

test('старое сохранение без outing/finds: дома, прогулка работает', () => {
  const s = startAt(r, 10) as any;
  delete s.outing; delete s.finds;
  assert.deepEqual(moods(s, r, o).includes('walking'), false);
  stepTo(s, r, o, s.t + H);
  assert.equal(walksDone(s), 0);
  assert.equal(act(s, r, o, W).ok, true);
  stepTo(s, r, o, s.t + 4 * H);
  assert.equal(walksDone(s), 1);
});
