# 11. CI приложения: .ipa и экраны картинками без iPhone

Дата: 16.10.2026. Workflow `.github/workflows/app.yml`, тесты `app/Tests/`, `app/UITests/`.
Цель: координатор сам смотрит виджеты, остров и экраны приложения по PNG из CI, не дожидаясь Вадима с телефоном.

## Запуск

```
gh workflow run app.yml                    # всё: .ipa + юнит + UI (mode=all)
gh workflow run app.yml -f mode=unit       # только юнит-тесты с покрытием
gh workflow run app.yml -f mode=ui         # только UI-тесты (ui-*, anim-*)
gh workflow run app.yml -f mode=ipa        # только .ipa (то же, что старое -f tests=false)
gh run list -w app.yml -L 1                # id прогона
gh run watch <id>
gh run download <id> -n Pet-screens -D builds/screens/<id>
gh run download <id> -n Pet-ipa -D builds
```

Только ручной запуск. Репо публичное с 18.10 — минуты Actions бесплатны, параллельные раннеры не стоят ничего. Повторный запуск на той же ветке отменяет ещё идущий (`concurrency`).

## Что делает

С волны 24 — четыре job вместо одного (было ≈ 52–54 мин подряд, см. «Минуты»):

1. **plan** (ubuntu, секунды) — по `mode` (и старому `tests=false`) решает, нужен ли .ipa, и строит matrix шардов тестов.
2. **ipa** (`macos-26`, параллельно с тестами) — XcodeGen → Release для iphoneos без подписи → ad-hoc `codesign` с entitlements (сначала appex, потом app) → проверка, что `group.com.vadimpet.pet` в подписи обоих → `Payload/` → zip. Пути к `.entitlements` берутся из `-showBuildSettings`. Артефакт **Pet-ipa**.
3. **test 1 / test 2** (`macos-26`, каждый на своём раннере, `fail-fast: false`) — у каждого свой симулятор (iPhone Air на самой новой iOS 26, иначе 17 Pro / 17; будится до XcodeGen и сборки), статус-бар 9:41, одна `build-for-testing` с подписью ad-hoc `-`, дальше `test-without-building`:
   - шард 1: PetTests с покрытием (`coverage.txt`) + `AnimationUITests` + `FirstMinutesUITests` — длинные тесты (20–85 с каждый);
   - шард 2: все остальные PetUITests (`-only-testing:PetUITests -skip-testing:` тех двух) — новый класс UI-тестов попадает сюда без правки workflow.
   Без параллельного клонирования симуляторов (оверрайд статус-бара на клоны не ложится, на 3 ядрах раннера клоны дают таймауты), таймаут 180 с на тест. Вложения выгружаются и при упавших тестах; части — `Pet-screens-part-N`, `Pet-xcresult-part-N` (сутки), `Pet-anim` сразу целиком из шарда 1.
4. **merge** (ubuntu) — `actions/upload-artifact/merge@v4` склеивает части в прежние **Pet-screens** (14 дней) и **Pet-xcresult** (`PetTests.xcresult`, `PetUITests-1.xcresult`, `PetUITests-2.xcresult`, `coverage.txt`; 7 дней) и удаляет части. Имена для `gh run download` не поменялись.

XcodeGen — локальный composite action `.github/actions/xcodegen` (бинарь с релиза 2.45.4, brew только если скачать не вышло): один и тот же шаг в ipa и шардах. Сторонних action нет, только `actions/*`.

Выгрузка: `xcrun xcresulttool export attachments --path <xcresult> --output-path <dir>` (Xcode 16+) по каждому xcresult шарда кладёт файлы под UUID и `manifest.json` вида `[{attachments:[{exportedFileName, suggestedHumanReadableName}]}]`; скрипт переименовывает в читаемое имя без хвоста `_0_<UUID>`.

## Что в Pet-screens

| Файл | Откуда |
|---|---|
| `widget-<семейство>-<состояние>.png` | WidgetSnapshotTests: small / medium / large, circular / rectangular / inline |
| `island-<семейство>-<состояние>.png` | то же: islandCompact / islandExpanded / lockActivity |
| `ui-00-alert-N.png` | системный запрос разрешения, если всплыл (потом жмётся «Разрешить») |
| `ui-01-main.png`, `ui-01-main-tree.txt` | главный экран и дерево его элементов (по нему видно accessibilityIdentifier) |
| `ui-1N-tab-N.png` | каждая вкладка, если приложение на TabView |
| `ui-2N-<имя>.png` | экраны из `ScreenshotUITests.screens` по accessibilityIdentifier |
| `ui-90-home.png` | рабочий стол после выхода: остров, если приложение запустило Live Activity |

Состояния: `fed`, `hungry`, `asleep` (тёмная тема), `critical`. Масштаб ×3, фон systemBackground, рамка со скруглением семейства. Размеры примерные под iPhone Air: важны пропорции.

## Что дописать при интеграции

1. **`app/Tests/SnapshotCatalog.swift`** — единственное место, где тесты касаются кода приложения:
   - `SnapshotCatalog.view(family:mood:)` → настоящая вью из `app/Shared/Views` (сейчас цветная плашка «заглушка»); `nil` — пары нет.
   - `StoreHooks.writeThenRead(marker:)` и `StoreHooks.food(afterHours:)` → через стор приложения (сейчас `nil`, тесты стора пропускаются со skip).
2. **project.yml** (тест-таргеты):
   ```yaml
   PetTests:
     type: bundle.unit-test
     platform: iOS
     sources: [Tests]
     settings: { base: { GENERATE_INFOPLIST_FILE: YES } }
     dependencies: [{ target: Pet }, { package: PetCore }]   # PetCore — для StoreTests.testCoreTimeMoves
   PetUITests:
     type: bundle.ui-testing
     platform: iOS
     sources: [UITests]
     settings: { base: { GENERATE_INFOPLIST_FILE: YES } }
     dependencies: [{ target: Pet }]
   ```
   и у Pet `scheme: { testTargets: [PetTests, PetUITests] }`. Без `package: PetCore` у PetTests тест ядра пропускается (`#if canImport`), а при импорте без линковки возможна ошибка линковки — лучше добавить.
3. **Идентификаторы** кнопок экранов: `open.shop`, `open.home`, `open.wardrobe`, `open.settings` (или поправить список в `ScreenshotUITests.screens`). Тест получает `-uiTesting` и `PET_UI_TEST=1` — приложение может по ним пропустить онбординг или подложить состояние.
4. **economy.json**: тест ядра ищет `economy.json` в бандле Pet, иначе читает `config/economy.json` из репо (симулятор видит диск Mac).

## Локально (если будет Mac)

`TEST_RUNNER_SNAPSHOT_DIR=/tmp/shots xcodebuild test -project app/Pet.xcodeproj -scheme Pet -destination 'platform=iOS Simulator,name=iPhone Air'` — `TEST_RUNNER_*` передаётся в процесс тестов без префикса. Без переменной PNG ложатся в `NSTemporaryDirectory()/snapshots` симулятора.

## Минуты

Оценка, не замер (зонд собирался 27 с, у Pet больше кода и RealityKit):

| Этап | ~минут |
|---|---|
| раннер, checkout, XcodeGen | 0,5 |
| .ipa Release (+ подпись, zip, выгрузка) | 1,5–3 |
| сборка Debug под симулятор | 1,5–3 |
| unit-тесты + UI-тесты (запуски, алерты, вкладки) | 1–2 |
| выгрузка вложений и артефактов | 0,3 |
| **итого tests=true** | **≈ 5–8** |
| **итого tests=false** | **≈ 2–4** |

GitHub округляет job вверх до минуты. При ~200 macOS-минутах в месяц (минус потраченное на зонд) это ~20–25 прогонов с тестами. Экономия: `tests=false`, когда нужен только .ipa; не запускать на каждую мелочь — копить правки.

**Кэш.** Кэшировать почти нечего: SPM-пакет локальный, внешних зависимостей нет; XcodeGen скачивается за секунды. DerivedData в кэш не кладём: 300+ МБ туда-обратно ≈ 1 мин, а checkout меняет mtime файлов, и Swift всё равно пересобирается.

## Если упало

- **Подпись под симулятор** (`requires a development team` / ошибка codesign в Test on simulator): заменить `CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual` на `CODE_SIGNING_ALLOWED=NO`. Тесты пойдут, но App Group без entitlements может не дать контейнер — `testAppGroupContainerRoundTrip` уйдёт в skip, стор приложения уйдёт в запасную папку Documents.
- **Пустые снимки** (`Пустые снимки: …`): вью рисует то, что ImageRenderer не умеет (RealityView, UIViewRepresentable, карты). Для виджетов и острова это и так нельзя — там нужны готовые картинки.
- **UI-тест долго ждёт** на тапах: XCUITest ждёт «простоя» приложения, а живая 3D-сцена его не даёт. Под `PET_UI_TEST=1` приложению стоит ставить сцену на паузу или снижать FPS.
- **Нет PNG**: смотреть `Pet-xcresult` (открывается в Xcode) и лог шага «Export screenshots» — он печатает список файлов.

## Источники

- Образ раннера macOS 26 (Xcode, симуляторы, отсутствие XcodeGen): https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md
- `xcresulttool export attachments` (`--path`, `--output-path`, `--test-id`, `--only-failures`): https://keith.github.io/xcode-man-pages/xcresulttool.1.html
- Формат `manifest.json` (`exportedFileName`, `suggestedHumanReadableName`) на живом скрипте: https://github.com/omarshahine/HomeClaw/pull/144 и https://github.com/alexrrouse/xcodebuild-axi/issues/58
- Релизы XcodeGen (2.45.4, ассет `xcodegen.zip`): https://github.com/yonaskolb/XcodeGen/releases
- Тарифы macOS-минут: RESEARCH/01-signing-build.md
