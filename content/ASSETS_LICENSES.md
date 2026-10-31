# Лицензии сторонних ассетов

Всё стороннее, что попадает в приложение. Только открытые лицензии: CC0 — без условий;
CC-BY — обязательно указать автора в «Настройках» и здесь. Проверяет `PrefsTests.testMusicFilesBundledSmallAndLicensed`.

## Музыка (волна 49)

| Файл в `app/Resources/Music/` | Трек | Автор | Источник | Лицензия |
|---|---|---|---|---|
| `music_home.m4a` | «Chill (Loopable)» | Pro Sensory (Alex McCulloch) | https://opengameart.org/content/chill-loopable | CC0 1.0 |
| `music_play.m4a` | «Lofi Hip Hop Loop» | omfgdude | https://opengameart.org/content/lofi-hip-hop-loop | CC0 1.0 |

- CC0 атрибуции не требует, но автор «Chill (Loopable)» просит указать его — указан в подписи раздела
  «Звук и отклик» в настройках: «Музыка: Alex McCulloch (Pro Sensory), omfgdude — CC0».
- Перекодировано ffmpeg из оригиналов (`C:\Users\ryanc\pet-assets\music\…`, в репо не лежат):
  `music_home` — моно, срез выше 11 кГц, −4,8 дБ, 32 кГц, AAC 56 кбит/с (67 с, петля);
  `music_play` — 22,05 кГц, AAC 48 кбит/с (128 с, петля). Вместе ≈1,3 МБ (лимит 1,5 МБ).

### Запасные варианты (скачаны, не в приложении — на выбор Вадиму)

- «Chill lofi inspired» — omfgdude, CC0: https://opengameart.org/content/chill-lofi-inspired
- «Lofi again» — omfgdude, CC0: https://opengameart.org/content/lofi-again

Звуковые эффекты не сторонние: их синтезирует само приложение (`app/Shared/SoundRecipes.swift`).

## 3D-модели (волна 58)

| Файл в `app/Resources/Pets/` | Модель | Автор | Источник | Лицензия |
|---|---|---|---|---|
| `shiba.usdz` | «Shiba Inu» | Quaternius | https://poly.pizza/m/y4wdQpg767 | CC0 1.0 |
| `husky.usdz` | «Husky» | Quaternius | https://poly.pizza/m/wcWiuEqwzq | CC0 1.0 |
| `bowl.usdz` | «Dog bowl» | Poly by Google | https://poly.pizza/m/a3frygyTZwp | CC-BY 3.0 |
| `ball.usdz` | «Tennis ball» | Poly by Google | https://poly.pizza/m/0aPpwgcBbk1 | CC-BY 3.0 |

- CC-BY 3.0 (миска, мячик): автор указан в настройках, раздел «Об игре» — «Миска «Dog bowl» и мячик
  «Tennis ball» — Poly by Google (CC-BY 3.0)». Изменения: размер под комнату, миска матовая графитовая
  (оригинал чистый чёрный), формат glb → usdz (`tools/assets/props_usdz.py`). Исходники — `tools/assets/source/props/`.
- Шиба и Хаски: позы, новые клипы и окрас стиля A — наши (`tools/assets/build_clips.py`, `poses.json`,
  `style_a*.json`); исходники glb — `tools/assets/source/`. CC0 атрибуции не требует, но автор назван там же.
- Проверяет `PetBreedTests.testAssetCreditsListed`.

## Виджет, островок и контрол «что сейчас» (волна 51)

Сторонних файлов **нет**. Пёс в позах занятия — свой `PixelDog`/3D из кода (бег, сон, тазик с пеной уже были),
значки — системные SF Symbols (`moon.zzz.fill`, `bubbles.and.sparkles.fill`, `figure.walk` и др.), макеты
`design/wave51/` — свой SVG-пёс в `dog.js`. Ничего не скачано.

Смотрели готовое (не взято, на будущее):

- «Dog Spritesheets» — Jason of GDN, CC0: https://opengameart.org/content/dog-spritesheets — бег/шаг/стойка
  в 3 окрасах, но нет сна и купания, стиль чужой.
- «Dog» — rmazanek, CC0: https://opengameart.org (поиск «rmazanek dog») — бег и сидит, нет сна, кадры 60×38.
- «Emotes Pack» — Kenney, CC0: https://opengameart.org/content/emotes-pack — пузыри-эмоции; zzz и пена уже
  есть в SF Symbols.
- pawello2222/WidgetExamples — MIT: https://github.com/pawello2222/WidgetExamples — образец кода Live
  Activity и таймеров, код не брали.
- «Pixel Dogs» (Benvictus, itch.io) — есть сон, но лицензия неясна, отброшен.

## «Команды» — дрессировка (волна 57)

Сторонних файлов **нет**. Иконки 8 команд и значки причин «недоступно» — системные SF Symbols
(`dog.fill`, `pawprint.fill`, `bed.double.fill`, `speaker.wave.2.fill`, `arrow.trianglehead.2.clockwise.rotate.90`,
`hand.raised.fill`, `powersleep`, `tortoise.fill`; причины — `moon.zzz.fill`, `bubbles.and.sparkles.fill`,
`figure.walk` и др.), как рекомендовала волна 52. Анимации — клипы волны 58 (`sit*`, `paw`, `lie*`, `bark`,
`spin`, `high_five`, `death` + `play_dead_out`, `crawl`), новых клипов не делали. Макеты `design/wave57/` —
свои SVG-иконки в `icons57.js` (только для макетов, в приложение не идут). Ничего не скачано.

Смотрели готовое (не взято, на будущее):

- Phosphor Icons — MIT: https://phosphoricons.com (https://github.com/phosphor-icons/core) — есть `dog`,
  `paw-print`, `hand-palm`, `arrows-clockwise`; SF Symbols закрывают все 8 команд, лишний шрифт не нужен.
- Tabler Icons — MIT: https://tabler.io/icons — `paw`, `dog`, `hand-stop`, `rotate-clockwise`; тот же довод.
- «Dog Training Icons» на Flaticon / Noun Project — лицензия с обязательной атрибуцией на каждом экране или
  платная, стиль чужой; отброшены.
