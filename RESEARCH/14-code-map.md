# 14. Карта кода

Волна 28, 20.10.2026. Где что лежит, чтобы новая волна начинала не с поиска. Каждый .swift начинается с
комментария «что это и зачем»; здесь только сводка по папкам и связям. Числа строк — на момент волны 28.

## Слои

```
core/            ядро: правила и движок питомца, одна логика на Swift и TS (векторы сверяют обе)
  swift/         пакет PetCore: Engine (advance, apply), Rules (economy.json), Insights, JSONValue
  ts/            та же логика на TS + сценарии; web/petcore.js — сборка для песочницы
  vectors/       общие тест-векторы ядра (гоняют core.yml и PetTests)
config/economy.json   все числа экономики и правил (бандлится в приложение и виджеты)
content/ru/lines.json реплики (правила выбора — content/README.md)
app/             приложение iOS 26, XcodeGen (app/project.yml), Swift 6
  Shared/        логика без UI + общие вьюшки (Shared/Views). Входит и в приложение, и в виджеты
  App/           только приложение: экраны SwiftUI, 3D-сцена RealityKit, модель экрана
  Widgets/       расширение PetWidgets: виджет, Live Activity, контролы Пункта управления
  Tests/         юнит-тесты (PetTests): XCTest на симуляторе, большая часть ещё и на Linux
  UITests/       UI-тесты (PetUITests): сценарии, скриншоты, раскадровки anim-*, перф
  Package.swift  Linux-сборка логики (WSL и logic.yml): явные списки sources из Shared и Tests
  Resources/Pets shiba.usdz и shiba.clips.json (собирает tools/assets)
tools/assets     конвейер 3D: Blender → glTF → usdz, клипы, проверка ассета
tools/wsl-test.sh   юнит-тесты логики в WSL (Swift на Linux)
tools/ipa_size.py   из чего состоит вес ipa и бюджет 40 МБ (волна 56; шаг «Ipa size» в job ipa)
probe/           ранний зонд возможностей iOS (код AppGroup оттуда)
.github/workflows   app.yml (сборка, тесты, ipa, перф), logic.yml, core.yml, assets.yml, probe-ipa.yml
```

Правило слоёв: Shared не видит App (в Linux-сборке App нет вовсе). Всё, что можно проверить без SwiftUI и
RealityKit, живёт в Shared и тестируется на Linux; App — тонкий вид поверх. Типы в Shared не называются как
типы SwiftUI (Wave5SeamTests следит).

## Поток данных

1. Стор — один JSON `state.json` в App Group (Shared/PetStore, SaveFile, Paths). Пишут приложение, виджеты и
   интенты; запись атомарная с повтором.
2. Время и действия — Shared/PetRunner поверх ядра (PetEngine.advance/apply). «Сейчас» — Shared/Clock
   (в UI-тестах сдвигается PET_NOW).
3. Снимок для показа — Shared/Presenter (PetSnapshot): одна плоская структура для приложения, виджетов,
   острова и превью. Прогноз «если никто не придёт» — ForecastTools.
4. Экран — App/AppModel (@Observable, AppModel.shared): держит копию стейта и снимок, тикер раз в 30 с,
   все действия кнопок. Действия из интентов идут через App/AppActions.
5. Виджеты и остров читают тот же стор и рисуют Shared/Views; кнопки — интенты из Shared/Intents.

## App: что где

| Область | Файлы |
|---|---|
| Вход, модель | PetApp (точка входа), AppModel (состояние экрана, действия; 1434 стр.), AppActions (общая точка для интентов), AwayReport («Пока тебя не было» и AwayBuilder), LaunchSeed (PET_RESET / PET_AWAY_H / PET_SEED для UI-тестов) |
| Главный экран | HomeScreen (сцена + слои, жесты, StatusScrim), ActionBar (панель действий, ActButton, ActBadge), HomeLayers (палец ласки, TouchBox, NameCard), HomeBanners (CalmTimerView, спасение, Banner, ToastView), HomeChips (кошелёк, «Открытка дня», «Вкус открыт!»), HintViews («что нужно сейчас», обучение жестам), WalkViews (ряд «Альбом · Автомат · Дом · Трюки · Игры · Гулять», записка, альбом), PopView |
| 3D-сцена | PetStage (RealityView, камера, загрузка Шибы), PetRoom (комната стиля A, материалы, веки), RoomDecor (вещи дома), RoomLighting (свет по времени), PetChoreo (компоненты и хореография по часам), ChoreoPath (чистые траектории), PetRig (шея, голова, челюсть, веки), PetStance (позы и клипы), PetClips (имена клипов), PetJuice (дыхание, пружины), PetWear (надетое в 3D), PostcardCamera (снимок сцены) |
| Экраны и листы | Screens (шкалы, отчёт, настройки, ошибка, каталог превью), HouseScreen, KitchenSheet, CapsuleScreen, ShopSheet, TricksScreen, BrushViews, CharacterViews, CharacterPacksScreen, CharacterAvatar, HabitsScreen, RulesScreen, IntroScreen, WidgetGuideSheet, GuideCenter, PostcardViews |
| Мини-игры | CatchGameScreen, BlockDuoScreen, ZombieRunScreen (логика каждой — в Shared: CatchGame, BlockDuo, ZombieRun + RetroRaster/ZombieArt) |
| Система | NotificationScheduler, LiveActivityController, StepsSync (CMPedometer), SoundKit (AVAudioEngine), FeelKit (отклик на касание: `Feel` — вибрация и звук в одной точке, волна 29; RESEARCH/15-feedback.md), ShortcutsProvider, StrokeTracker (разбор касаний) |

## Shared: что где

| Область | Файлы |
|---|---|
| Стор и время | PetStore, SaveFile, Paths, AppGroup, Clock, DayKey, PetRunner, PetAction, Backup, FirstWins, StableHash |
| Показ | Presenter, ForecastTools, IslandPlan, HomeText, Hush («одно сообщение за раз»), NeedHint, Guides, Onboarding, RenderPause, GlassSettle, JawTalk, PetNames |
| Экономика и дом | Economy, Catalog, Capsule, ShopDaily, ItemCatalog, ItemArt, HomeShop, HomeOffer, RoomPlan, Cooking, Finds |
| Питомец | Tastes, Traits, Memories, Tricks, Habits, OwnerSleep, Coat, CoatFur, Brush, Wear, WearMesh, TapWiggle, RoomLight, Postcards, PostcardPhotos |
| Тексты | Lines, LineRotation, NotificationPlanner |
| Звук и отклик | Synth, SoundRecipes, Feel (FeelGate: виды, кулдауны, тишина в фоне) |
| Мини-игры | CatchGame, BlockDuo, ZombieRun, ZombieArt, RetroRaster |
| Свои персонажи | CharacterPack, CharacterStore |
| Интенты и остров | Intents, PetAttributes (не в Linux-сборке: App Intents и ActivityKit), DeepLink |
| Views (общие вьюшки) | Components, PetPalette, PetFaceView, ItemIcon, WidgetViews, AccessoryViews, IslandViews, PreviewCatalog |

## Тесты

- PetTests (app/Tests, 68 файлов): на Linux идут файлы из `sources` PetTests в app/Package.swift (776 тестов
  на волне 28); исключённые (им нужны App, RealityKit, SwiftUI или интенты) — только в Xcode CI. Векторы ядра — core/vectors. Сохранения прошлых версий — Tests/Fixtures.
- Некоторые тесты читают исходники по пути: ClarityTests (WalkViews, HouseScreen, TricksScreen,
  CatchGameScreen, ActionBar), Wave5SeamTests (все файлы Shared). При переносе кода — править пути в них.
- PetUITests (app/UITests): accessibilityIdentifier — контракт с UI-тестами, их не переименовывать.
  Имена тестов уникальны: `grep -o "func test[A-Za-z0-9]*" app/UITests/*.swift | sort | uniq -d` пусто.
- CI: `gh workflow run app.yml -f mode=all|unit|ui|ipa|perf`. Локально — только WSL:
  `wsl -e bash tools/wsl-test.sh`.

## Как добавлять файл

- В App/, Shared/, Widgets/, Tests/, UITests/ — просто положить: XcodeGen берёт папки целиком.
- Новый файл в Shared/ без SwiftUI/UIKit/AppIntents/ActivityKit — дописать в `sources` таргета Pet в
  app/Package.swift (список явный). С ними — в Shared/Views (исключена целиком) или в `exclude` таргета Pet.
- Новый тест: на Linux — дописать в `sources` PetTests; если ему нужен App, RealityKit или SwiftUI — в `exclude`
  PetTests, иначе SwiftPM предупреждает «found N file(s) which are unhandled».
