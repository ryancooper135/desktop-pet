# Resources

Ресурсы приложения (таргет Pet). Всё, кроме `*.md`, попадает в бандл.

- `shiba.usdz` — модель Шибы для главного экрана. Ищется как `Bundle.main.url(forResource: "shiba", withExtension: "usdz")`.
  - Нет файла — на сцене заглушка из коробок (App/PetStage.swift, `StubDog`).
  - Масштаб и позиция подгоняются сами: рост 0.42 по `visualBounds`, ноги на полу, центр по x и z.
  - Первая анимация из `availableAnimations` играет в цикле. Позы по анимациям — позже.
  - Морда смотрит на +z (к камере).
- `economy.json` и `lines.json` сюда не копировать: project.yml берёт их из `../config` и `../content/ru`.
