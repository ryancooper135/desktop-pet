# Страницы-прототипы

Исходники опубликованных страниц (артефакты claude.ai, приватные, открываются под аккаунтом Вадима).

| Папка | Что | Ссылка |
|---|---|---|
| `screens/` | Макеты экранов, виджетов, острова + механика одной страницей | https://claude.ai/artifact/75FSkjVK8s1F4RC2xD4SA3 |
| `sandbox/` | Песочница ядра: Шиба на iPhone Air, перемотка времени, прогноз на 72 ч | https://claude.ai/artifact/PHVFdeynbhfsarPcoKde7B |
| `../moodboard/page/` | Мудборд стиля (выбран A, Шиба) | см. PROGRESS 16.10 |

Рядом со страницей при публикации лежат файлы, которых нет в этой папке:
- `sandbox/`: `petcore.js` ← `core/web/petcore.js`, `economy.json` ← `config/economy.json`, `shiba.json` — модель Quaternius (CC0), переделанная из .glb в .gltf JSON с base64 (так модель проходит CSP артефакта, см. PROGRESS 16.10).
- `screens/`: `mechanics.md` ← `RESEARCH/mechanics-onepager.md`, модели `shiba.json`, `husky.json`, `cat.json` в том же формате.

three.js 0.147.0 и marked 4.3.0 грузятся с jsDelivr.
