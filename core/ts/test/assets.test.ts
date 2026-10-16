// Ассеты и тексты без Мака: таблица клипов Шибы, список обязательных клипов в коде, длины реплик.
// Файла нет — тест пропускается (t.skip), а не падает. Запуск: node --test "core/ts/test/*.test.ts"
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('../../../', import.meta.url));
const CLIPS = join(ROOT, 'app/Resources/Pets/shiba.clips.json');
const PET_CLIPS_SWIFT = join(ROOT, 'app/App/PetClips.swift');
const LINES_SWIFT = join(ROOT, 'app/Shared/Lines.swift');
const CONTENT = join(ROOT, 'content');

// 21 клип, на которых держится сцена (tools/assets/poses.json + клипы Quaternius). Убрал клип — поправь и здесь.
const REQUIRED = [
  'idle', 'idle_2', 'idle_headlow', 'walk', 'gallop', 'gallop_jump', 'jump_to_idle', 'eat', 'attack',
  'hit_left', 'hit_right', 'death', 'sit_in', 'sit', 'sit_out', 'lie_in', 'lie', 'lie_out',
  'sleep_in', 'sleep', 'sleep_out',
];

type Clip = { start: number; end: number; frames?: number[]; loop?: boolean };
const readJSON = (p: string) => JSON.parse(readFileSync(p, 'utf8'));

test('clips.json: fps 24, у каждого клипа start < end, обязательные на месте', (t) => {
  if (!existsSync(CLIPS)) return t.skip('нет app/Resources/Pets/shiba.clips.json');
  const j = readJSON(CLIPS);
  assert.equal(j.fps, 24, 'fps');
  const clips: Record<string, Clip> = j.clips ?? {};
  assert.ok(Object.keys(clips).length >= REQUIRED.length, `клипов ${Object.keys(clips).length}`);
  for (const [name, c] of Object.entries(clips)) {
    assert.ok(Number.isFinite(c.start) && Number.isFinite(c.end), `${name}: start/end не числа`);
    assert.ok(c.start >= 0, `${name}: start < 0`);
    assert.ok(c.start < c.end, `${name}: start ${c.start} >= end ${c.end}`);
    if (Number.isFinite(j.duration)) assert.ok(c.end <= j.duration + 1e-6, `${name}: end ${c.end} за концом таймлайна ${j.duration}`);
    if (Array.isArray(c.frames) && c.frames.length === 2) {
      assert.ok(c.frames[0] < c.frames[1], `${name}: кадры ${c.frames}`);
      // Кадры и секунды — одно и то же при 24 fps (округление до кадра).
      assert.ok(Math.abs(c.frames[0] / j.fps - c.start) < 1 / j.fps, `${name}: start не совпадает с кадром`);
    }
  }
  const missing = REQUIRED.filter(n => !(n in clips));
  assert.deepEqual(missing, [], `нет клипов: ${missing.join(', ')}`);
});

test('clips.json: клипы не налезают друг на друга', (t) => {
  if (!existsSync(CLIPS)) return t.skip('нет app/Resources/Pets/shiba.clips.json');
  const clips: [string, Clip][] = Object.entries(readJSON(CLIPS).clips ?? {});
  clips.sort((a, b) => a[1].start - b[1].start);
  for (let i = 1; i < clips.length; i++) {
    const [pn, p] = clips[i - 1], [n, c] = clips[i];
    assert.ok(c.start >= p.end - 1e-6, `${n} начинается внутри ${pn}`);
  }
});

test('PetClips.swift: все клипы из required есть в clips.json', (t) => {
  if (!existsSync(PET_CLIPS_SWIFT)) return t.skip('нет app/App/PetClips.swift');
  if (!existsSync(CLIPS)) return t.skip('нет app/Resources/Pets/shiba.clips.json');
  const src = readFileSync(PET_CLIPS_SWIFT, 'utf8');
  // static let required: [String] = [ "idle", ... ]  /  let required = Set([...])
  const m = src.match(/\brequired\b[^=\n]*=\s*(?:Set\s*\(\s*)?\[([\s\S]*?)\]/);
  if (!m) return t.skip('в PetClips.swift нет списка required');
  const names = [...m[1].matchAll(/"([^"\\]+)"/g)].map(x => x[1]);
  assert.ok(names.length > 0, 'required пуст');
  const clips = readJSON(CLIPS).clips ?? {};
  const missing = names.filter(n => !(n in clips));
  assert.deepEqual(missing, [], `PetClips.required ждёт клипы, которых нет в clips.json: ${missing.join(', ')}`);
});

// Лимиты — из LineLimit в app/Shared/Lines.swift (если файл есть), иначе как в content/README.md.
function lineLimits(): Record<string, number> {
  const lim: Record<string, number> = { widget: 40, island: 20, thought: 24, away: 70, notifTitle: 30, notifBody: 90 };
  if (existsSync(LINES_SWIFT)) {
    const src = readFileSync(LINES_SWIFT, 'utf8');
    const block = src.match(/enum\s+LineLimit\s*\{([\s\S]*?)\}/);
    if (block) for (const x of block[1].matchAll(/static\s+let\s+(\w+)\s*=\s*(\d+)/g)) lim[x[1]] = Number(x[2]);
  }
  return lim;
}

function jsonFiles(dir: string): string[] {
  const out: string[] = [];
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) out.push(...jsonFiles(p));
    else if (name.endsWith('.json')) out.push(p);
  }
  return out;
}

// Длина как у Swift String.count (графемы); кодовые точки не меньше графем, поэтому проверка не мягче.
const len = (s: string) => [...s].length;

test('content/**: реплики не длиннее LineLimit', (t) => {
  if (!existsSync(CONTENT)) return t.skip('нет content/');
  const files = jsonFiles(CONTENT).filter(p => {
    const j = readJSON(p);
    return j && typeof j === 'object' && ('widget' in j || 'notifications' in j || 'island' in j);
  });
  if (files.length === 0) return t.skip('в content/ нет файлов реплик');
  const lim = lineLimits();
  const over: string[] = [];
  let checked = 0;
  const check = (where: string, s: unknown, max: number) => {
    if (typeof s !== 'string') return;
    checked++;
    if (len(s) > max) over.push(`${where}: ${len(s)} > ${max} «${s}»`);
  };
  for (const p of files) {
    const j = readJSON(p);
    const rel = p.slice(ROOT.length);
    for (const [sec, max] of [['widget', lim.widget], ['island', lim.island], ['away', lim.away]] as const) {
      for (const [key, arr] of Object.entries<any[]>(j[sec] ?? {})) {
        for (const it of arr ?? []) check(`${rel} ${sec}.${key} ${it.id ?? ''}`, it.text, max);
      }
    }
    for (const [key, arr] of Object.entries<any[]>(j.notifications ?? {})) {
      for (const it of arr ?? []) {
        check(`${rel} notifications.${key} ${it.id ?? ''} title`, it.title, lim.notifTitle);
        check(`${rel} notifications.${key} ${it.id ?? ''} body`, it.body ?? it.text, lim.notifBody);
      }
    }
    for (const [key, it] of Object.entries<any>(j.thoughts ?? {})) check(`${rel} thoughts.${key}`, it?.text, lim.thought);
  }
  assert.ok(checked > 0, 'ни одной реплики не проверено');
  assert.deepEqual(over, [], `длинные реплики:\n${over.join('\n')}`);
});
