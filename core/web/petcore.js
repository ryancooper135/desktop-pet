// Сгенерировано core/ts/tools/bundle-web.ts из core/ts/src. Руками не править.
(function (g) {
'use strict';
// Правила из config/economy.json в удобном для движка виде.
// Условия вида "food < 20" и "fun < 10 && love < 10" компилируются один раз.

const NEEDS = ['food', 'clean', 'energy', 'fun', 'love', 'walk', 'look']         ;
                                        
const DISTRESS = ['starve', 'dirty', 'toska']         ;
                                               
const HOME_LINES = ['bath', 'bed', 'kitchen', 'kennel', 'play', 'yard']         ;
                                                 

                                        
                                        
                                                      

                        
                           
                                        
                                                                                    
                                                                                                                                      
                                                                                        
                        
                  
                         
                                                
                               
                                
                                   
                  
                                                                                                
                                                                                                            
 

/** Прогулка с находкой: care.walk_out. */
                          
                                                               
                 
                                                                    
                                                                                    
                                                                       
                                                                
                                                                       
 

function walkOut(w     )                 {
  if (!w) return null;
  return {
    minMin: w.minutes[0], maxMin: w.minutes[1], requires: compileCond(w.requires),
    decayX: numbers(w.decay_x)                          , energyX: w.energy_decay_x ?? 1,
    onReturn: numbers(w.on_return), finds: w.finds.map((f     ) => f.id),
  };
}

const COND_PART = /^\s*(\w+)\s*(<=|>=|==|<|>)\s*(-?\d+(?:\.\d+)?)\s*$/;

function compileCond(expr        )       {
  const parts = expr.split('&&').map(p => {
    const m = COND_PART.exec(p);
    if (!m || !(NEEDS                     ).includes(m[1])) throw new Error(`условие не разобрано: ${expr}`);
    const need = m[1]        , op = m[2], x = Number(m[3]);
    switch (op) {
      case '<': return (v      ) => v[need] < x;
      case '<=': return (v      ) => v[need] <= x;
      case '>': return (v      ) => v[need] > x;
      case '>=': return (v      ) => v[need] >= x;
      default: return (v      ) => v[need] === x;
    }
  });
  return v => parts.every(f => f(v));
}

function hhmm(s        )         {
  const [h, m] = s.split(':').map(Number);
  return h * 60 + m;
}

function numbers(o     )         {
  const out         = {};
  for (const [k, v] of Object.entries(o ?? {})) if (!k.startsWith('_') && (typeof v === 'number' || typeof v === 'boolean')) out[k] = v;
  return out;
}

// ---------- пресеты строгости смерти (care.hearts.presets) ----------

/** Глубокое слияние: объекты по ключам, остальное заменяется; ключи с «_» — пометки, пропускаются. */
function mergePatch(base     , patch     )      {
  const obj = (v     ) => typeof v === 'object' && v !== null && !Array.isArray(v);
  if (!obj(base) || !obj(patch)) return patch;
  const out = { ...base };
  for (const k of Object.keys(patch)) if (!k.startsWith('_')) out[k] = mergePatch(base[k], patch[k]);
  return out;
}

/** Имена пресетов строгости из конфига: strict, medium, soft. */
function presetNames(cfg     )           {
  return Object.keys(cfg.care?.hearts?.presets ?? {}).filter(k => !k.startsWith('_'));
}

/** Конфиг с наложенным пресетом (по умолчанию care.hearts.preset). Без пресетов в конфиге — как есть. */
function withPreset(cfg     , preset         )                                      {
  const h = cfg.care.hearts;
  const name = preset ?? h.preset ?? null;
  if (name === null) return { cfg, preset: null };
  // как в Swift: только собственный ключ-объект (не toString из прототипа и не строка)
  const patch = h.presets && Object.hasOwn(h.presets, name) ? h.presets[name] : undefined;
  if (name.startsWith('_') || typeof patch !== 'object' || patch === null || Array.isArray(patch)) throw new Error(`нет пресета строгости: ${name}`);
  return { cfg: { ...cfg, care: { ...cfg.care, hearts: mergePatch(h, patch) } }, preset: name };
}

function makeRules(cfg0     , presetName         )        {
  const { cfg, preset } = withPreset(cfg0, presetName);
  const care = cfg.care, h = care.hearts;
  const distress = {}                     ;
  for (const d of DISTRESS) {
    const x = h.distress[d];
    distress[d] = { cond: compileCond(x.when), graceH: x.grace_h_awake, hoursPerHeart: x.hours_per_heart };
  }
  const food                         = {};
  for (const f of cfg.shop.food) food[f.id] = numbers(f);
  const items                         = {};
  for (const c of cfg.shop.consumables) items[c.id] = numbers(c);
  const home = {}                 ;
  for (const line of HOME_LINES) home[line] = cfg.home_upgrades[line].levels.map((l     ) => numbers(l.buff));
  return {
    needs: care.needs,
    cross: care.cross_effects.map((c     ) => ({ cond: compileCond(c.if), then: numbers(c.then) })),
    distress,
    hearts: {
      max: h.max, regenPerH: h.regen_per_h_awake, regenNightX: h.regen_night_x, regenAllGe: h.regen_requires_all_ge,
      lastChanceH: h.last_heart.timer_h_awake, noDeathAfterWakeH: h.last_heart.no_death_first_h_after_wake,
    },
    night: {
      bedMin: hhmm(care.night.default_bed), wakeMin: hhmm(care.night.default_wake),
      afterBedMin: care.night.pet_sleep_offset_min.after_bed, afterWakeMin: care.night.pet_sleep_offset_min.after_wake,
    },
    bathMinutes: care.bath_minutes_by_level,
    petLove: care.actions.pet.love,
    petCooldownMin: care.cooldowns_min.pet,
    play: { funGain: cfg.minigames.fun_gain, energyCost: cfg.minigames.energy_cost },
    food, items, home,
    warnLow: cfg.levels?.warn_low ?? 30,
    preset,
    walkOut: walkOut(care.walk_out),
  };
}

// Ядро питомца: состояние считается от времени (ленивый пересчёт), а не тикает в фоне.
// Шаг — ровно 1 минута, состояние двигается только целыми минутами, поэтому
// «посчитать сразу до T» и «посчитать по кускам до T» дают одно и то же.
// Порядок операций с плавающей точкой должен совпадать со Swift-версией (core/swift):
// общие тест-векторы в core/vectors сверяют обе.

/** Прогулка с находкой (care.walk_out). */
                                                                     

                    
                                  
                                  
                   
                    
                    
                                    
                    
                     

                                                           

const STEP = 60;
/** Сколько сытости автокормушка даёт за раз (как миска корма). */
const AUTOFEED_PORTION = 20;
const DH = 1 / 60;
const CARE         = ['food', 'clean', 'fun', 'love', 'walk'];
const WATCH         = ['food', 'clean', 'fun', 'love'];

function defaultOwner(r       , tzOffsetMin = 0)        {
  return { bedMin: r.night.bedMin, wakeMin: r.night.wakeMin, tzOffsetMin };
}

function newPet(r       , t        )           {
  const needs = {}        ;
  for (const n of NEEDS) needs[n] = r.needs[n].start;
  const home = {}                            ;
  for (const l of HOME_LINES) home[l] = 0;
  return {
    t, needs, hearts: r.hearts.max, grace: { starve: 0, dirty: 0, toska: 0 },
    lastChanceH: null, napUntil: null, bathUntil: null, lastHeartLossT: null, cooldowns: {},
    home, alive: true, diedAt: null, cause: null, outing: null, finds: {}, pantry: 0,
  };
}

function clone(s          )           {
  return structuredClone(s);
}

// ---------- время суток ----------

function localMin(t        , o       )         {
  return (((Math.floor(t / 60) + o.tzOffsetMin) % 1440) + 1440) % 1440;
}

function inWindow(m        , from        , to        )          {
  const a = ((from % 1440) + 1440) % 1440, b = ((to % 1440) + 1440) % 1440;
  return a <= b ? m >= a && m < b : m >= a || m < b;
}

function ownerAsleep(t        , o       )          {
  return inWindow(localMin(t, o), o.bedMin, o.wakeMin);
}

function petNight(t        , r       , o       )          {
  return inWindow(localMin(t, o), o.bedMin + r.night.afterBedMin, o.wakeMin + r.night.afterWakeMin);
}

// ---------- множители ----------

const clamp = (v        ) => (v < 0 ? 0 : v > 100 ? 100 : v);

function homeBuff(s          , r       , line          )         {
  return r.home[line][s.home[line]] ?? {};
}

// Улучшения дома (по линиям в порядке HOME_LINES), затем перекрёстные эффекты в порядке конфига.
function mods(s          , r       )         {
  const m         = {};
  const add = (e        ) => {
    for (const k of Object.keys(e)) {
      const v = e[k];
      if (typeof v === 'number' && k.endsWith('_x')) m[k] = ((m[k]                      ) ?? 1) * v;
      else m[k] = v;
    }
  };
  for (const l of HOME_LINES) add(homeBuff(s, r, l));
  for (const c of r.cross) if (c.cond(s.needs)) add(c.then);
  return m;
}

const x = (m        , k        ) => (typeof m[k] === 'number' ? (m[k]          ) : 1);
const num = (m        , k        ) => (typeof m[k] === 'number' ? (m[k]          ) : 0);

function maxHearts(s          , r       )         {
  const b = homeBuff(s, r, 'kennel');
  return typeof b.max_hearts === 'number' ? b.max_hearts : r.hearts.max;
}

// ---------- шаг ----------

function finishBath(s          , r       ) {
  const b = homeBuff(s, r, 'bath');
  s.needs.clean = 100;
  s.needs.fun = clamp(s.needs.fun + num(b, 'fun_after_bath'));
  s.needs.look = clamp(s.needs.look + num(b, 'look_after_bath'));
  s.bathUntil = null;
}

// ---------- прогулка ----------

/** FNV-1a 32 бит по ASCII-строке: одинаково в TS и Swift, без Math.random. */
function fnv32(str        )         {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

/** Сколько прогулок уже было: сумма альбома находок. */
function walksDone(s          )         {
  let n = 0;
  for (const k of Object.keys(s.finds ?? {})) n += s.finds[k];
  return n;
}

/** Вернуться с прогулки: прибавка шкал и находка в альбом. */
function finishWalk(s          , r       ) {
  const o = s.outing ;
  if (r.walkOut) applyEffect(s, r.walkOut.onReturn, maxHearts(s, r));
  if (!s.finds) s.finds = {};
  s.finds[o.find] = (s.finds[o.find] ?? 0) + 1;
  s.outing = null;
}

/** Автокормушка кухни (бафф autofeed_below): дома и не в ванне, сытость ниже порога — порция из запаса. */
function autofeed(s          , r       ) {
  const below = num(homeBuff(s, r, 'kitchen'), 'autofeed_below');
  const left = s.pantry ?? 0;
  if (below <= 0 || left <= 0 || s.outing != null || s.bathUntil !== null || s.needs.food >= below) return;
  const p = Math.min(left, AUTOFEED_PORTION);
  s.needs.food = clamp(s.needs.food + p);
  s.pantry = left - p;
}

/** Один шаг в 1 минуту (на месте). Снаружи ядра зовите stepTo/advance. */
function step(s          , r       , o       ) {
  const t = s.t;
  if (s.napUntil !== null && t >= s.napUntil) s.napUntil = null;
  if (s.bathUntil !== null && t >= s.bathUntil) finishBath(s, r);
  // прогулка кончается в until; раньше — если наступила ночь питомца или вдруг беда
  if (s.outing != null && (t >= s.outing.until || r.walkOut === null || petNight(t, r, o) || DISTRESS.some(d => r.distress[d].cond(s.needs)))) {
    finishWalk(s, r);
  }
  const wo = s.outing != null ? r.walkOut : null; // гуляет: шкалы по своим множителям, урона и смерти нет
  autofeed(s, r);

  const asleep = ownerAsleep(t, o);
  const night = petNight(t, r, o);
  if (!night && petNight(t - STEP, r, o)) {
    s.needs.love = clamp(s.needs.love + num(homeBuff(s, r, 'bed'), 'love_on_wake'));
  }
  const en = r.needs.energy;
  if (!night && wo === null && s.napUntil === null && s.bathUntil === null && s.needs.energy < en.nap_below) {
    s.napUntil = t + en.nap_minutes * 60;
  }
  const sleeping = night || s.napUntil !== null;
  const md = mods(s, r);
  const active = DISTRESS.map(d => r.distress[d].cond(s.needs));
  const ge = r.hearts.regenAllGe;
  const regenOk = WATCH.every(n => s.needs[n] >= ge);

  // шкалы
  for (const n of CARE) {
    const c = r.needs[n];
    const rate = sleeping ? c.night_per_h : c.day_per_h;
    let k = x(md, n + '_decay_x');
    if (n === 'food' && night) k = k * x(md, 'night_food_decay_x');
    if (wo !== null) k = k * (wo.decayX[n] ?? 1);
    s.needs[n] = clamp(s.needs[n] - rate * k * DH);
  }
  if (night) s.needs.energy = clamp(s.needs.energy + en.night_regen_per_h * x(md, 'night_energy_regen_x') * x(md, 'sleep_regen_x') * DH);
  else if (s.napUntil !== null) s.needs.energy = clamp(s.needs.energy + en.nap_regen_per_h * DH);
  else s.needs.energy = clamp(s.needs.energy - en.day_per_h * x(md, 'energy_decay_x') * (wo !== null ? wo.energyX : 1) * DH);
  s.needs.look = clamp(s.needs.look - r.needs.look.per_day / 24 * DH);

  // сердца: урон и «льготы» копятся только в бодрые часы хозяина
  const h = r.hearts;
  let dmg = 0;
  let anyActive = false;
  DISTRESS.forEach((d, i) => {
    if (!active[i]) { s.grace[d] = 0; return; }
    anyActive = true;
    if (asleep || wo !== null) return;
    s.grace[d] = s.grace[d] + DH;
    const rd = r.distress[d];
    if (s.grace[d] > rd.graceH) dmg = dmg + DH / rd.hoursPerHeart;
  });
  if (dmg > 0 && s.hearts > 1) {
    const before = s.hearts;
    s.hearts = Math.max(1, s.hearts - dmg * x(md, 'heart_damage_x'));
    if (Math.ceil(s.hearts - 1e-9) < Math.ceil(before - 1e-9)) s.lastHeartLossT = t;
  }
  const maxH = maxHearts(s, r);
  if (!anyActive && regenOk && s.hearts < maxH) {
    s.hearts = Math.min(maxH, s.hearts + h.regenPerH * (asleep ? h.regenNightX : 1) * x(md, 'heart_regen_x') * DH);
  }

  // последнее сердце: таймер на бодрые часы, смерть не раньше чем через 3 ч после подъёма
  if (s.hearts > 1) s.lastChanceH = null;
  else {
    if (s.lastChanceH === null) s.lastChanceH = h.lastChanceH;
    if (!asleep && wo === null && anyActive) {
      s.lastChanceH = s.lastChanceH - DH;
      const sinceWake = (localMin(t, o) - o.wakeMin + 1440) % 1440;
      if (s.lastChanceH <= 0 && sinceWake >= h.noDeathAfterWakeH * 60) {
        s.alive = false;
        s.diedAt = t + STEP;
        s.cause = DISTRESS[active.indexOf(true)];
      }
    }
  }
  s.t = t + STEP;
}

/** Досчитать состояние до момента T (на месте). Остаток меньше минуты ждёт следующего вызова. */
function stepTo(s          , r       , o       , T        )           {
  while (s.alive && s.t + STEP <= T) step(s, r, o);
  return s;
}

function advance(s          , r       , o       , T        )           {
  return stepTo(clone(s), r, o, T);
}

// ---------- действия ----------

function applyEffect(s          , e        , maxH        ) {
  for (const n of NEEDS) if (typeof e[n] === 'number') s.needs[n] = clamp(s.needs[n] + (e[n]          ));
  if (typeof e.hearts === 'number') s.hearts = Math.min(maxH, s.hearts + e.hearts);
}

/** Действие в момент s.t (сначала досчитай stepTo). Меняет s на месте. */
function act(s          , r       , o       , a        )            {
  if (!s.alive) return { ok: false, reason: 'dead' };
  // гуляет: дома никого, принимаются только шаги хозяина
  if (s.outing != null && a.type !== 'steps') return { ok: false, reason: 'away' };
  const t = s.t;
  const md = mods(s, r);
  const cooling = (k        ) => s.cooldowns[k] !== undefined && s.cooldowns[k] > t;
  switch (a.type) {
    case 'feed':
    case 'item': {
      const e = a.type === 'feed' ? r.food[a.item] : r.items[a.item];
      if (!e) return { ok: false, reason: 'unknown_item' };
      if (s.bathUntil !== null) return { ok: false, reason: 'bathing' };
      if (cooling(a.item)) return { ok: false, reason: 'cooldown' };
      if (a.type === 'feed') {
        s.napUntil = null;
        s.pantry = num(homeBuff(s, r, 'kitchen'), 'storage'); // покормил — заодно пополнил запас на кухне
      }
      applyEffect(s, e, maxHearts(s, r));
      if (typeof e.cooldown_h === 'number') s.cooldowns[a.item] = t + e.cooldown_h * 3600;
      return { ok: true };
    }
    case 'pet': {
      if (cooling('pet')) return { ok: false, reason: 'cooldown' };
      s.needs.love = clamp(s.needs.love + r.petLove * x(md, 'love_gain_x'));
      s.cooldowns.pet = t + r.petCooldownMin * 60;
      return { ok: true };
    }
    case 'play': {
      if (s.bathUntil !== null) return { ok: false, reason: 'bathing' };
      if (s.napUntil !== null || petNight(t, r, o)) return { ok: false, reason: 'asleep' };
      if (md.refuses_games === true) return { ok: false, reason: 'tired' };
      s.needs.fun = clamp(s.needs.fun + r.play.funGain * x(md, 'fun_gain_x'));
      s.needs.energy = clamp(s.needs.energy - r.play.energyCost);
      return { ok: true };
    }
    case 'bath': {
      if (s.bathUntil !== null) return { ok: false, reason: 'bathing' };
      s.napUntil = null;
      s.bathUntil = t + r.bathMinutes[s.home.bath] * 60;
      return { ok: true };
    }
    case 'steps': {
      s.needs.walk = clamp(s.needs.walk + a.count / r.needs.walk.steps_per_point);
      return { ok: true };
    }
    case 'wake': {
      if (s.napUntil === null) return { ok: false, reason: 'not_napping' };
      s.napUntil = null;
      return { ok: true };
    }
    case 'walk': {
      const w = r.walkOut;
      if (w === null) return { ok: false, reason: 'unavailable' };
      if (s.bathUntil !== null) return { ok: false, reason: 'bathing' };
      if (s.napUntil !== null || petNight(t, r, o)) return { ok: false, reason: 'asleep' };
      if (level(s, r) === 3 || DISTRESS.some(d => r.distress[d].cond(s.needs))) return { ok: false, reason: 'unwell' };
      if (!w.requires(s.needs)) return { ok: false, reason: 'not_ready' };
      // длительность и находка — от минуты старта и числа прошлых прогулок
      const m = Math.floor(t / 60), n = walksDone(s);
      let dur = w.minMin + fnv32(`walk:${m}:${n}`) % (w.maxMin - w.minMin + 1);
      for (let k = 1; k <= dur; k++) if (petNight(t + k * 60, r, o)) { dur = k; break; }
      if (dur < w.minMin) return { ok: false, reason: 'too_late' };
      s.outing = { from: t, until: t + dur * 60, find: w.finds[fnv32(`find:${m}:${n}`) % w.finds.length] };
      return { ok: true };
    }
  }
}

// ---------- что показывать ----------

/** 0 — всё хорошо, 1 «Просит», 2 «Плохо», 3 «Критично». */
function level(s          , r       )         {
  if (!s.alive || s.hearts <= 2) return 3;
  if (DISTRESS.some(d => r.distress[d].cond(s.needs))) return 2;
  if (s.lastHeartLossT !== null && s.t - s.lastHeartLossT < 12 * 3600) return 2;
  if (WATCH.some(n => s.needs[n] < r.warnLow)) return 1;
  return 0;
}

/** Видимые состояния для виджета и острова. */
function moods(s          , r       , o       )           {
  if (!s.alive) return ['dead'];
  const out           = [];
  if (s.outing != null) out.push('walking');
  if (s.bathUntil !== null) out.push('bath');
  if (petNight(s.t, r, o)) out.push('sleep');
  else if (s.napUntil !== null) out.push('nap');
  if (level(s, r) === 3) out.push('critical');
  const v = s.needs;
  if (v.food < 25) out.push('hungry');
  if (v.clean < 10) out.push('smelly');
  else if (v.clean < 25) out.push('dirty');
  if (v.energy < 20) out.push('tired');
  if (v.fun < 30) out.push('bored');
  if (v.love < 35) out.push('wants_love');
  return out;
}

                                
            
                                                                                                    
               
                 
 

/** Что уже было до начала наблюдения: от этого считаются новые события прогноза. */
                                                                                                                                          

function tracker(s          , r       )          {
  return {
    low: new Set(WATCH.filter(n => s.needs[n] < r.warnLow)),
    dist: new Set(DISTRESS.filter(d => r.distress[d].cond(s.needs))),
    lvl: level(s, r),
    hc: Math.ceil(s.hearts - 1e-9),
    lc: s.lastChanceH !== null,
    out: s.outing?.find ?? null,
    pantry: s.pantry ?? 0,
  };
}

/** После шага: дописать в ev новые события (back_home, autofeed, low, distress, heart, last_chance, level). */
function observe(tr         , s          , r       , ev                 ) {
  // вернулся с прогулки в начале этого шага: время — начало шага (= until), key — находка
  if (tr.out !== null && s.outing == null) ev.push({ t: s.t - STEP, kind: 'back_home', key: tr.out });
  tr.out = s.outing?.find ?? null;
  // поел из автокормушки в начале этого шага: value — сколько сытости
  const left = s.pantry ?? 0;
  if (left < tr.pantry) ev.push({ t: s.t - STEP, kind: 'autofeed', value: tr.pantry - left });
  tr.pantry = left;
  for (const n of WATCH) if (s.needs[n] < r.warnLow && !tr.low.has(n)) { tr.low.add(n); ev.push({ t: s.t, kind: 'low', key: n }); }
  for (const d of DISTRESS) {
    const on = r.distress[d].cond(s.needs);
    if (on && !tr.dist.has(d)) { tr.dist.add(d); ev.push({ t: s.t, kind: 'distress', key: d }); }
    if (!on) tr.dist.delete(d);
  }
  const c = Math.ceil(s.hearts - 1e-9);
  if (c < tr.hc) ev.push({ t: s.t, kind: 'heart', value: c });
  tr.hc = c;
  if (s.lastChanceH !== null && !tr.lc) ev.push({ t: s.t, kind: 'last_chance' });
  tr.lc = s.lastChanceH !== null;
  const l = level(s, r);
  if (l !== tr.lvl) { ev.push({ t: s.t, kind: 'level', value: l }); tr.lvl = l; }
}

/** Что случится, если никто не придёт: для локальных уведомлений и «умрёт в чт ~15:00». */
function forecast(s0          , r       , o       , horizonH = 72)                  {
  const s = clone(s0);
  const end = s.t + horizonH * 3600;
  const ev                  = [];
  const tr = tracker(s, r);
  while (s.alive && s.t + STEP <= end) {
    step(s, r, o);
    observe(tr, s, r, ev);
  }
  if (!s.alive) ev.push({ t: s.diedAt ?? s.t, kind: 'death', key: s.cause ?? undefined });
  return ev;
}

// Что показать и когда позвать: желания для пузыря, одно настроение для реплик, «Пока тебя не было»,
// кнопка «Спасти» и план локальных уведомлений. Всё считается из состояния ядра и не меняет баланс.
// Swift-порт — core/swift/Sources/PetCore/Insights.swift, сверка по общим векторам core/vectors.
// Имена верхнего уровня не должны совпадать с engine.ts и rules.ts: бандл склеивает их в одну область.


// Ключи совпадают с content/ru/lines.json: желания — thoughts, настроения — widget/island, триггеры — notifications, экран — away.
                                                                          
                                                                                                                                                                                 
                                                              
                                                                                                                                                 

// Пороги показа (не баланс): from — с какого значения шкалы питомец начинает хотеть,
// mood — ниже какого значения желание становится настроением, w — вес при сортировке.
                                                                                                            
const WANT_SPECS             = [
  { key: 'food', need: 'food', from: 50, mood: 25, w: 1, moodKey: 'hungry' },
  { key: 'bath', need: 'clean', from: 50, mood: 25, w: 0.8, moodKey: 'dirty' }, // ниже SMELLY_BELOW — smelly
  { key: 'sleep', need: 'energy', from: 30, mood: 20, w: 0.6, moodKey: 'tired' },
  { key: 'play', need: 'fun', from: 50, mood: 30, w: 0.7, moodKey: 'bored' },
  { key: 'pet', need: 'love', from: 50, mood: 35, w: 0.7, moodKey: 'wants_love' },
  { key: 'walk', need: 'walk', from: 30, mood: 15, w: 0.4, moodKey: 'wants_walk' },
];
const WANT_DISTRESS                              = { starve: ['food'], dirty: ['bath'], toska: ['play', 'pet'] };
const SMELLY_BELOW = 10;        // как в moods(): чистота ниже — smelly, ниже 25 — dirty
const PART_MIN = 180;           // утро — 3 ч после подъёма питомца, вечер — 3 ч до отбоя хозяина
const AWAY_SHOW_H = 2;          // экран «Пока тебя не было» — после ≥ 2 ч (04 §6.4)
const AWAY_LONG_H = 24;         // от суток — welcome_long
const N_CARE_DAYS = 3;          // RESEARCH/07 #6: 3 дня без открытий — только «скучаю»
const N_MISS_EVERY_DAYS = 3;    // «скучаю» раз в 3 дня
const N_STOP_DAYS = 14;         // после 14 дней — тишина
const N_LEAD_MIN = 60;          // не звать раньше чем через час после «сейчас»: человек только что всё видел
const NEED_TRIGGER                                 = { food: 'hungry', clean: 'dirty', fun: 'bored', love: 'wants_love' };
const DISTRESS_TRIGGER                            = { starve: 'hungry', dirty: 'smelly', toska: 'unwell' };

const at = (s          , r       , o       , now         ) => (now !== undefined && now > s.t ? advance(s, r, o, now) : s);
const sleepingNow = (s          , r       , o       ) => petNight(s.t, r, o) || s.napUntil !== null;

// ---------- желания ----------

                                                                         

/** Желания для пузыря мысли: срочные (идёт беда) первыми, дальше по силе 0..1. Пусто — ничего не хочет. */
function wants(s0          , r       , o       , now         )         {
  const s = at(s0, r, o, now);
  if (!s.alive || s.outing != null) return []; // гуляет — дома просить нечего
  const bathing = s.bathUntil !== null, sleeping = sleepingNow(s, r, o);
  const tired = mods(s, r).refuses_games === true;
  const urgent = new Set         ();
  for (const d of DISTRESS) if (r.distress[d].cond(s.needs)) for (const k of WANT_DISTRESS[d]) urgent.add(k);
  const out                           = [];
  WANT_SPECS.forEach((w, i) => {
    if (bathing && (w.key === 'food' || w.key === 'bath' || w.key === 'play')) return;
    if (sleeping && (w.key === 'sleep' || w.key === 'play')) return;
    if (tired && w.key === 'play') return;
    const v = s.needs[w.need];
    if (v >= w.from) return;
    const strength = Math.min(1, w.w * (w.from - v) / w.from);
    out.push({ key: w.key, strength, urgent: urgent.has(w.key), i });
  });
  out.sort((a, b) => (a.urgent !== b.urgent ? (a.urgent ? -1 : 1) : b.strength !== a.strength ? b.strength - a.strength : a.i - b.i));
  return out.map(({ key, strength, urgent }) => ({ key, strength, urgent }));
}

// ---------- настроение ----------

/** Одно настроение для реплик виджета и острова. */
function mood(s0          , r       , o       , now         )       {
  const s = at(s0, r, o, now);
  if (!s.alive) return 'dead';
  if (s.outing != null) return 'walking';
  const lv = level(s, r);
  if (lv === 3) return 'critical';
  if (s.bathUntil !== null) return 'bath';
  if (petNight(s.t, r, o)) return 'sleep';
  if (s.napUntil !== null) return 'nap';
  for (const w of wants(s, r, o)) {
    const spec = WANT_SPECS.find(x => x.key === w.key) ;
    const v = s.needs[spec.need];
    if (spec.key === 'bath' && v < SMELLY_BELOW) return 'smelly';
    if (spec.moodKey !== null && v < spec.mood) return spec.moodKey;
  }
  if (lv === 2) return 'sulky';
  return 'ok';
}

/** Время суток для реплик: утро — 3 ч после подъёма питомца, вечер — 3 ч до отбоя, ночь — питомец спит. */
function daypart(t        , r       , o       )          {
  if (petNight(t, r, o)) return 'night';
  const m = localMin(t, o);
  const up = o.wakeMin + r.night.afterWakeMin;
  if (inWindow(m, up, up + PART_MIN)) return 'morning';
  if (inWindow(m, o.bedMin - PART_MIN, o.bedMin + r.night.afterBedMin)) return 'evening';
  return 'day';
}

// ---------- «Спасти» ----------

                                                                                                      
                                                                          

const NEED_ACTIONS                                  = {
  food: [{ type: 'feed', item: '' }], clean: [{ type: 'bath' }], fun: [{ type: 'play' }], love: [{ type: 'pet' }],
};
const DISTRESS_ACTIONS                             = {
  starve: [{ type: 'feed', item: '' }], dirty: [{ type: 'bath' }], toska: [{ type: 'play' }, { type: 'pet' }],
};

function actionKey(a        )                   {
  switch (a.type) {
    case 'feed': return 'food';
    case 'bath': return 'bath';
    case 'play': return 'play';
    case 'pet': return 'pet';
    default: return 'heal';
  }
}

/**
 * Одно самое срочное действие, которое ядро примет прямо сейчас (проверяется act на копии):
 * беда по скорости урона → шкалы ниже порога регенерации (или ниже warnLow при полных сердцах) в порядке wants →
 * в критичном состоянии лечебный предмет. null — делать нечего или ничего не поможет сейчас (ванна, ночь).
 * food/heal — какой корм и предмет предлагать (что есть в инвентаре — решает приложение).
 */
function rescue(s0          , r       , o       , opts             = {})                {
  const s = at(s0, r, o, opts.now);
  if (!s.alive || s.outing != null) return null; // гуляет: действия не принимаются, спасать некого
  const food = opts.food ?? 'kibble', heal = opts.heal ?? 'vitamin';
  const fill = (a        )         => (a.type === 'feed' ? { type: 'feed', item: food } : a);
  const tryAct = (a        ) => { const c = clone(s); return act(c, r, o, a).ok ? c : null; };

  const dist = DISTRESS.filter(d => r.distress[d].cond(s.needs))
    .map((d, i) => ({ d, i, h: r.distress[d].hoursPerHeart }))
    .sort((a, b) => (a.h !== b.h ? a.h - b.h : a.i - b.i));
  for (const { d } of dist) {
    let first                = null;
    for (const a0 of DISTRESS_ACTIONS[d]) {
      const a = fill(a0);
      const c = tryAct(a);
      if (!c) continue;
      if (first === null) first = a;
      if (a.type === 'bath' || !r.distress[d].cond(c.needs)) return { key: actionKey(a), action: a, because: d };
    }
    if (first !== null) return { key: actionKey(first), action: first, because: d };
  }

  const maxH = maxHearts(s, r);
  const bar = s.hearts < maxH ? r.hearts.regenAllGe : r.warnLow;
  for (const w of wants(s, r, o)) {
    const n = WANT_SPECS.find(x => x.key === w.key) .need;
    if (!WATCH.includes(n) || s.needs[n] >= bar) continue;
    for (const a0 of NEED_ACTIONS[n] ?? []) {
      const a = fill(a0);
      if (tryAct(a)) return { key: actionKey(a), action: a, because: n };
    }
  }

  if (level(s, r) === 3 && s.hearts < maxH) {
    const a         = { type: 'item', item: heal };
    if (tryAct(a)) return { key: 'heal', action: a, because: 'hearts' };
  }
  return null;
}

// ---------- «Пока тебя не было» ----------

                                                       
                                                                                                     
const WANT_CTA                           = { food: 'cta_hungry', bath: 'cta_dirty', play: 'cta_bored', pet: 'cta_love', sleep: 'cta_tired', walk: 'cta_ok' };
                                                                                                               
                                                                                                    
                              
               
             
                
                                                             
                                                                                                                       
                                                                                     
                                                                        
                     
                   
                                                                 
                                                                            
                
                                                                                   
 

/**
 * Пересчитать отсутствие от prev до now. journal — действия, сделанные без приложения
 * (кнопки виджета и острова, шаги): применяются в своё время, как в векторах (act в момент s.t после stepTo).
 */
function awaySummary(prev          , r       , o       , now        , journal             = [])              {
  const s = clone(prev);
  const ev              = [];
  let tr = tracker(s, r);
  let wasNight = petNight(s.t, r, o);
  let sleptMin = 0;
  const hc = () => Math.ceil(s.hearts - 1e-9);
  const run = (T        ) => {
    while (s.alive && s.t + STEP <= T) {
      const t0 = s.t, h0 = hc(), nap0 = s.napUntil;
      step(s, r, o);
      const night = petNight(t0, r, o);
      if (night !== wasNight) { ev.push({ t: t0, kind: night ? 'sleep' : 'wake' }); wasNight = night; }
      if (!night && s.napUntil !== null && s.napUntil !== nap0) ev.push({ t: s.t, kind: 'nap' });
      if (night || s.napUntil !== null) sleptMin++;
      if (hc() > h0) ev.push({ t: s.t, kind: 'heart_up', value: hc() });
      observe(tr, s, r, ev                              );
      if (!s.alive) ev.push({ t: s.diedAt ?? s.t, kind: 'death', key: s.cause ?? undefined });
    }
  };
  const acts = journal.map((a, i) => ({ a, i })).filter(x => x.a.t >= prev.t && x.a.t <= now)
    .sort((x, y) => (x.a.t !== y.a.t ? x.a.t - y.a.t : x.i - y.i));
  for (const { a } of acts) {
    run(a.t);
    if (!s.alive) break;
    const h0 = hc();
    const res = act(s, r, o, a.action);
    ev.push({ t: s.t, kind: 'act', key: a.action.type, ok: res.ok });
    if (hc() > h0) ev.push({ t: s.t, kind: 'heart_up', value: hc() });
    tr = tracker(s, r);
  }
  run(now);
  const needs = {}                        ;
  for (const n of NEEDS) needs[n] = s.needs[n] - prev.needs[n];
  const awayH = (now - prev.t) / 3600;
  const died = prev.alive && !s.alive;
  const show = awayH >= AWAY_SHOW_H;
  const live = show && s.alive;
  const top = live ? wants(s, r, o)[0] : undefined;
  return {
    from: prev.t, to: now, awayH, show, greet: live ? (awayH >= AWAY_LONG_H ? 'welcome_long' : 'welcome') : null,
    cta: live ? (top ? WANT_CTA[top.key] : 'cta_ok') : null,
    sleptH: sleptMin / 60, heartsFrom: prev.hearts, heartsTo: s.hearts, needs,
    events: ev.filter(e => (e.kind          ) !== 'level'), died, state: s,
  };
}

// ---------- план уведомлений ----------

                             
                                                                                                        
                                                                                            
                                                                                                     
                                                                                                
                      
 
                                                                                                                                                            

const localDay = (t        , o       ) => Math.floor((Math.floor(t / 60) + o.tzOffsetMin) / 1440);

/**
 * Локальные уведомления по прогнозу без ухода (RESEARCH/07 #6):
 * не больше 1 в местный день (самое серьёзное, при равенстве — раньшее), тихие часы переносят на их конец;
 * первые 3 дня после открытия — по событиям прогноза, с 3-го по 14-й — только «скучаю» раз в 3 дня, дальше тишина.
 * После смерти по прогнозу не зовём.
 */
function notificationPlan(s0          , r       , o       , now        , opts             = {})                        {
  const s = at(s0, r, o, now);
  if (!s.alive) return [];
  const horizonH = opts.horizonH ?? 72;
  const lastOpen = opts.lastOpenT ?? now;
  const qFrom = opts.quietFromMin ?? o.bedMin, qTo = opts.quietToMin ?? o.wakeMin;
  const end = now + horizonH * 3600;
  const careUntil = lastOpen + N_CARE_DAYS * 86400, stopAt = lastOpen + N_STOP_DAYS * 86400;
  const quiet = (t        ) => {
    const m = localMin(t, o);
    return inWindow(m, qFrom, qTo) ? t + ((((qTo - m) % 1440) + 1440) % 1440) * 60 : t;
  };
  const ev = forecast(s, r, o, horizonH);
  const death = ev.find(e => e.kind === 'death');
  const deathT = death ? death.t : Infinity;
  const cands                                            = [];
  for (const e of ev) {
    let trigger                     , sev = 0;
    if (e.kind === 'low') { trigger = NEED_TRIGGER[e.key        ]; sev = 1; }
    else if (e.kind === 'distress') { trigger = DISTRESS_TRIGGER[e.key            ]; sev = 2; }
    else if (e.kind === 'heart') { trigger = 'heart_lost'; sev = 2; }
    else if (e.kind === 'level' && e.value === 3) { trigger = 'critical'; sev = 3; }
    else if (e.kind === 'last_chance') { trigger = 'last_chance'; sev = 4; }
    if (trigger === undefined) continue;
    const t = quiet(e.t);
    if (t >= careUntil) continue;
    const c                                        = { at: t, trigger, kind: e.kind                               , sev };
    if (e.key !== undefined) c.key = e.key;
    cands.push(c);
  }
  for (let k = 1; lastOpen + k * N_MISS_EVERY_DAYS * 86400 < stopAt; k++) {
    const t = quiet(lastOpen + k * N_MISS_EVERY_DAYS * 86400);
    if (t < stopAt) cands.push({ at: t, trigger: 'miss_you', kind: 'absent', sev: 0 });
  }
  const sentDay = opts.lastSentT !== undefined && opts.lastSentT !== null ? localDay(opts.lastSentT, o) : null;
  const ok = cands.filter(c => c.at >= now + N_LEAD_MIN * 60 && c.at <= end && c.at < deathT && localDay(c.at, o) !== sentDay)
    .map((c, i) => ({ c, i }))
    .sort((a, b) => (a.c.at !== b.c.at ? a.c.at - b.c.at : a.i - b.i));
  const byDay = new Map                                               ();
  for (const { c } of ok) {
    const d = localDay(c.at, o);
    const cur = byDay.get(d);
    if (cur === undefined || c.sev > cur.sev) byDay.set(d, c);
  }
  return [...byDay.values()].sort((a, b) => a.at - b.at).map(({ sev, ...p }) => p);
}

g.PetCore = { NEEDS, DISTRESS, HOME_LINES, compileCond, makeRules, presetNames, withPreset, defaultOwner, newPet, clone, localMin, ownerAsleep, petNight, mods, maxHearts, stepTo, advance, act, level, moods, forecast, WANT_SPECS, wants, mood, daypart, rescue, awaySummary, notificationPlan };
})(typeof window !== 'undefined' ? window : globalThis);
