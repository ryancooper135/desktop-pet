// Правила из config/economy.json в удобном для движка виде.
// Условия вида "food < 20" и "fun < 10 && love < 10" компилируются один раз.

export const NEEDS = ['food', 'clean', 'energy', 'fun', 'love', 'walk', 'look'] as const;
export type Need = typeof NEEDS[number];
export const DISTRESS = ['starve', 'dirty', 'toska'] as const;
export type Distress = typeof DISTRESS[number];
export const HOME_LINES = ['bath', 'bed', 'kitchen', 'kennel', 'play', 'yard'] as const;
export type HomeLine = typeof HOME_LINES[number];

export type Vals = Record<Need, number>;
export type Cond = (v: Vals) => boolean;
export type Effect = Record<string, number | boolean>;

export interface Rules {
  needs: Record<Need, any>;
  cross: { cond: Cond; then: Effect }[];
  distress: Record<Distress, { cond: Cond; graceH: number; hoursPerHeart: number }>;
  hearts: { max: number; regenPerH: number; regenNightX: number; regenAllGe: number; lastChanceH: number; noDeathAfterWakeH: number };
  night: { bedMin: number; wakeMin: number; afterBedMin: number; afterWakeMin: number };
  bathMinutes: number[];
  petLove: number;
  petCooldownMin: number;
  play: { funGain: number; energyCost: number };
  food: Record<string, Effect>;
  items: Record<string, Effect>;
  home: Record<HomeLine, Effect[]>;
  warnLow: number;
}

const COND_PART = /^\s*(\w+)\s*(<=|>=|==|<|>)\s*(-?\d+(?:\.\d+)?)\s*$/;

export function compileCond(expr: string): Cond {
  const parts = expr.split('&&').map(p => {
    const m = COND_PART.exec(p);
    if (!m || !(NEEDS as readonly string[]).includes(m[1])) throw new Error(`условие не разобрано: ${expr}`);
    const need = m[1] as Need, op = m[2], x = Number(m[3]);
    switch (op) {
      case '<': return (v: Vals) => v[need] < x;
      case '<=': return (v: Vals) => v[need] <= x;
      case '>': return (v: Vals) => v[need] > x;
      case '>=': return (v: Vals) => v[need] >= x;
      default: return (v: Vals) => v[need] === x;
    }
  });
  return v => parts.every(f => f(v));
}

function hhmm(s: string): number {
  const [h, m] = s.split(':').map(Number);
  return h * 60 + m;
}

function numbers(o: any): Effect {
  const out: Effect = {};
  for (const [k, v] of Object.entries(o ?? {})) if (!k.startsWith('_') && (typeof v === 'number' || typeof v === 'boolean')) out[k] = v;
  return out;
}

export function makeRules(cfg: any): Rules {
  const care = cfg.care, h = care.hearts;
  const distress = {} as Rules['distress'];
  for (const d of DISTRESS) {
    const x = h.distress[d];
    distress[d] = { cond: compileCond(x.when), graceH: x.grace_h_awake, hoursPerHeart: x.hours_per_heart };
  }
  const food: Record<string, Effect> = {};
  for (const f of cfg.shop.food) food[f.id] = numbers(f);
  const items: Record<string, Effect> = {};
  for (const c of cfg.shop.consumables) items[c.id] = numbers(c);
  const home = {} as Rules['home'];
  for (const line of HOME_LINES) home[line] = cfg.home_upgrades[line].levels.map((l: any) => numbers(l.buff));
  return {
    needs: care.needs,
    cross: care.cross_effects.map((c: any) => ({ cond: compileCond(c.if), then: numbers(c.then) })),
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
