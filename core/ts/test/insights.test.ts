// Желания, настроение, «Пока тебя не было», «Спасти», план уведомлений. Запуск: node --test "core/ts/test/*.test.ts"
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { makeRules } from '../src/rules.ts';
import { act, advance, clone, defaultOwner, forecast, localMin, ownerAsleep, stepTo } from '../src/engine.ts';
import { WANT_SPECS, awaySummary, daypart, mood, notificationPlan, rescue, wants } from '../src/insights.ts';
import { T0, startAt } from '../src/scenarios.ts';

const r = makeRules(JSON.parse(readFileSync(new URL('../../../config/economy.json', import.meta.url), 'utf8')));
const o = defaultOwner(r);
const H = 3600, D = 86400;
const MOODS = ['dead', 'walking', 'critical', 'bath', 'sleep', 'nap', 'hungry', 'smelly', 'dirty', 'tired', 'bored', 'wants_love', 'wants_walk', 'sulky', 'ok'];
const lines = JSON.parse(readFileSync(new URL('../../../content/ru/lines.json', import.meta.url), 'utf8'));

test('желания: сила 0..1, срочные первыми, без игр во сне и в ванне', () => {
  const s = startAt(r, 7.5);
  for (let h = 0; h < 60; h += 1) {
    const x = advance(s, r, o, s.t + h * H);
    const w = wants(x, r, o);
    for (const it of w) assert.ok(it.strength > 0 && it.strength <= 1, `${h}: ${it.key} ${it.strength}`);
    for (let i = 1; i < w.length; i++) {
      const a = w[i - 1], b = w[i];
      assert.ok(a.urgent > b.urgent || (a.urgent === b.urgent && a.strength >= b.strength), `${h}: порядок`);
    }
    if (x.alive && ['sleep', 'nap'].includes(mood(x, r, o))) assert.ok(!w.some(it => it.key === 'play' || it.key === 'sleep'));
  }
  const full = startAt(r, 13, 100);
  assert.deepEqual(wants(full, r, o), []);
  const dirty = startAt(r, 13, 40);
  dirty.needs.clean = 5;
  assert.equal(wants(dirty, r, o)[0].key, 'bath');
  assert.equal(mood(dirty, r, o), 'smelly');
  assert.equal(wants(dirty, r, o)[0].urgent, true);
  act(dirty, r, o, { type: 'bath' });
  assert.ok(!wants(dirty, r, o).some(it => it.key === 'bath' || it.key === 'food' || it.key === 'play'));
  assert.equal(mood(dirty, r, o), 'bath');
  assert.deepEqual(new Set(WANT_SPECS.map(w => w.key)).size, WANT_SPECS.length);
});

test('настроение: полный игнор — сон, голод, критично, смерть', () => {
  const s = startAt(r, 7.5);
  const seen: string[] = [];
  for (let h = 0; h <= 66; h += 0.5) {
    const m = mood(s, r, o, s.t + h * H);
    assert.ok(MOODS.includes(m), m);
    if (seen[seen.length - 1] !== m) seen.push(m);
  }
  assert.equal(seen[0], 'sleep');
  assert.ok(seen.includes('hungry'));
  assert.equal(seen[seen.length - 1], 'dead');
  assert.equal(seen[seen.length - 2], 'critical');
  assert.equal(mood(startAt(r, 13, 100), r, o), 'ok');
  assert.equal(mood(startAt(r, 13, 60), r, o), 'ok');
});

test('время суток', () => {
  const at = (hh: number) => T0 + hh * H;
  assert.equal(daypart(at(8.5), r, o), 'morning');
  assert.equal(daypart(at(13), r, o), 'day');
  assert.equal(daypart(at(21), r, o), 'evening');
  assert.equal(daypart(at(23.6), r, o), 'evening');
  assert.equal(daypart(at(2), r, o), 'night');
  assert.equal(daypart(at(7.9), r, o), 'night');
});

test('«Спасти»: беда → кормить, сытый и чистый → нечего, ночью игру не предлагает', () => {
  const s = startAt(r, 7.5);
  const x = advance(s, r, o, s.t + 30 * H);
  const rs = rescue(x, r, o)!;
  assert.equal(rs.key, 'food');
  assert.equal(rs.because, 'starve');
  assert.equal(act(clone(x), r, o, rs.action).ok, true);
  assert.equal(rescue(startAt(r, 13, 100), r, o), null);
  const night = startAt(r, 2, 80);
  night.needs.fun = 5; night.needs.love = 5;
  const n = rescue(night, r, o)!;
  assert.equal(n.because, 'toska');
  assert.equal(n.key, 'pet');
  const day = startAt(r, 13, 80);
  day.needs.fun = 5; day.needs.love = 5;
  assert.equal(rescue(day, r, o)!.key, 'play');
  const crit = startAt(r, 13, 80);
  crit.hearts = 1.5;
  assert.equal(rescue(crit, r, o)!.key, 'heal');
  const dead = advance(s, r, o, s.t + 80 * H);
  assert.equal(rescue(dead, r, o), null);
});

test('«Пока тебя не было»: итог совпадает с ядром, сон считается, журнал применяется', () => {
  const s = startAt(r, 7.5);
  const a = awaySummary(s, r, o, s.t + 30 * H);
  assert.deepEqual(a.state, advance(s, r, o, s.t + 30 * H));
  assert.equal(a.show, true);
  assert.equal(a.greet, 'welcome_long');
  assert.equal(a.cta, 'cta_hungry');
  assert.equal(awaySummary(s, r, o, s.t + 5 * H).greet, 'welcome');
  assert.ok(Math.abs(a.sleptH - 8.75) < 1e-9, `${a.sleptH}`); // 07:30–08:00 + 23:45–08:00
  assert.ok(a.events.some(e => e.kind === 'sleep') && a.events.some(e => e.kind === 'wake'));
  assert.ok(!a.events.some(e => (e.kind as string) === 'level'));
  for (let i = 1; i < a.events.length; i++) assert.ok(a.events[i].t >= a.events[i - 1].t);
  assert.equal(awaySummary(s, r, o, s.t + H).show, false);

  const journal = [{ t: s.t + 10 * H, action: { type: 'feed' as const, item: 'stew' } }];
  const b = awaySummary(s, r, o, s.t + 30 * H, journal);
  const manual = clone(s);
  stepTo(manual, r, o, journal[0].t);
  act(manual, r, o, journal[0].action);
  stepTo(manual, r, o, s.t + 30 * H);
  assert.deepEqual(b.state, manual);
  assert.ok(b.events.some(e => e.kind === 'act' && e.key === 'feed' && e.ok === true));

  const d = awaySummary(s, r, o, s.t + 80 * H);
  assert.equal(d.died, true);
  assert.equal(d.greet, null);
  assert.equal(d.cta, null);
  assert.equal(d.events[d.events.length - 1].kind, 'death');
});

test('уведомления: ≤1 в день, не в тихие часы, не после смерти, правила 3/14 дней', () => {
  const day = (t: number) => Math.floor((Math.floor(t / 60) + o.tzOffsetMin) / 1440);
  for (const h of [7.5, 13, 22]) {
    const s = startAt(r, h);
    const plan = notificationPlan(s, r, o, s.t, { horizonH: 14 * 24 });
    assert.ok(plan.length > 0);
    const days = plan.map(p => day(p.at));
    assert.equal(new Set(days).size, days.length, 'больше одного в день');
    const death = forecast(s, r, o, 14 * 24).find(e => e.kind === 'death')!;
    for (const p of plan) {
      assert.ok(!ownerAsleep(p.at, o), `${h}: ${localMin(p.at, o)} — тихие часы`);
      assert.ok(p.at < death.t);
      assert.ok(p.at >= s.t + H);
    }
    assert.ok(plan.some(p => p.trigger === 'critical' || p.trigger === 'last_chance'));
  }
  // крепкий питомец, давно не открывали: только «скучаю», раз в 3 дня, до 14 дней
  const s = startAt(r, 13, 100);
  s.home.kennel = 3;
  const lastOpen = s.t - 2.5 * D;
  const plan = notificationPlan(s, r, o, s.t, { horizonH: 14 * 24, lastOpenT: lastOpen });
  for (const p of plan) {
    if (p.at >= lastOpen + 3 * D) assert.equal(p.trigger, 'miss_you');
    assert.ok(p.at < lastOpen + 14 * D);
  }
  assert.ok(plan.some(p => p.trigger === 'miss_you'));
  // в день последнего уведомления больше не зовём
  const sent = notificationPlan(s, r, o, s.t, { horizonH: 14 * 24, lastOpenT: lastOpen, lastSentT: s.t });
  assert.ok(!sent.some(p => day(p.at) === day(s.t)));
  // мёртвому — ничего
  assert.deepEqual(notificationPlan(s, r, o, s.t + 200 * H), []);
});

test('ключи есть в content/ru/lines.json', () => {
  const has = (sec: string, k: string) => assert.ok(k in lines[sec], `${sec}.${k}`);
  for (const m of MOODS) { if (m !== 'dead') has('island', m); has('widget', m); }
  for (const w of WANT_SPECS) has('thoughts', w.key);
  for (const t of ['hungry', 'dirty', 'smelly', 'bored', 'wants_love', 'unwell', 'heart_lost', 'critical', 'last_chance', 'miss_you']) has('notifications', t);
  for (const k of ['welcome', 'welcome_long', 'cta_hungry', 'cta_dirty', 'cta_bored', 'cta_love', 'cta_tired', 'cta_ok']) has('away', k);
});
