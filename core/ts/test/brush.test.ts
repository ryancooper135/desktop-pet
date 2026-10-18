// Расчесать (care.actions.brush): половина ласки «Погладить», свой откат, отказы как у трюков, монет ядро не знает.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { makeRules } from '../src/rules.ts';
import { BRUSH_COOLDOWN, act, clone, defaultOwner, stepTo } from '../src/engine.ts';
import type { Action, PetState } from '../src/engine.ts';
import { startAt } from '../src/scenarios.ts';

const cfg = JSON.parse(readFileSync(new URL('../../../config/economy.json', import.meta.url), 'utf8'));
const r = makeRules(cfg);
const o = defaultOwner(r);
const H = 3600;
const B: Action = { type: 'brush' };

/** Ласка после «Погладить» на копии без отката поглаживания. */
const petted = (s: PetState) => { const c = clone(s); delete c.cooldowns.pet; assert.equal(act(c, r, o, { type: 'pet' }).ok, true); return c.needs.love; };

test('правила из конфига: доля 0,5, откат 6 ч; без блока — недоступно', () => {
  assert.deepEqual(r.brush, { loveShare: 0.5, cooldownMin: 360 });
  const c2 = clone(cfg); delete c2.care.actions.brush;
  const r2 = makeRules(c2);
  assert.equal(r2.brush, null);
  const s = startAt(r2, 10);
  const before = clone(s);
  assert.deepEqual(act(s, r2, o, B), { ok: false, reason: 'unavailable' });
  assert.deepEqual(s, before);
});

test('ласка — половина «Погладить», с множителем грязи и потолком 100', () => {
  const s = startAt(r, 10); s.needs.love = 40;
  const want = 40 + (petted(s) - 40) * 0.5;
  assert.equal(act(s, r, o, B).ok, true);
  assert.equal(s.needs.love, want);
  assert.equal(want, 40 + r.petLove / 2);

  const dirty = startAt(r, 10); dirty.needs.love = 40; dirty.needs.clean = 20; // love_gain_x 0.7
  assert.equal(act(dirty, r, o, B).ok, true);
  assert.ok(Math.abs(dirty.needs.love - (40 + r.petLove * 0.7 / 2)) < 1e-9);

  const full = startAt(r, 10); full.needs.love = 97; // «Погладить» упрётся в 100: половина от 3, а не от 12
  assert.equal(act(full, r, o, B).ok, true);
  assert.equal(full.needs.love, 98.5);
});

test('только ласка и свой откат: остальное не трогает', () => {
  const s = startAt(r, 10); s.needs.love = 40;
  const before = clone(s);
  act(s, r, o, B);
  const { love: _l, ...restAfter } = s.needs, { love: _b, ...restBefore } = before.needs;
  assert.deepEqual(restAfter, restBefore);
  assert.deepEqual(s.cooldowns, { [BRUSH_COOLDOWN]: s.t + 6 * H });
  assert.equal(s.hearts, before.hearts);
  assert.equal(s.napUntil, before.napUntil);
  // «Погладить» сразу после — можно, и наоборот
  assert.equal(act(s, r, o, { type: 'pet' }).ok, true);
  const p = startAt(r, 10); act(p, r, o, { type: 'pet' });
  assert.equal(act(p, r, o, B).ok, true);
});

test('откат 6 ч: раньше — cooldown без изменений, ровно через 6 ч — можно', () => {
  const s = startAt(r, 9); s.needs.love = 40;
  const t0 = s.t;
  act(s, r, o, B);
  stepTo(s, r, o, t0 + 6 * H - 60);
  const c = clone(s);
  assert.deepEqual(act(s, r, o, B), { ok: false, reason: 'cooldown' });
  assert.deepEqual(s, c);
  stepTo(s, r, o, t0 + 6 * H);
  assert.equal(act(s, r, o, B).ok, true);
});

test('ключ отката не совпадает с расчёской из магазина', () => {
  assert.notEqual(BRUSH_COOLDOWN, 'brush');
  assert.ok(r.items.brush, 'расчёска в shop.consumables есть');
  const s = startAt(r, 10);
  act(s, r, o, B);
  assert.equal(act(s, r, o, { type: 'item', item: 'brush' }).ok, true);
});

test('отказы по порядку: смерть, гуляет, ванна, дрёма, ночь, беда', () => {
  const why = (s: PetState) => { const c = clone(s); const res = act(c, r, o, B); if (!res.ok) assert.deepEqual(c, s, 'отказ не меняет состояние'); return res.reason; };
  const dead = startAt(r, 10); dead.alive = false;
  assert.equal(why(dead), 'dead');
  const away = startAt(r, 10); assert.equal(act(away, r, o, { type: 'walk' }).ok, true);
  assert.equal(why(away), 'away');
  const bath = startAt(r, 10); act(bath, r, o, { type: 'bath' });
  assert.equal(why(bath), 'bathing');
  const nap = startAt(r, 10); nap.napUntil = nap.t + 1800;
  assert.equal(why(nap), 'asleep');
  assert.equal(why(startAt(r, 2)), 'asleep');
  const crit = startAt(r, 10); crit.hearts = 2;
  assert.equal(why(crit), 'unwell');
  // беда с откатом — сначала беда: как у трюков в приложении
  const both = startAt(r, 10); act(both, r, o, B); both.hearts = 2;
  assert.equal(why(both), 'unwell');
  // Плохо (2), но не Критично — можно
  const bad = startAt(r, 10); bad.needs.food = 0;
  assert.equal(why(bad), undefined);
});
