// Встраивает в index.html нужные песочнице строки из content/ru/lines.json (артефакт без fetch).
// Запуск из корня репо: node RESEARCH/mockups/sandbox/embed-lines.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..', '..');
const src = JSON.parse(readFileSync(join(root, 'content', 'ru', 'lines.json'), 'utf8'));

// Ключи, которые выдаёт core/ts/src/insights.ts (mood, wants, notificationPlan, awaySummary).
const MOODS = ['ok', 'morning', 'evening', 'dead', 'critical', 'bath', 'sleep', 'nap', 'hungry', 'smelly', 'dirty', 'tired', 'bored', 'wants_love', 'wants_walk', 'sulky'];
const TRIGGERS = ['hungry', 'dirty', 'smelly', 'bored', 'wants_love', 'unwell', 'heart_lost', 'critical', 'last_chance', 'miss_you'];
const WANTS = ['food', 'bath', 'sleep', 'play', 'pet', 'walk'];
const AWAY = ['welcome', 'welcome_long', 'slept', 'nap', 'missed', 'heart_lost', 'nothing', 'cta_hungry', 'cta_dirty', 'cta_bored', 'cta_love', 'cta_tired', 'cta_ok'];

const take = (sec, keys) => Object.fromEntries(keys.filter(k => src[sec] && src[sec][k]).map(k => [k, src[sec][k]]));
const out = {
  widget: take('widget', MOODS),
  island: take('island', MOODS),
  thoughts: take('thoughts', WANTS),
  notifications: take('notifications', TRIGGERS),
  away: take('away', AWAY),
};
const json = JSON.stringify(out).replace(/</g, '\\u003c');

const file = join(here, 'index.html');
const html = readFileSync(file, 'utf8');
const re = /(<script type="application\/json" id="lines">)[\s\S]*?(<\/script>)/;
if (!re.test(html)) throw new Error('нет блока <script id="lines"> в index.html');
writeFileSync(file, html.replace(re, (_, a, b) => a + json + b));
console.log('lines встроены:', json.length, 'символов');
