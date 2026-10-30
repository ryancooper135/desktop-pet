# Resources

Ресурсы приложения (таргет Pet). Всё, кроме `*.md`, попадает в бандл.

- `shiba.usdz` — модель Шибы для главного экрана. Ищется как `Bundle.main.url(forResource: "shiba", withExtension: "usdz")`.
  - Нет файла — на сцене заглушка из коробок (App/PetStage.swift, `StubDog`).
  - Масштаб и позиция подгоняются сами: рост 0.42 по `visualBounds`, ноги на полу, центр по x и z.
  - Лежит в `Pets/` (кладёт `gh workflow run assets.yml -f commit=true`); в бандле папки сплющиваются.
  - `shiba.clips.json` — границы 21 клипа на одной анимации «Clips». По нему PetStage режет анимацию: поза → клип (`PetStage.clip(for:)`). Нет таблицы — вся анимация по кругу.
  - Морда смотрит на +z (к камере).
- `economy.json` и `lines.json` сюда не копировать: project.yml берёт их из `../config` и `../content/ru`.
- `Music/music_home.m4a`, `Music/music_play.m4a` — тихие лупы музыки (волна 49, MusicTheme/SoundKit), ищутся как `Bundle.main.url(forResource: "music_home", withExtension: "m4a")`. Лицензии — `content/ASSETS_LICENSES.md`.
