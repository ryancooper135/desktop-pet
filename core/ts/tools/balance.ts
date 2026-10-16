// Таблица баланса: node core/ts/tools/balance.ts
// Сценарии ухода × варианты строгости. Варианты — только параметры прогона, config/economy.json не меняется.
import { readFileSync } from 'node:fs';
import { makeRules, DISTRESS } from '../src/rules.ts';
import type { Rules } from '../src/rules.ts';
import { act, defaultOwner, forecast } from '../src/engine.ts';
import { SCENARIOS, START_HOUR, ignoreUntilDeath, runScenario, startAt } from '../src/scenarios.ts';
import type { ActFn } from '../src/scenarios.ts';

const DAYS = 30;
const cfg0 = JSON.parse(readFileSync(new URL('../../../config/economy.json', import.meta.url), 'utf8'));
const r = makeRules(cfg0);
const o = defaultOwner(r);
const f1 = (x: number) => x.toFixed(1).replace('.', ',');

const RU: Record<string, string> = { starve: 'голод', dirty: 'грязь', toska: 'тоска' };
const why = (c: string[]) => c.map(x => RU[x]).join(' + ');

function verdict(diedDay: number | null, causes: string[]): string {
  return diedDay === null ? `живёт ≥ ${DAYS} сут` : `† ${f1(diedDay)} сут (${why(causes)})`;
}

// ---------- базовый конфиг: подробно ----------

console.log('## Полный игнор (часы до смерти)\n');
for (const h of [7.5, 10, 14, 18, 22]) console.log(`- старт ${h}: ${f1(ignoreUntilDeath(r, o, startAt(r, h))!)} ч`);
{ const s = startAt(r, 7.5); s.home.kennel = 3; console.log(`- будка L4, старт 7.5: ${f1(ignoreUntilDeath(r, o, s)!)} ч`); }
{
  const s0 = startAt(r, 7.5);
  const ev = forecast(s0, r, o, 80).filter(e => e.kind !== 'low');
  console.log('\nХронология игнора с 07:30: ' + ev.map(e => `${f1((e.t - s0.t) / 3600)} ч ${e.kind}${e.key ? ' ' + e.key : ''}${e.value !== undefined ? ' ' + e.value : ''}`).join(' → '));
}

console.log(`\n## Сценарии с 07:30, ${DAYS} суток, конфиг по умолчанию\n`);
console.log('| Сценарий | Итог | Мин. ❤ | Сытость | Чистота | Энергия | Настроение | Ласка | Движение |');
console.log('|---|---|---|---|---|---|---|---|---|');
for (const sc of SCENARIOS) {
  const res = runScenario(r, o, sc, DAYS);
  const a = res.avgNeeds;
  console.log(`| ${sc.title} | ${verdict(res.diedDay, res.causes)} | ${f1(res.minHearts)} | ${[a.food, a.clean, a.energy, a.fun, a.love, a.walk].map(x => Math.round(x)).join(' | ')} |`);
}
console.log('\nПотребности — средние по почасовым замерам, пока жив (ночь включена). В скобках — беды, активные в момент смерти.');

// ---------- варианты строгости ----------

interface Variant { title: string; cfg?: (c: any) => void; act?: () => ActFn }

const allDistress = (key: string, v: number) => (c: any) => { for (const d of DISTRESS) c.care.hearts.distress[d][key] = v; };

/** Игры подряд в одном заходе (перерыв меньше часа) дают fun_gain × xs[n]. В ядре этого нет, только здесь. */
function diminishing(xs: number[]): () => ActFn {
  return () => {
    let n = 0, last = -Infinity;
    return (s, rr, oo, a) => {
      if (a.type !== 'play') return act(s, rr, oo, a);
      if (s.t - last >= 3600) n = 0;
      const k = xs[Math.min(n, xs.length - 1)];
      const res = act(s, { ...rr, play: { ...rr.play, funGain: rr.play.funGain * k } }, oo, a);
      if (res.ok) { n++; last = s.t; }
      return res;
    };
  };
}

const VARIANTS: Variant[] = [
  { title: '**конфиг сейчас**' },
  { title: 'hours_per_heart 6 (все беды)', cfg: allDistress('hours_per_heart', 6) },
  { title: 'hours_per_heart 8 (все беды)', cfg: allDistress('hours_per_heart', 8) },
  { title: 'hours_per_heart 12 (все беды)', cfg: allDistress('hours_per_heart', 12) },
  { title: 'grace 0 ч (все беды)', cfg: allDistress('grace_h_awake', 0) },
  { title: 'grace 12 ч (все беды)', cfg: allDistress('grace_h_awake', 12) },
  { title: 'grace 24 ч (все беды)', cfg: allDistress('grace_h_awake', 24) },
  { title: 'регенерация сердец выкл', cfg: c => { c.care.hearts.regen_per_h_awake = 0; } },
  { title: 'настроение −4,5/ч днём (было 6)', cfg: c => { c.care.needs.fun.day_per_h = 4.5; } },
  { title: 'игра +25 (было 18)', cfg: c => { c.minigames.fun_gain = 25; } },
  { title: 'игры в заходе ×1 / 0,6 / 0,3', act: diminishing([1, 0.6, 0.3]) },
  { title: 'настроение −4,5/ч + игра +25', cfg: c => { c.care.needs.fun.day_per_h = 4.5; c.minigames.fun_gain = 25; } },
  // для справки: что будет, если грязь (и тоска) вообще не отнимают сердца
  { title: 'грязь без урона', cfg: c => { c.care.hearts.distress.dirty.hours_per_heart = 1e9; } },
  { title: 'грязь и тоска без урона', cfg: c => { c.care.hearts.distress.dirty.hours_per_heart = 1e9; c.care.hearts.distress.toska.hours_per_heart = 1e9; } },
];

function rulesFor(v: Variant): Rules {
  if (!v.cfg) return r;
  const c = structuredClone(cfg0);
  v.cfg(c);
  return makeRules(c);
}

console.log(`\n## Варианты строгости × сценарии (старт 07:30, ${DAYS} суток)\n`);
console.log('Ячейка: † сутки до смерти (причина) или «мин. ❤ / среднее настроение». Игнор — часы до смерти.\n');
console.log(`| Вариант | Игнор | ${SCENARIOS.map(sc => sc.short).join(' | ')} |`);
console.log(`|---|---|${SCENARIOS.map(() => '---').join('|')}|`);
for (const v of VARIANTS) {
  const rv = rulesFor(v);
  const ov = defaultOwner(rv);
  const ign = ignoreUntilDeath(rv, ov, startAt(rv, START_HOUR));
  const cells = SCENARIOS.map(sc => {
    const res = runScenario(rv, ov, sc, DAYS, v.act?.());
    return res.diedDay === null ? `❤ ${f1(res.minHearts)} / ${Math.round(res.avgNeeds.fun)}` : `† ${f1(res.diedDay)} (${why(res.causes)})`;
  });
  console.log(`| ${v.title} | ${ign === null ? '> 200' : f1(ign)} | ${cells.join(' | ')} |`);
}
