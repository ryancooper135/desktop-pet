// Краевые случаи ядра: разбор условий, окна через полночь, пояс, порядок отказов act.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { makeRules, compileCond } from '../src/rules.ts';
import { act, defaultOwner, inWindow, localMin, newPet } from '../src/engine.ts';

const r = makeRules(JSON.parse(readFileSync(new URL('../../../config/economy.json', import.meta.url), 'utf8')));
const o = defaultOwner(r);
const T0 = 1_760_000_000;
const v = { food: 50, clean: 50, energy: 50, fun: 5, love: 5, walk: 50, look: 0 };

test('условия: все операторы и пробелы', () => {
  assert.equal(compileCond('food <= 50')(v), true);
  assert.equal(compileCond('food < 50')(v), false);
  assert.equal(compileCond('food >= 50')(v), true);
  assert.equal(compileCond('food > 50')(v), false);
  assert.equal(compileCond('food == 50')(v), true);
  assert.equal(compileCond('  fun<10&&love<10  ')(v), true);
  assert.equal(compileCond('look > -1.5')(v), true);
  assert.throws(() => compileCond('food = 50'));
  assert.throws(() => compileCond(''));
});

test('окно через полночь и пустое окно', () => {
  assert.equal(inWindow(23 * 60 + 59, 1410, 450), true);
  assert.equal(inWindow(0, 1410, 450), true);
  assert.equal(inWindow(449, 1410, 450), true);
  assert.equal(inWindow(450, 1410, 450), false, 'конец не входит');
  assert.equal(inWindow(1409, 1410, 450), false);
  assert.equal(inWindow(600, 600, 600), false, 'from == to — пусто');
  assert.equal(inWindow(7, 1440 + 5, -1430), true, 'минуты вне суток сворачиваются');
});

test('местная минута при отрицательном поясе', () => {
  const midnightUtc = Math.floor(T0 / 86400) * 86400;
  assert.equal(localMin(midnightUtc, { ...o, tzOffsetMin: 0 }), 0);
  assert.equal(localMin(midnightUtc, { ...o, tzOffsetMin: -300 }), 1140);
  assert.equal(localMin(midnightUtc + 59, { ...o, tzOffsetMin: 330 }), 330, 'секунды отбрасываются');
});

test('порядок отказов act', () => {
  const dead = newPet(r, T0);
  dead.alive = false;
  assert.deepEqual(act(dead, r, o, { type: 'feed', item: 'нет' }), { ok: false, reason: 'dead' }, 'смерть важнее всего');

  const s = newPet(r, T0);
  assert.equal(act(s, r, o, { type: 'feed', item: 'vitamin' }).reason, 'unknown_item', 'витамин — не еда');
  assert.equal(act(s, r, o, { type: 'item', item: 'kibble' }).reason, 'unknown_item', 'корм — не предмет');
  assert.equal(act(s, r, o, { type: 'wake' }).reason, 'not_napping');
  assert.equal(act(s, r, o, { type: 'bath' }).ok, true);
  assert.equal(act(s, r, o, { type: 'feed', item: 'нет' }).reason, 'unknown_item', 'неизвестное раньше ванны');
  assert.equal(act(s, r, o, { type: 'feed', item: 'kibble' }).reason, 'bathing');
  assert.equal(act(s, r, o, { type: 'bath' }).reason, 'bathing');
  assert.equal(act(s, r, o, { type: 'pet' }).ok, true, 'гладить можно и в ванне');
});

test('шаги не переливают шкалу', () => {
  const s = newPet(r, T0);
  assert.equal(act(s, r, o, { type: 'steps', count: 10_000_000 }).ok, true);
  assert.equal(s.needs.walk, 100);
  const z = newPet(r, T0);
  const before = z.needs.walk;
  act(z, r, o, { type: 'steps', count: 0 });
  assert.equal(z.needs.walk, before);
});
