// Генератор общих тест-векторов: node core/ts/tools/vectors.ts
// TS прогоняет сценарии и записывает контрольные состояния; Swift (core/swift) обязан их повторить.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { makeRules } from '../src/rules.ts';
import { act, clone, defaultOwner, forecast, level, moods, stepTo } from '../src/engine.ts';
import type { Action, Owner, PetState } from '../src/engine.ts';
import { T0, runDays, startAt } from '../src/scenarios.ts';
import type { TimedAction } from '../src/scenarios.ts';

const cfgUrl = new URL('../../../config/economy.json', import.meta.url);
const r = makeRules(JSON.parse(readFileSync(cfgUrl, 'utf8')));
const outDir = new URL('../../vectors/', import.meta.url);
mkdirSync(outDir, { recursive: true });
const H = 3600;

type Step = { t: number; do: Action; ok: boolean; reason?: string } | { t: number; expect: PetState; level: number; moods: string[] };

/** Переиграть действия с нуля, вставляя контрольные точки каждые checkH часов. */
function record(name: string, o: Owner, start: PetState, actions: TimedAction[], endT: number, checkH = 6, extra: (s: PetState) => void = () => {}) {
  const s = clone(start);
  const steps: Step[] = [];
  const check = (t: number) => { stepTo(s, r, o, t); steps.push({ t, expect: clone(s), level: level(s, r), moods: moods(s, r, o) }); };
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
  writeFileSync(new URL(`${name}.json`, outDir), JSON.stringify({ name, owner: o, start, steps, forecast: { from: clone(s), horizonH: 72, events: fc } }, null, 1) + '\n');
  console.log(name, steps.length, 'шагов,', fc.length, 'событий прогноза');
}

const o = defaultOwner(r);
const oKiev = defaultOwner(r, 180);

// 1. полный игнор до смерти
{ const s = startAt(r, 7.5); record('ignore_0730', o, s, [], s.t + 62 * H); }
// 2. будка L4 + UTC+3 + нестандартный график
{ const s = startAt(r, 14); s.home.kennel = 3; s.home.bed = 2; const ow = { ...oKiev, bedMin: 60, wakeMin: 9 * 60 }; record('kennel4_tz180', ow, s, [], s.t + 90 * H); }
// 3. 4 захода + шаги, 4 дня
{ const s = startAt(r, 7.5); const res = runDays(r, o, clone(s), 4, [8, 13, 18, 22.5], { steps: 6000 }); record('visits4_steps', o, s, res.log, T0 + 4 * 86400); }
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
