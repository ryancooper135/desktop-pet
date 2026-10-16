// Сгенерировано core/ts/tools/bundle-web.ts из core/ts/src. Руками не править.
(function (g) {
'use strict';
// Правила из config/economy.json в удобном для движка виде.
// Условия вида "food < 20" и "fun < 10 && love < 10" компилируются один раз.

const NEEDS = ['food', 'clean', 'energy', 'fun', 'love', 'walk', 'look']         ;
                                        
const DISTRESS = ['starve', 'dirty', 'toska']         ;
                                               
const HOME_LINES = ['bath', 'bed', 'kitchen', 'kennel', 'play', 'yard']         ;
                                                 

                                        
                                        
                                                      

                        
                           
                                        
                                                                                    
                                                                                                                                      
                                                                                        
                        
                  
                         
                                                
                               
                                
                                   
                  
 

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

function makeRules(cfg     )        {
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
    warnLow: 30,
  };
}

// Ядро питомца: состояние считается от времени (ленивый пересчёт), а не тикает в фоне.
// Шаг — ровно 1 минута, состояние двигается только целыми минутами, поэтому
// «посчитать сразу до T» и «посчитать по кускам до T» дают одно и то же.
// Порядок операций с плавающей точкой должен совпадать со Swift-версией (core/swift):
// общие тест-векторы в core/vectors сверяют обе.

const STEP = 60;
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
    home, alive: true, diedAt: null, cause: null,
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

function step(s          , r       , o       ) {
  const t = s.t;
  if (s.napUntil !== null && t >= s.napUntil) s.napUntil = null;
  if (s.bathUntil !== null && t >= s.bathUntil) finishBath(s, r);

  const asleep = ownerAsleep(t, o);
  const night = petNight(t, r, o);
  if (!night && petNight(t - STEP, r, o)) {
    s.needs.love = clamp(s.needs.love + num(homeBuff(s, r, 'bed'), 'love_on_wake'));
  }
  const en = r.needs.energy;
  if (!night && s.napUntil === null && s.bathUntil === null && s.needs.energy < en.nap_below) {
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
    s.needs[n] = clamp(s.needs[n] - rate * k * DH);
  }
  if (night) s.needs.energy = clamp(s.needs.energy + en.night_regen_per_h * x(md, 'night_energy_regen_x') * x(md, 'sleep_regen_x') * DH);
  else if (s.napUntil !== null) s.needs.energy = clamp(s.needs.energy + en.nap_regen_per_h * DH);
  else s.needs.energy = clamp(s.needs.energy - en.day_per_h * x(md, 'energy_decay_x') * DH);
  s.needs.look = clamp(s.needs.look - r.needs.look.per_day / 24 * DH);

  // сердца: урон и «льготы» копятся только в бодрые часы хозяина
  const h = r.hearts;
  let dmg = 0;
  let anyActive = false;
  DISTRESS.forEach((d, i) => {
    if (!active[i]) { s.grace[d] = 0; return; }
    anyActive = true;
    if (asleep) return;
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
    if (!asleep && anyActive) {
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
      if (a.type === 'feed') s.napUntil = null;
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

                                
            
                                                                         
               
                 
 

/** Что случится, если никто не придёт: для локальных уведомлений и «умрёт в чт ~15:00». */
function forecast(s0          , r       , o       , horizonH = 72)                  {
  const s = clone(s0);
  const end = s.t + horizonH * 3600;
  const ev                  = [];
  const low = new Set(WATCH.filter(n => s.needs[n] < r.warnLow));
  const dist = new Set(DISTRESS.filter(d => r.distress[d].cond(s.needs)));
  let lvl = level(s, r);
  let hc = Math.ceil(s.hearts - 1e-9);
  let lc = s.lastChanceH !== null;
  while (s.alive && s.t + STEP <= end) {
    step(s, r, o);
    for (const n of WATCH) if (s.needs[n] < r.warnLow && !low.has(n)) { low.add(n); ev.push({ t: s.t, kind: 'low', key: n }); }
    for (const d of DISTRESS) {
      const on = r.distress[d].cond(s.needs);
      if (on && !dist.has(d)) { dist.add(d); ev.push({ t: s.t, kind: 'distress', key: d }); }
      if (!on) dist.delete(d);
    }
    const c = Math.ceil(s.hearts - 1e-9);
    if (c < hc) ev.push({ t: s.t, kind: 'heart', value: c });
    hc = c;
    if (s.lastChanceH !== null && !lc) ev.push({ t: s.t, kind: 'last_chance' });
    lc = s.lastChanceH !== null;
    const l = level(s, r);
    if (l !== lvl) { ev.push({ t: s.t, kind: 'level', value: l }); lvl = l; }
  }
  if (!s.alive) ev.push({ t: s.diedAt , kind: 'death', key: s.cause ?? undefined });
  return ev;
}

g.PetCore = { NEEDS, DISTRESS, HOME_LINES, compileCond, makeRules, defaultOwner, newPet, clone, localMin, ownerAsleep, petNight, mods, maxHearts, stepTo, advance, act, level, moods, forecast };
})(typeof window !== 'undefined' ? window : globalThis);
