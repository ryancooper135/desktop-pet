// Сейв с мёртвым питомцем без diedAt (битый или старый) не должен ронять прогноз.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { defaultOwner, forecast, newPet } from '../src/engine.ts';
import { makeRules } from '../src/rules.ts';

test('forecast: мёртвый без diedAt — событие смерти на s.t, без падения', () => {
  const r = makeRules(JSON.parse(readFileSync(new URL('../../../config/economy.json', import.meta.url), 'utf8')));
  const s = newPet(r, 1_700_000_000);
  s.alive = false;
  const ev = forecast(s, r, defaultOwner(r), 24);
  assert.equal(ev.length, 1);
  assert.equal(ev[0].kind, 'death');
  assert.equal(ev[0].t, s.t);
});
