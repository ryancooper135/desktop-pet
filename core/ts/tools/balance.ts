import { readFileSync } from 'node:fs';
import { makeRules } from '../src/rules.ts';
import { defaultOwner, forecast, clone, level } from '../src/engine.ts';
import { startAt, runDays, ignoreUntilDeath } from '../src/scenarios.ts';
const r = makeRules(JSON.parse(readFileSync(new URL('../../../config/economy.json', import.meta.url), 'utf8')));
const o = defaultOwner(r);
for (const h of [7.5, 10, 14, 18, 22]) console.log('ignore from', h, '→ death after', ignoreUntilDeath(r, o, startAt(r, h))?.toFixed(1), 'h');
{ const s = startAt(r, 7.5); s.home.kennel = 3; console.log('kennel L4 →', ignoreUntilDeath(r, o, s)?.toFixed(1)); }
const ev = forecast(startAt(r, 7.5), r, o, 80);
console.log(ev.filter(e => e.kind !== 'low').map(e => `${((e.t - startAt(r,7.5).t)/3600).toFixed(1)}h ${e.kind} ${e.key ?? ''} ${e.value ?? ''}`).join('\n'));
for (const [name, v, opts] of [['4 visits', [8, 13, 18, 22.5], { steps: 6000 }], ['3 visits', [8, 14, 21], {}], ['2 visits', [9, 21], {}], ['1 full', [12], {}], ['1 careless', [12], { careless: true }]] as const) {
  const s = startAt(r, 7.5);
  const res = runDays(r, o, s, 14, v as any, opts as any);
  console.log(name, 'alive', res.state.alive, 'died', res.state.diedAt ? ((res.state.diedAt - startAt(r,7.5).t)/86400).toFixed(1)+'d' : '-', 'minHearts', res.minHearts.toFixed(2), 'hearts', res.state.hearts.toFixed(2), 'needs', JSON.stringify(Object.fromEntries(Object.entries(res.state.needs).map(([k, x]) => [k, Math.round(x)]))));
}
