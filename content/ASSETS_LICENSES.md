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
