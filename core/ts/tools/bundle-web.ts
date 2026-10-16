// Собирает ядро в один файл для браузера: core/web/petcore.js с глобальным PetCore.
// Типы снимает сам Node (stripTypeScriptTypes), код движка не переписывается руками,
// поэтому песочница считает ровно то же, что тесты и Swift.
// Запуск из корня репо: node core/ts/tools/bundle-web.ts

import { stripTypeScriptTypes } from 'node:module';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';

const src = (f: string) => {
  const js = stripTypeScriptTypes(readFileSync(`core/ts/src/${f}`, 'utf8'));
  return js
    .replace(/^\s*import\s[^;]*;\s*$/gm, '')
    .replace(/^export\s+(?=(const|function|interface|type)\b)/gm, '');
};

const names = [
  'NEEDS', 'DISTRESS', 'HOME_LINES', 'compileCond', 'makeRules', 'presetNames', 'withPreset',
  'defaultOwner', 'newPet', 'clone', 'localMin', 'ownerAsleep', 'petNight', 'mods', 'maxHearts',
  'stepTo', 'advance', 'act', 'level', 'moods', 'forecast',
  'WANT_SPECS', 'wants', 'mood', 'daypart', 'rescue', 'awaySummary', 'notificationPlan',
];

const out = `// Сгенерировано core/ts/tools/bundle-web.ts из core/ts/src. Руками не править.
(function (g) {
'use strict';
${src('rules.ts')}
${src('engine.ts')}
${src('insights.ts')}
g.PetCore = { ${names.join(', ')} };
})(typeof window !== 'undefined' ? window : globalThis);
`;

mkdirSync('core/web', { recursive: true });
writeFileSync('core/web/petcore.js', out);
console.log(`core/web/petcore.js: ${out.length} байт`);
