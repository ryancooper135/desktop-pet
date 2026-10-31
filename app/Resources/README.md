# Resources

Ресурсы приложения (таргет Pet). Всё, кроме `*.md`, попадает в бандл.

- `Pets/shiba.usdz`, `Pets/husky.usdz` — модели пса (Quaternius, CC0), порода выбирается в «Персонажах» (`PetBreed`, волна 58).
  Ищутся как `Bundle.main.url(forResource: PetBreed.resource, withExtension: "usdz")`; старые сейвы — Шиба.
  - Нет файла — на сцене заглушка из коробок (App/PetStage.swift, `StubDog`).
  - Масштаб и позиция подгоняются сами: рост 0.42 по `visualBounds`, ноги на полу, центр по x и z.
  - Собирает `gh workflow run assets.yml -f commit=true` (матрица shiba/husky) или локально Blender 5.2 + `tools/assets/build_clips.py`; в бандле папки сплющиваются.
  - `<порода>.clips.json` — границы 39 клипов на одной анимации «Clips» (24 fps, у обеих пород одни имена). По нему PetStage режет анимацию: поза → клип (`PetStage.clip(for:)`). Нет таблицы — вся анимация по кругу.
  - Морда смотрит на +z (к камере). Бюджет — ≤ 10 000 треугольников и ~2 МБ на породу (тест `PetBreedTests`).
- `Pets/bowl.usdz`, `Pets/ball.usdz` — миска «Dog bowl» и мячик «Tennis ball» (Poly by Google, CC-BY 3.0; автор назван в «Об игре»).
  Собирает `python -P tools/assets/props_usdz.py` из `tools/assets/source/props`; грузит `App/PetProps.swift`, нет файла — прежние примитивы. Бюджет ≤ 2000 треугольников и ≤ 300 КБ.
- `Room/plant.usdz`, `Room/books.usdz`, `Room/bear.usdz` — цветок, книжки и мишка на полке комнаты (Kenney Furniture Kit, CC0, волна 53).
  Собирает `python -P tools/assets/furniture_usdz.py <glb> <usdz> --height … --color …`; грузит `App/PetProps.swift`, нет файла — полки без них.
- `Room/floor_herringbone.jpg` — пастельный паркет ёлочкой (ambientCG WoodFloor036, CC0), `tools/assets/floor_pastel.py`; нет файла — клетка.
- `economy.json` и `lines.json` сюда не копировать: project.yml берёт их из `../config` и `../content/ru`.
- `Music/music_home.m4a`, `Music/music_play.m4a` — тихие лупы музыки (волна 49, MusicTheme/SoundKit), ищутся как `Bundle.main.url(forResource: "music_home", withExtension: "m4a")`. Лицензии — `content/ASSETS_LICENSES.md`.
