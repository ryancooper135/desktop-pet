// Сценарии баланса и инструменты: шаги до захода, заход «до максимума», детерминизм, warn_low из конфига.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { makeRules } from '../src/rules.ts';
import { act, defaultOwner, level } from '../src/engine.ts';
import type { Action } from '../src/engine.ts';
import { SCENARIOS, T0, runDays, runScenario, scenario, startAt } from '../src/scenarios.ts';
import type { ActFn } from '../src/scenarios.ts';

const cfgUrl = new URL('../../../config/economy.json', import.meta.url);
const cfg = () => JSON.parse(readFileSync(cfgUrl, 'utf8'));
const r = makeRules(cfg());
const o = defaultOwner(r);
const H = 3600;

/** Шпион: настоящее act плюс запись вызовов (время, действие, движение до действия). */
function spy() {
  const calls: { t: number; a: Action; walk: number; ok: boolean }[] = [];
  const fn: ActFn = (s, rr, oo, a) => {
    const walk = s.needs.walk;
    const res = act(s, rr, oo, a);
    calls.push({ t: s.t, a, walk, ok: res.ok });
    return res;
  };
  return { fn, calls };
}

test('runDays: шаги дня начисляются в начале захода того же дня, до его действий', () => {
  const sp = spy();
  runDays(r, o, startAt(r, 7.5), 3, [8, 13, 18, 22.5], { steps: 6000, act: sp.fn });
  for (let d = 0; d < 3; d++) {
    const t18 = T0 + d * 86400 + 18 * H;
    const atVisit = sp.calls.filter(c => c.t >= t18 && c.t < t18 + H);
    assert.equal(atVisit[0].a.type, 'steps', `день ${d}: первое действие захода в 18:00 — шаги`);
    assert.equal(atVisit[0].t, t18);
    // следующее действие того же захода уже видит шаги
    assert.ok(atVisit[1].walk >= Math.min(100, atVisit[0].walk + 6000 / r.needs.walk.steps_per_point) - 1e-9);
  }
  assert.equal(sp.calls.filter(c => c.a.type === 'steps').length, 3);
});

test('runDays: без захода после 18:00 шаги приходят с последним заходом дня', () => {
  const sp = spy();
  runDays(r, o, startAt(r, 7.5), 2, [9, 13], { steps: 4000, act: sp.fn });
  const st = sp.calls.filter(c => c.a.type === 'steps');
  assert.deepEqual(st.map(c => c.t), [T0 + 13 * H, T0 + 86400 + 13 * H]);
});

test('сценарий «1 до максимума» действительно идёт с full: true', () => {
  const sc = scenario('full1_noon');
  assert.equal(sc.opts.full, true);
  const sp = spy();
  runScenario(r, o, sc, 2, sp.fn);
  // заход второго дня (36 ч от T0): ласка просела, обычный гладит ровно 3 раза, «до максимума» — пока ласка не 95
  const day1 = (c: { t: number; a: Action; ok: boolean }) => c.ok && c.t >= T0 + 36 * H && c.t < T0 + 39 * H;
  const count = (xs: typeof sp.calls, type: string) => xs.filter(c => day1(c) && c.a.type === type).length;
  assert.ok(count(sp.calls, 'pet') > 3, 'гладит больше трёх раз');
  assert.ok(count(sp.calls, 'play') > 1, 'играет больше одного раза');
  const normal = spy();
  runScenario(r, o, scenario('visits1'), 2, normal.fn);
  assert.equal(count(normal.calls, 'pet'), 3);
  assert.equal(count(normal.calls, 'play'), 1);
  // все сценарии, подписанные «до максимума», с full
  for (const s of SCENARIOS) if (s.title.includes('до максимума')) assert.equal(s.opts.full, true, s.key);
});

test('careless2 и full1_noon детерминированы', () => {
  for (const key of ['careless2', 'full1_noon']) {
    const a = runScenario(r, o, scenario(key), 30);
    const b = runScenario(r, o, scenario(key), 30);
    assert.deepEqual(
      { d: a.diedDay, c: a.causes, m: a.minHearts, n: a.avgNeeds, s: a.state },
      { d: b.diedDay, c: b.causes, m: b.minHearts, n: b.avgNeeds, s: b.state }, key);
    for (const x of Object.values(a.avgNeeds)) assert.ok(Number.isFinite(x));
  }
});

test('careless2: смерть совпадает с вектором core/vectors/careless2.json', () => {
  const v = JSON.parse(readFileSync(new URL('../../vectors/careless2.json', import.meta.url), 'utf8'));
  const res = runScenario(r, o, scenario('careless2'), 30);
  const last = v.steps.at(-1).expect;
  assert.equal(last.alive, false);
  assert.equal(res.state.diedAt, last.diedAt);
});

test('warn_low из конфига: нет поля → 30, 40 → 40', () => {
  const c = cfg();
  assert.equal(r.warnLow, c.levels.warn_low);
  delete c.levels.warn_low;
  const r30 = makeRules(c);
  assert.equal(r30.warnLow, 30);
  c.levels.warn_low = 40;
  const r40 = makeRules(c);
  assert.equal(r40.warnLow, 40);
  const s = startAt(r, 12);
  s.needs.fun = 35;
  assert.equal(level(s, r30), 0);
  assert.equal(level(s, r40), 1);
});
