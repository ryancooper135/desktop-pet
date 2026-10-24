// Пресеты строгости смерти (care.hearts.presets) и образы игроков. Цифры — RESEARCH/12-balance-options.md.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { makeRules, presetNames, withPreset } from '../src/rules.ts';
import type { Rules } from '../src/rules.ts';
import { defaultOwner } from '../src/engine.ts';
import { PATTERNS, SCENARIOS, START_HOUR, T0, ignoreUntilDeath, runDays, runScenario, startAt } from '../src/scenarios.ts';

const cfgUrl = new URL('../../../config/economy.json', import.meta.url);
const cfg = () => JSON.parse(readFileSync(cfgUrl, 'utf8'));
const H = 3600;
const pat = (k: string) => PATTERNS.find(p => p.key === k)!;
const sc = (k: string) => SCENARIOS.find(p => p.key === k)!;
const run = (r: Rules, k: string, days = 21) => runScenario(r, defaultOwner(r), pat(k), days);

/** Правила без поля preset — для сравнения значений. */
const values = (r: Rules) => { const { preset: _p, ...rest } = r; return JSON.stringify(rest, (_k, v) => typeof v === 'function' ? String(v) : v); };

test('пресеты: «Обычно» по умолчанию (волна 32), список из конфига', () => {
  const c = cfg();
  assert.equal(c.care.hearts.preset, 'normal');
  assert.deepEqual(presetNames(c), ['strict', 'normal', 'medium', 'soft']);
  assert.equal(makeRules(c).preset, 'normal');
  assert.equal(makeRules(c, 'soft').preset, 'soft');
  assert.equal(values(makeRules(c)), values(makeRules(c, 'normal')));
});

test('пресеты: «Обычно» строго между «Строго» и «Средне»', () => {
  const [s, n, m] = ['strict', 'normal', 'medium'].map(p => makeRules(cfg(), p));
  const between = (a: number, x: number, b: number) => a < x && x < b;
  assert.ok(between(m.hearts.regenAllGe, n.hearts.regenAllGe, s.hearts.regenAllGe));
  assert.ok(between(s.hearts.lastChanceH, n.hearts.lastChanceH, m.hearts.lastChanceH));
  for (const d of ['dirty', 'toska'] as const) {
    assert.ok(between(s.distress[d].graceH, n.distress[d].graceH, m.distress[d].graceH), d);
    assert.ok(between(s.distress[d].hoursPerHeart, n.distress[d].hoursPerHeart, m.distress[d].hoursPerHeart), d);
  }
  assert.equal(n.distress.starve.hoursPerHeart, s.distress.starve.hoursPerHeart);
  const ign = [s, n, m].map(r => ignoreUntilDeath(r, defaultOwner(r), startAt(r, START_HOUR))!);
  assert.ok(between(ign[0], ign[1], ign[2]), `игнор: ${ign}`);
  // без ванны умирает позже строгого и раньше среднего; после выходных сердца растут, но медленнее среднего
  const nb = ['strict', 'normal', 'medium'].map(p => run(makeRules(cfg(), p), 'nobath').diedDay!);
  assert.ok(between(nb[0], nb[1], nb[2]), `без ванны: ${nb}`);
  const wk = run(n, 'weekend');
  assert.equal(wk.diedDay, null);
  assert.ok(wk.heartsByDay[14] > wk.heartsByDay[7] + 0.3, `обычно: ${wk.heartsByDay[7]} → ${wk.heartsByDay[14]}`);
});

test('пресеты: strict — пустая заплатка, конфиг без пресетов даёт те же правила', () => {
  const c = cfg();
  c.care.hearts.preset = 'strict';
  const bare = cfg();
  delete bare.care.hearts.preset;
  delete bare.care.hearts.presets;
  assert.equal(makeRules(bare).preset, null);
  assert.equal(values(makeRules(bare)), values(makeRules(c)));
  assert.deepEqual(presetNames(bare), []);
  // и сам конфиг не меняется от наложения
  const before = JSON.stringify(c);
  withPreset(c, 'soft');
  assert.equal(JSON.stringify(c), before);
});

test('пресеты: неизвестное имя и служебные ключи — ошибка', () => {
  assert.throws(() => makeRules(cfg(), 'hardcore'), /нет пресета/);
  assert.throws(() => makeRules(cfg(), '_note'), /нет пресета/);
  assert.throws(() => makeRules(cfg(), 'toString'), /нет пресета/);
  const bad = cfg();
  bad.care.hearts.presets.broken = 'medium';
  assert.throws(() => makeRules(bad, 'broken'), /нет пресета/);
  const c = cfg();
  c.care.hearts.preset = 'nope';
  assert.throws(() => makeRules(c), /нет пресета/);
});

test('пресеты: значения заплаток накладываются', () => {
  const s = makeRules(cfg(), 'strict'), m = makeRules(cfg(), 'medium'), so = makeRules(cfg(), 'soft');
  assert.equal(m.distress.dirty.hoursPerHeart, 48);
  assert.equal(m.distress.dirty.graceH, 24);
  assert.equal(m.distress.toska.hoursPerHeart, 36);
  assert.equal(m.hearts.regenAllGe, 15);
  assert.equal(m.hearts.lastChanceH, 12);
  // то, чего нет в заплатке, — как в строгом
  assert.equal(m.distress.starve.hoursPerHeart, s.distress.starve.hoursPerHeart);
  assert.equal(m.hearts.regenPerH, s.hearts.regenPerH);
  assert.equal(so.hearts.regenPerH, 0.125);
  assert.equal(so.hearts.lastChanceH, 16);
  assert.equal(so.distress.starve.hoursPerHeart, 8);
  // в мягком грязь не беда ни при какой чистоте
  const n = { ...startAt(so, 8).needs, clean: 0 };
  assert.equal(so.distress.dirty.cond(n), false);
  assert.equal(s.distress.dirty.cond(n), true);
});

test('пресеты: строже — раньше смерть (игнор и «кормит и всё»)', () => {
  const [s, m, so] = ['strict', 'medium', 'soft'].map(p => makeRules(cfg(), p));
  const ign = [s, m, so].map(r => ignoreUntilDeath(r, defaultOwner(r), startAt(r, START_HOUR))!);
  assert.ok(ign[0] < ign[1] && ign[1] < ign[2], `игнор: ${ign}`);
  assert.ok(Math.abs(ign[0] - 59.3) < 0.1, `строгий игнор ${ign[0]}`);
  const dead = [s, m, so].map(r => runScenario(r, defaultOwner(r), sc('careless2'), 30).diedDay ?? Infinity);
  assert.ok(dead[0] < dead[1] && dead[1] < dead[2], `2 × еда: ${dead}`);
  // «Плохо» приходит одинаково: пресеты сдвигают смерть, а не предупреждение
  const bad = [s, m, so].map(r => run(r, 'feed2').firstBadH);
  assert.equal(bad[0], bad[1]);
  assert.equal(bad[1], bad[2]);
});

test('образы: нормальная забота живёт с полными сердцами в любом пресете', () => {
  for (const p of ['strict', 'medium', 'soft']) {
    const r = makeRules(cfg(), p);
    for (const k of ['carer', 'regular', 'busy2', 'owl']) {
      const res = run(r, k);
      assert.ok(res.state.alive, `${p}/${k} умер`);
      assert.equal(res.firstBadH, null, `${p}/${k}: «Плохо» в ${res.firstBadH} ч`);
      assert.equal(res.minHearts, r.hearts.max, `${p}/${k}`);
    }
  }
});

test('образы: строгий убивает за неделю без ванны, мягкий — нет', () => {
  const s = run(makeRules(cfg(), 'strict'), 'nobath');
  assert.ok(s.diedDay !== null && s.diedDay < 8, `строго: ${s.diedDay}`);
  assert.deepEqual(s.causes, ['dirty']);
  const m = run(makeRules(cfg(), 'medium'), 'nobath');
  assert.ok(m.diedDay !== null && m.diedDay > 14, `средне: ${m.diedDay}`);
  const so = run(makeRules(cfg(), 'soft'), 'nobath');
  assert.equal(so.diedDay, null);
  assert.equal(so.firstBadH, null);
});

test('образы: после выходных сердца возвращаются только в среднем и мягком', () => {
  const [s, m, so] = ['strict', 'medium', 'soft'].map(p => run(makeRules(cfg(), p), 'weekend'));
  for (const x of [s, m, so]) assert.equal(x.diedDay, null);
  assert.ok(s.heartsByDay[14] <= s.heartsByDay[7] + 1e-9, 'строго: не растут');
  assert.ok(m.heartsByDay[14] > m.heartsByDay[7] + 1, `средне: ${m.heartsByDay[7]} → ${m.heartsByDay[14]}`);
  assert.ok(so.heartsByDay[14] > so.heartsByDay[7], 'мягко: растут');
  // отпуск 5 суток без пансиона убивает в любом пресете
  for (const p of ['strict', 'medium', 'soft']) assert.notEqual(run(makeRules(cfg(), p), 'vacation').diedDay, null, p);
});

test('runDays: away пропускает заходы, noBath не купает, сердца по суткам', () => {
  const r = makeRules(cfg());
  const o = defaultOwner(r);
  const res = runDays(r, o, startAt(r, 7.5), 5, [8, 14, 21], { away: [[24 + 10, 3 * 24]] });
  const inAway = res.log.filter(l => l.t >= T0 + (24 + 10) * H && l.t < T0 + 3 * 24 * H);
  assert.equal(inAway.length, 0);
  assert.ok(res.log.some(l => l.t === T0 + (24 + 8) * H), 'заход до окна есть');
  assert.ok(res.log.some(l => l.t === T0 + (3 * 24 + 8) * H), 'заход после окна есть');
  assert.equal(res.heartsByDay.length, 5);
  assert.equal(res.heartsByDay[0], 5);
  const nb = runDays(r, o, startAt(r, 7.5), 4, [8, 14, 21], { noBath: true });
  assert.ok(!nb.log.some(l => l.action.type === 'bath'));
  const wb = runDays(r, o, startAt(r, 7.5), 4, [8, 14, 21]);
  assert.ok(wb.log.some(l => l.action.type === 'bath'));
});

test('образы: первая потеря сердца после первого «Плохо»', () => {
  for (const p of ['strict', 'medium', 'soft']) {
    const r = makeRules(cfg(), p);
    for (const sc of PATTERNS) {
      const res = run(r, sc.key);
      if (res.firstLossH !== null) assert.ok(res.firstBadH !== null && res.firstBadH <= res.firstLossH, `${p}/${sc.key}`);
    }
  }
});
