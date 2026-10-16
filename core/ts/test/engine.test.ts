// Баланс из RESEARCH/04 §2.2 и инварианты движка. Запуск: node --test core/ts/test/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { makeRules, compileCond } from '../src/rules.ts';
import { act, advance, clone, defaultOwner, forecast, level, moods, ownerAsleep, stepTo } from '../src/engine.ts';
import { T0, ignoreUntilDeath, runDays, startAt } from '../src/scenarios.ts';

const r = makeRules(JSON.parse(readFileSync(new URL('../../../config/economy.json', import.meta.url), 'utf8')));
const o = defaultOwner(r);
const H = 3600;

test('условия из конфига', () => {
  const c = compileCond('fun < 10 && love < 10');
  const v = { food: 50, clean: 50, energy: 50, fun: 5, love: 5, walk: 50, look: 0 };
  assert.equal(c(v), true);
  assert.equal(c({ ...v, love: 10 }), false);
  assert.throws(() => compileCond('mood < 3'));
});

test('полный игнор: смерть через 2,4–2,9 суток (§2.2)', () => {
  const expect: [number, number][] = [[7.5, 59], [10, 58], [14, 68.5], [18, 66], [22, 66]];
  for (const [h, want] of expect) {
    const got = ignoreUntilDeath(r, o, startAt(r, h))!;
    assert.ok(Math.abs(got - want) <= 1.5, `старт ${h}:00 → ${got.toFixed(1)} ч, ждали ≈${want}`);
  }
});

test('будка L4 заметно страхует (≈84 ч)', () => {
  const s = startAt(r, 7.5);
  s.home.kennel = 3;
  const got = ignoreUntilDeath(r, o, s)!;
  assert.ok(got > 78 && got < 90, `${got}`);
});

test('хронология игнора: L1 → беда → сердца → последний шанс → смерть', () => {
  const s = startAt(r, 7.5);
  const ev = forecast(s, r, o, 80);
  const at = (kind: string, pred: (e: any) => boolean = () => true) => {
    const e = ev.find(e => e.kind === kind && pred(e));
    return e ? (e.t - s.t) / H : null;
  };
  assert.ok(at('level', e => e.value === 1)! < 12);
  assert.ok(at('distress', e => e.key === 'starve')! < 24);
  const first = at('heart', e => e.value === 4)!;
  assert.ok(first > 24 && first < 36, `первое сердце на ${first} ч`);
  assert.ok(at('last_chance')! > 45);
  assert.equal(ev.at(-1)!.kind, 'death');
  // события идут по времени
  for (let i = 1; i < ev.length; i++) assert.ok(ev[i].t >= ev[i - 1].t);
});

test('4 захода + 6000 шагов: 14 дней без потерь', () => {
  const res = runDays(r, o, startAt(r, 7.5), 14, [8, 13, 18, 22.5], { steps: 6000 });
  assert.equal(res.state.alive, true);
  assert.equal(res.minHearts, 5);
});

test('3 захода: без потерь', () => {
  const res = runDays(r, o, startAt(r, 7.5), 14, [8, 14, 21]);
  assert.equal(res.minHearts, 5);
});

test('1 заход «до максимума»: живёт три недели', () => {
  const res = runDays(r, o, startAt(r, 7.5), 21, [19], { full: true });
  assert.equal(res.state.alive, true);
  assert.ok(res.minHearts >= 4.5);
});

test('1 небрежный заход (только еда): медленное угасание, не мгновенно', () => {
  // §2.2 обещал ≈6 суток; ставки урона из того же конфига дают ≈3,6 — см. core/README.md
  const res = runDays(r, o, startAt(r, 7.5), 14, [12], { careless: true });
  assert.equal(res.state.alive, false);
  const days = (res.state.diedAt! - startAt(r, 7.5).t) / 86400;
  assert.ok(days > 3 && days < 8, `${days}`);
});

test('ночью хозяина урон и льгота стоят', () => {
  const s = startAt(r, 7.5);
  s.needs.food = 0; s.needs.clean = 0; s.needs.fun = 0; s.needs.love = 0;
  // дожить до момента, когда хозяин заснул
  let t = s.t;
  while (!ownerAsleep(t, o)) t += 60;
  stepTo(s, r, o, t);
  const h = s.hearts, g = { ...s.grace };
  let t2 = t;
  while (ownerAsleep(t2 + 60, o)) t2 += 60;
  stepTo(s, r, o, t2);
  assert.equal(s.hearts, h);
  assert.deepEqual(s.grace, g);
});

test('смерть не раньше 3 ч после подъёма хозяина', () => {
  for (const h of [7.5, 10, 14, 18, 22]) {
    const s = startAt(r, h);
    ignoreUntilDeath(r, o, s);
    const m = ((Math.floor(s.diedAt! / 60) % 1440) + 1440) % 1440;
    const sinceWake = (m - o.wakeMin + 1440) % 1440;
    assert.ok(sinceWake >= r.hearts.noDeathAfterWakeH * 60, `смерть в ${Math.floor(m / 60)}:${m % 60}`);
  }
});

test('по кускам и сразу — одно и то же', () => {
  const s = startAt(r, 9);
  const whole = advance(s, r, o, s.t + 50 * H);
  let part = clone(s);
  for (const dt of [1, 59, 61, 3599, 7 * H + 17, 13 * H, 29 * H]) part = advance(part, r, o, part.t + dt);
  part = advance(part, r, o, s.t + 50 * H);
  assert.deepEqual(part, whole);
});

test('ванна: недоступна еда и игра, после — чистота 100', () => {
  const s = startAt(r, 10);
  s.needs.clean = 20;
  assert.ok(act(s, r, o, { type: 'bath' }).ok);
  assert.equal(act(s, r, o, { type: 'feed', item: 'stew' }).reason, 'bathing');
  assert.equal(act(s, r, o, { type: 'play' }).reason, 'bathing');
  assert.ok(moods(s, r, o).includes('bath'));
  stepTo(s, r, o, s.t + r.bathMinutes[0] * 60 + 60);
  assert.equal(s.bathUntil, null);
  assert.ok(s.needs.clean >= 99);
});

test('дрёма при низкой энергии, кормление будит', () => {
  const s = startAt(r, 11);
  s.needs.energy = r.needs.energy.nap_below - 1;
  stepTo(s, r, o, s.t + 120);
  assert.notEqual(s.napUntil, null);
  assert.equal(act(s, r, o, { type: 'play' }).reason, 'asleep');
  assert.ok(act(s, r, o, { type: 'feed', item: 'kibble' }).ok);
  assert.equal(s.napUntil, null);
});

test('кулдаун ласки и золотой косточки', () => {
  const s = startAt(r, 12);
  s.needs.love = 10;
  assert.ok(act(s, r, o, { type: 'pet' }).ok);
  assert.equal(s.needs.love, 10 + r.petLove);
  assert.equal(act(s, r, o, { type: 'pet' }).reason, 'cooldown');
  stepTo(s, r, o, s.t + r.petCooldownMin * 60);
  assert.ok(act(s, r, o, { type: 'pet' }).ok);
  s.hearts = 3;
  assert.ok(act(s, r, o, { type: 'feed', item: 'gold_bone' }).ok);
  assert.equal(s.hearts, 3.5);
  assert.equal(act(s, r, o, { type: 'feed', item: 'gold_bone' }).reason, 'cooldown');
  assert.equal(act(s, r, o, { type: 'feed', item: 'nope' }).reason, 'unknown_item');
});

test('уровни тревоги', () => {
  const s = startAt(r, 12);
  assert.equal(level(s, r), 0);
  s.needs.fun = 20; assert.equal(level(s, r), 1);
  s.needs.food = 0; assert.equal(level(s, r), 2);
  s.hearts = 2; assert.equal(level(s, r), 3);
});

test('шаги кормят шкалу прогулки', () => {
  const s = startAt(r, 12);
  s.needs.walk = 0;
  act(s, r, o, { type: 'steps', count: 4000 });
  assert.equal(s.needs.walk, 4000 / r.needs.walk.steps_per_point);
});

test('часовой пояс сдвигает ночь', () => {
  const kiev = defaultOwner(r, 180);
  // 21:00 UTC = 00:00 в UTC+3: хозяин спит, а в UTC — ещё нет
  const t = T0 + 21 * H;
  assert.equal(ownerAsleep(t, kiev), true);
  assert.equal(ownerAsleep(t, o), false);
});
