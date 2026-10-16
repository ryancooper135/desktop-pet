# 09. Архитектура приложения v0.1

В v0.1 входят: Этап 2 «Каркас» целиком, из Этапа 3 пузырь мысли, «Пока тебя не было», уведомления и критичное состояние, из Этапа 3½ таймлайн, таймер, кнопки-интенты, экран блокировки и остров.
Не входят: 3D-кадры в виджетах (пока 2D-мордочка), сервер (только интерфейс), мини-игры, монеты и инвентарь, 20+ поз (в v0.1 их 13).
Документ опирается на `probe/` (проверено на телефоне 16.10), `core/swift` и RESEARCH/02, 05, 07, 08.

## 0. Решения коротко

- Вся правда о питомце в одном файле `state.json` в App Group. Пишут только приложение и интенты. Виджет только читает и досчитывает время в памяти.
- Ядро `PetCore` не трогаем. Для хранения используем свои Codable-копии `PetDTO`/`OwnerDTO`, их JSON совпадает с форматом `core/vectors`. `PetState` живёт только внутри синхронных функций и между акторами не ходит, поэтому strict concurrency его не задевает.
- Каждое чтение и запись идёт через `NSFileCoordinator` с атомарной записью и счётчиком `rev`. Время досчитывается при каждом обращении.
- Кнопки виджета, острова и контрола — `LiveActivityIntent`. Они выполняются в процессе приложения, код острова закрыт `#if APP_TARGET`.
- Виджет: таймлайн на 24 ч вперёд (шаг 30 мин плюс моменты событий прогноза), перезагрузка через 12 ч.
- Уведомления планирует чистая функция по прогнозу на 72 ч: не больше 1 в день, «скучаю» на 3, 6, 9 и 12-й день, всего ≤ 50.
- Остров стартует, когда приложение уходит в фон, и мягко перезапускается после 7 ч при любом пробуждении приложения. `staleDate` ставим на следующее событие прогноза.
- Свои типы-«снимки» (`PetSnapshot`) Sendable. Все вью получают только снимок, поэтому их можно рендерить в тестах через `ImageRenderer`.

## 1. Дерево `app/`

```
app/
  project.yml                    XcodeGen: Pet, PetWidgets, PetTests, PetUITests, схема Pet (§10)
  App/                           только таргет Pet (флаг APP_TARGET)
    PetApp.swift                 @main; scenePhase → onForeground/onBackground; ставит делегат уведомлений в init
    AppModel.swift               @MainActor @Observable: текущий PetSnapshot, тост, флаги экранов; тикер раз в 30 с
    AppActions.swift             @MainActor: единая точка «сделать действие»: PetRunner → остров → виджеты → уведомления → бэкап
    LiveActivityController.swift start / update / end / мягкий рестарт после 7 ч
    NotificationScheduler.swift  применяет NotificationPlanner: снимает pending «pet.*», ставит новые
    NotificationDelegate.swift   категории и фоновые действия «Покормить» и «Погладить» (didReceive)
    StepsSync.swift              CMPedometer → .steps(n) при каждом входе в foreground
    SignWatch.swift              срок подписи → SaveFile.build, «амнистия» за просроченную подпись (§2.5)
    MirrorBackup.swift           копия state.json в Documents приложения (страховка при смене App Group)
    ShortcutsProvider.swift      AppShortcutsProvider: фразы «Команд»
    Screens/
      HomeScreen.swift           ZStack: сцена, оверлеи, панель действий, тосты
      PetStage.swift             RealityView: shiba.usdz или заглушка; поза → анимация
      StubDog.swift              собака из примитивов RealityKit
      ActionBar.swift            плавающие кнопки (glass), состояния disabled по причинам отказа
      NeedsSheet.swift           шкалы по запросу и прогноз «к 18:00»
      AwayScreen.swift           «Пока тебя не было»
      RescueOverlay.swift        уровень 3: кнопка «Спасти»
      RulesScreen.swift          честные правила смерти (на 3-й день или при первом «Плохо»)
      MemorialScreen.swift       смерть: альбом и «Начать заново»
      SettingsScreen.swift       имя, график сна, остров вкл/выкл, срок подписи, сброс
      SignBanner.swift           «подпись истекает через N дн.»
  Shared/                        компилируется в оба таргета; без @main, без RealityKit
    AppGroup.swift               AppGroup.resolved (ALTAppGroups → embedded.mobileprovision → константа) — из probe
    ProvisioningProfile.swift    entitlements(), expirationDate() из embedded.mobileprovision
    Paths.swift                  каталог стейта: группа → fallback Application Support; env PET_STORE_DIR для тестов
    Clock.swift                  Clock.now(): Date() или env PET_NOW (UI-тесты)
    Catalog.swift                Rules из economy.json, Lines из lines.json (один раз на процесс)
    Lines.swift                  загрузчик lines.json с нейтральными заглушками, pick(...) с ротацией
    StableHash.swift             FNV-1a 64 (Hasher не годится: он солится на каждый запуск)
    PetDTO.swift                 PetDTO, OwnerDTO (Codable, Sendable) ↔ PetState, Owner
    PetAction.swift              enum PetAction (Sendable) → PetCore.Action; ActionSource
    SaveFile.swift               формат state.json (§2.1)
    PetStore.swift               координированное чтение и запись (§2.2)
    PetRunner.swift              catchUp(now) и perform(action) внутри одной записи (§2.3)
    Journal.swift                JournalEntry: журнал для «Пока тебя не было» и outbox для сервера
    Presenter.swift              (SaveFile, now) → PetSnapshot: поза, желание, реплика, таймеры, главное действие
    PetSnapshot.swift            PetSnapshot, Pose, Want, NeedTimer (Codable, Hashable, Sendable)
    ForecastTools.swift          прогноз → точки таймлайна, ближайший low, окна сна
    NotificationPlanner.swift    чистая функция: план уведомлений (§6)
    PetAttributes.swift          ActivityAttributes + ContentState (§5)
    Intents.swift                LiveActivityIntent-ы действий, StartIslandIntent, StatusIntent, IntentBridge
    Backup.swift                 protocol BackupService, NoopBackup (§8)
    FrameStore.swift             (на будущее) PNG-кадры из App Group с даунсемплом; сейчас всегда nil
    Views/                       всё, что рисует виджет и остров; только PetSnapshot на входе
      PetFaceView.swift          2D-мордочка из Shape по Pose; widgetAccentable-контур
      ThoughtBubble.swift        пузырь мысли: иконка желания
      HeartsView.swift           сердца половинками
      NeedTimerView.swift        ProgressView(timerInterval:) + подпись
      WidgetSmallView.swift
      WidgetMediumView.swift     + Button(intent:) «Погладить» и «Хрустик»
      AccessoryViews.swift       circular, rectangular, inline
      IslandViews.swift          compactLeading, compactTrailing, minimal, expanded
      LockScreenActivityView.swift
  Widgets/                       только таргет PetWidgets
    PetWidgetsBundle.swift       @main WidgetBundle { PetWidget; PetLiveActivity; IslandControl; FeedControl }
    PetWidget.swift              StaticConfiguration, все 5 семейств, containerBackground — только здесь
    PetTimelineProvider.swift    таймлайн на 24 ч (§4)
    PetLiveActivity.swift        ActivityConfiguration: регионы острова и экран блокировки
    PetControls.swift            контролы Пункта управления
  Tests/                         PetTests (хост Pet, @testable import Pet)
    PetDTOTests.swift            round-trip: start из core/vectors → PetState → DTO → тот же JSON
    PetStoreTests.swift          100 параллельных mutate → rev == 100, ни одной потери; битый файл → .broken
    PetRunnerTests.swift         catchUp через 3 суток = PetEngine.advance; часы назад не откатывают; амнистия подписи
    PresenterTests.swift         moods → Pose и Want по приоритету; главное действие; уровень 3 → «Спасти»
    TimelineTests.swift          ≤ 64 точек, по возрастанию, первая = now, есть точки событий; measure на 24 ч
    NotificationPlannerTests.swift  ≤ 1 в день, ни одного во сне хозяина, ≤ 50, детерминированность, «скучаю» 3/6/9/12
    CatalogTests.swift           economy.json и lines.json есть в бандлах Pet и PetWidgets.appex, Rules парсится
    LinesTests.swift             нет ключа → нейтральный текст; 7 дней подряд без повторов; плейсхолдеры
    ProvisioningTests.swift      ExpirationDate и группы из фикстуры Fixtures/sample.mobileprovision
    ViewRenderTests.swift        ImageRenderer по всем вью × все Pose → картинка не nil, размер > 0, вложения PNG
    Fixtures/sample.mobileprovision   текстовый plist в обёртке (без подписи), только для парсера
  UITests/                       PetUITests
    HomeFlowUITests.swift        покормить → тост, шкалы по долгому нажатию, отказ «в ванне»
    AwayUITests.swift            PET_AWAY_H=10 → экран «Пока тебя не было» → закрыть
    RescueUITests.swift          PET_SEED=critical → «Спасти» → уровень падает
```

Правила раскладки:
- В `Shared/` нет `import RealityKit` и `@main`.
- `containerBackground` и `.widgetURL` ставятся только в `Widgets/`, чтобы вью из `Shared/Views` рендерились в тестах без окружения WidgetKit.
- `AppActions`, `LiveActivityController` и `NotificationScheduler` существуют только в `App/`, в `Shared` их вызывают под `#if APP_TARGET`.

## 2. Общий стейт

### 2.1. Файл `state.json`

Путь: `<группа>/pet/state.json`. Рядом лежат `state.prev.json` (копия на каждый 10-й rev), `album/<petId>.json` (умершие питомцы) и `frames/` (на будущее).

```swift
struct SaveFile: Codable, Sendable {
    var v = 1
    var rev = 0                       // +1 на каждую запись; читатели сравнивают
    var petId: String                 // UUID, сид всех ротаций
    var deviceId: String              // UUID устройства; часть id событий для сервера
    var seq = 0                       // счётчик событий deviceId:seq
    var name = "Шиба"
    var createdT: Double
    var owner: OwnerDTO               // bedMin, wakeMin, tzOffsetMin
    var pet: PetDTO                   // ключи ровно как в core/vectors "start"
    var lastSeenT: Double             // приложение последний раз было на экране
    var lastStepsT: Double?
    var lastAction: LastAction?       // {kind, source, t, ok, reason} — для кадра-ответа в виджете
    var journal: [JournalEntry] = []  // ≤ 200, старые отрезаем
    var outbox: [JournalEntry] = []   // действия для будущего сервера, ≤ 500
    var build: BuildInfo?             // {expiresT, seenT}
    var island = IslandInfo()         // {enabled = true, startedT?, activityId?}
    var flags = Flags()               // rulesShown, widgetHintCount, widgetHintT, notifAsked
}

struct PetDTO: Codable, Sendable, Equatable {
    var t: Double; var needs: [String: Double]; var hearts: Double; var grace: [String: Double]
    var lastChanceH, napUntil, bathUntil, lastHeartLossT: Double?
    var cooldowns: [String: Double]; var home: [String: Int]
    var alive: Bool; var diedAt: Double?; var cause: String?
    init(_ s: PetState)                     // поля у PetState публичные — читаем напрямую
    var state: PetState { PetState(json: jsonValue) }  // memberwise-init у PetState internal, идём через init(json:)
}
```

`PetDTO → PetState` строится через `JSONValue`, а не через memberwise-init: тот у ядра internal. Опционалы кодируются как `null` (нужен свой `encode(to:)` с `encodeNil`, иначе ключ пропадёт; `init(json:)` терпит оба варианта).

### 2.2. Координация доступа: `PetStore`

```swift
final class PetStore: Sendable {
    static let shared = PetStore(dir: Paths.stateDir)
    let url: URL
    init(dir: URL) { url = dir.appending(path: "pet/state.json") }

    func read() throws -> SaveFile? {             // виджет, Presenter
        var err: NSError?; var out: Result<SaveFile?, Error> = .success(nil)
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &err) { u in
            out = Result { try Self.load(u) }
        }
        if let err { throw err }
        return try out.get()
    }

    @discardableResult
    func mutate<T>(_ body: (inout SaveFile) throws -> T) throws -> T {   // чтение+изменение+запись одним замком
        var err: NSError?; var out: Result<T, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &err) { u in
            out = Result {
                var f = try Self.load(u) ?? SaveFile.fresh(now: Clock.now())
                let r = try body(&f)
                f.rev += 1
                try JSONEncoder().encode(f).write(to: u, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                return r
            }
        }
        if let err { throw err }
        return try out!.get()
    }
}
```

- `NSFileCoordinator` работает между процессами (приложение, расширение, интент в фоне) и между экземплярами внутри одного процесса. Отдельный актор не нужен, а синхронный API проще для Swift 6.
- `load` различает два случая. Файла нет → `nil` → новый питомец (только при первом запуске). Файл не декодируется → переименовать в `state.broken-<t>.json`, взять `state.prev.json`, затем копию из Documents (§8). **Молча новую собаку не заводить.**
- Защита файла: `completeUntilFirstUserAuthentication`, ни в коем случае не `.complete`. Иначе виджет и интент на заблокированном телефоне не прочитают стейт.
- Каталог: `AppGroup.resolved` → `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`. Если `nil` (группу срезала подпись), берём `Application Support` и ставим флаг `Paths.isShared = false`: приложение показывает баннер, виджет пишет «открой приложение».
- Виджет **никогда не пишет**: читает и досчитывает в памяти. Так нет гонок и не тратится бюджет перезагрузок.

### 2.3. Что такое «сейчас»: `PetRunner`

```swift
enum PetRunner {
    /// Догнать время. Вызывается внутри mutate, перед любым действием и при входе в приложение.
    static func catchUp(_ f: inout SaveFile, now: Double) -> [ForecastEvent]
    /// catchUp + act + журнал + outbox + lastAction.
    static func perform(_ a: PetAction, source: ActionSource, store: PetStore = .shared, now: Double = Clock.now()) throws -> ActResult
    /// Только для показа: состояние на момент T без записи (виджет, тикер экрана).
    static func peek(_ f: SaveFile, at T: Double) -> PetState   // PetEngine.advance
}
```

- `now = Clock.now()` = `Date().timeIntervalSince1970`. В UI-тестах время берётся из env `PET_NOW`.
- `catchUp`:
  1. Если `now ≤ pet.t + 60`, ничего не делаем. Остаток меньше минуты ядро само дождётся до следующего вызова (`stepTo` шагает по 60 с).
  2. Если `pet.t − now > 300` (часы отвели назад), не откатываем и пишем в журнал `clock_back`.
  3. Иначе `events = forecast(s, R, o, horizonH: (now − s.t)/3600)` — это события «пока не было», их пишем в журнал. Затем `stepTo(&s, R, o, now)`. Стоимость: 7 дней = 10 080 шагов × 2, единицы миллисекунд.
  4. После шага обновляем `owner.tzOffsetMin = TimeZone.current.secondsFromGMT(for: now)/60`, чтобы ночь считалась по местному времени с учётом перелёта и перехода на летнее время. Обновлять **после** шага: прошлое досчитывается в старом поясе.
- Действие ядра выполняется в момент `s.t`, отставание от `now` меньше 60 с. Это приемлемо и совпадает с TS-песочницей.
- Глобальные правила: `enum Catalog { nonisolated(unsafe) static let rules: Rules = try! Rules(data: bundle("economy.json")) }`. `Rules` не Sendable, но неизменяем после init. Если в ядро добавят `Sendable` (см. вопросы), `nonisolated(unsafe)` можно убрать.

### 2.4. Журнал

```swift
struct JournalEntry: Codable, Sendable {
    var id: String          // "\(deviceId):\(seq)"
    var t: Double           // момент в часах устройства
    var kind: String        // "act.feed" | "act.pet" | … | "ev.low.food" | "ev.heart" | "ev.distress.starve" | "ev.death" | "clock_back" | "sign_pause"
    var source: ActionSource?   // app | widget | island | control | shortcut | notification | steps
    var ok: Bool?; var reason: String?; var value: Int?
}
```

`act.*` пишется и в `journal`, и в `outbox`, `ev.*` — только в `journal`. Формат `t` для сервера (`est/wall/boot/mono` из 05) добавим в v0.2. Сейчас хранится только `t`, сервер примет его как `wall`.

### 2.5. `build_age`: срок подписи

```swift
enum ProvisioningProfile {
    static func plist(_ bundle: Bundle = .main) -> [String: Any]?   // кусок <?xml … </plist> из embedded.mobileprovision (код из probe)
    static func expirationDate(_ bundle: Bundle = .main) -> Date? { plist(bundle)?["ExpirationDate"] as? Date }
}
```

- Срок читает приложение при запуске и на каждом foreground. `buildDaysLeft = ceil((expiresT − now)/86400)`.
- **Порядок важен.** Сначала сравниваем со **старым** `build.expiresT`: если `pet.t < old.expiresT < now`, подпись успела истечь, пока приложение не запускалось. Тогда «амнистия»:
  1. `catchUp` до `old.expiresT`;
  2. время `[old.expiresT, now]` пропускаем: `pet.t = now`, без убыли;
  3. в журнал пишем `sign_pause`.

  Только после этого записываем новый срок. Так соблюдается правило из ROADMAP: смерть только от реального забвения, а не от сбоя.
- Предупреждение за 2 дня (`expiresT − now < 48 ч`):
  - баннер `SignBanner` в приложении;
  - значок `⏳2д` в small и medium виджете и строка в rectangular;
  - уведомления в `expiresT − 48 ч` и `expiresT − 24 ч` в час после подъёма хозяина. Они занимают слот «1 в день» с наивысшим приоритетом (§6).
- `embedded.mobileprovision` нет на симуляторе и в CI-сборке без подписи → `nil`, ничего не показываем.
- У расширения свой `embedded.mobileprovision` в бандле `.appex`, но виджет берёт срок из `SaveFile.build`: так проще и одинаково.

## 3. Интенты

В ядре есть ровно эти действия: `.feed(id)`, `.item(id)`, `.pet`, `.play`, `.bath`, `.steps(n)`, `.wake`. «Уложить» в ядре нет: ночь идёт по графику `Owner`, дрёма начинается сама при `energy < 15`. В v0.1 вместо этого есть лампа (§7). Монет и инвентаря нет, поэтому `.feed` везде означает `kibble` («хрустик»), `.item` в v0.1 не показываем.

```swift
enum PetAction: Codable, Hashable, Sendable { case feed(String), item(String), pet, play, bath, wake, steps(Int)
    var core: Action { … } }
enum ActionSource: String, Codable, Sendable { case app, widget, island, control, shortcut, notification, steps }

enum IntentBridge {
    static func run(_ a: PetAction, _ src: ActionSource) async throws -> ActResult {
        #if APP_TARGET
        return await AppActions.shared.perform(a, source: src)     // + остров, уведомления, бэкап
        #else
        let r = try PetRunner.perform(a, source: src)            // страховка: если вдруг выполнился в расширении
        WidgetCenter.shared.reloadAllTimelines()
        return r
        #endif
    }
}

struct FeedIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Покормить"
    @Parameter(title: "Откуда", default: "widget") var source: String
    init() {}
    init(_ src: ActionSource) { source = src.rawValue }
    func perform() async throws -> some IntentResult {
        _ = try await IntentBridge.run(.feed("kibble"), ActionSource(rawValue: source) ?? .widget)
        return .result()
    }
}
```

| Интент | Тип | Где используется | Что делает |
|---|---|---|---|
| `FeedIntent` | LiveActivityIntent | medium-виджет, остров, контрол, «Команды» | `.feed("kibble")` |
| `PetIntent` | LiveActivityIntent | medium-виджет, остров, «Команды» | `.pet` (кулдаун 3 мин, +12 love) |
| `BathIntent` | LiveActivityIntent | «Команды» | `.bath` |
| `WakeIntent` | LiveActivityIntent | остров (во время дрёмы) | `.wake`, только если `napUntil != nil` |
| `PlayIntent` | AppIntent, `openAppWhenRun` | «Команды» | открывает приложение (игра в нём) |
| `MainActionIntent` | LiveActivityIntent | главная кнопка острова, «Спасти» | `Presenter.mainAction(snapshot)` (ниже) |
| `StartIslandIntent` | LiveActivityIntent | контрол «Позвать в остров», кнопка «Разбудить» на устаревшем острове, «Команды» | end старой активности + request новой |
| `StatusIntent` | AppIntent + `ProvidesDialog` | «Команды» и Siri | «Шиба сыт, хочет играть. Проголодается к 18:00» |

- **Главное действие** (`mainAction`, то же для «Спасти» и тапа в критичном состоянии) — первое подходящее по списку:
  1. мёртв → открыть приложение;
  2. в ванне → нет кнопки, показываем таймер;
  3. `hungry` или `starve` → покормить;
  4. `smelly`, `dirty` или distress `dirty` → помыть;
  5. `wants_love` или `toska` → погладить;
  6. дрёма → разбудить;
  7. иначе → погладить.
- Почему везде `LiveActivityIntent`: обычный `AppIntent` из виджета выполняется в расширении и не обновляет остров (проверено зондом). `LiveActivityIntent` система запускает в процессе приложения, тот видит `Activity.activities` и может стартовать новую активность из фона.
- **Swift 6:**
  - все статические свойства интентов только `static let` (`title`, `description`, `openAppWhenRun`, `isDiscoverable`); `static var` даёт ошибку конкурентности, в probe так было только из-за Swift 5;
  - кнопки в `Shared/Views` создаются как `Button(intent: FeedIntent(.widget))`.
- **Контролы (iOS 18+):**
  - `IslandControl` — `ControlWidgetButton(action: StartIslandIntent())`, «Позвать в остров»;
  - `FeedControl` — `ControlWidgetButton(action: FeedIntent(.control))`;
  - оба в одном расширении, `kind` = `"pet.control.island"` и `"pet.control.feed"`.
- **«Команды»:**
  - `ShortcutsProvider` (только `App/`), не больше 10 `AppShortcut`, в каждой фразе `\(.applicationName)`;
  - фразы: «Покормить в …», «Погладить в …», «Как там …», «Позвать … в остров», «Искупать в …»;
  - `openAppWhenRun = false` у всех, кроме `PlayIntent`.

`AppActions.perform` (только приложение, `@MainActor`) идёт по шагам:
1. `PetRunner.perform`;
2. `AppModel.refresh()`;
3. `LiveActivityController.update()`;
4. `WidgetCenter.shared.reloadAllTimelines()` (с дебаунсом 2 с);
5. `NotificationScheduler.replan()` (с дебаунсом 2 с);
6. `backup.push` (с дебаунсом 30 с).

## 4. Виджет

### 4.1. Провайдер

`PetTimelineProvider: TimelineProvider`, обычный (без конфигурации), методы с completion: у `TimelineProvider` нет async-вариантов.

```
getTimeline:
  f = PetStore.shared.read()  ?? → одна запись «открой приложение», .after(+1 ч)
  s = PetRunner.peek(f, at: now)
  fc = PetEngine.forecast(s, R, o, horizonH: 24)              // 1440 шагов
  times = {now} ∪ {now + k·30 мин, k=1…48} ∪ {e.t | e ∈ fc}
          ∪ {bathUntil, napUntil, начало/конец ночи питомца в ближайшие 24 ч}
          ∪ {lastAction.t + 90 с, если реакция ещё показывается}
  отсортировать, убрать ближе 60 с друг к другу, обрезать до 64
  для каждого T по возрастанию: s = PetEngine.advance(s, R, o, T)   // инкрементально, всего ≤ 1440 шагов
                                entry = PetEntry(date: T, snap: Presenter.snapshot(f, s, T))
  Timeline(entries, policy: .after(now + 12 ч))
```

- Перезагрузок не больше 2 в сутки по таймеру плюс по `reloadAllTimelines` от действий. Нажатия интентов бюджет не тратят. Итог укладывается в 40–70.
- `PetEntry: TimelineEntry, Sendable { date; snap: PetSnapshot; var relevance: TimelineEntryRelevance? { .init(score: Float(snap.level)) } }` — Smart Stack поднимает виджет, когда питомцу плохо.
- **Кадр-ответ.** Если `lastAction` моложе 90 с и `ok`, первая запись показывает позу `eating` или `loved` с репликой `widget["react_feed"]` или `widget["react_pet"]`, следующая запись — в `lastAction.t + 90 с`. Если `!ok`, показываем реплику по причине (`widget["refuse_bathing"]` и т. п.).
- Память: только Foundation, SwiftUI, WidgetKit, PetCore. Никакого RealityKit и больших картинок. Прогноз на 24 ч стоит миллисекунды и почти ноль памяти, до лимита 30 МБ далеко.

### 4.2. Позы, желания, реплики (`Presenter`)

Поза — первое совпадение по `moods` (приоритет сверху вниз):

| moods / условие | Pose | Want (пузырь) |
|---|---|---|
| `dead` | `.dead` | — |
| `lastAction` < 90 с | `.eating` / `.loved` | — |
| `bath` | `.bath` | — (таймер ванны) |
| `sleep` | `.sleep` | — |
| `nap` | `.nap` | — |
| `critical` | `.critical` | самое срочное |
| `hungry` | `.hungry` | `food` |
| `smelly` / `dirty` | `.dirty` | `bath` |
| `tired` | `.tired` | `sleep` |
| `bored` | `.bored` | `play` |
| `wants_love` | `.lonely` | `love` |
| `walk` < 30 | `.happy` | `walk` |
| ничего | `.happy` (утром и вечером `.idle`) | — |

- Итого 13 поз. Позже их будет 20+ (06 #5): новые позы добавляются в `Pose` и в `PetFaceView`, логика остаётся той же.
- Реплика: `Lines.pick(section: "widget", key: pose.rawValue, seed: petId, slot: floor(T / 1800))`. Слот меняется каждые 30 мин, индекс идёт по пулу по кругу, так что повтора нет, пока пул не кончится (§6.3).
- Пузырь: `thoughts[want] = {icon, text}`. Если в `icon` имя SF Symbol (`UIImage(systemName:) != nil`), рисуем `Image(systemName:)`, иначе `Text(icon)` (эмодзи).
- Таймер нужды: `NeedTimer(kind, start, end)`:
  - в ванне: `start = bathStartT`, `end = bathUntil` (`bathStartT` = момент `.bath` из журнала);
  - иначе ближайшее событие `low` из прогноза: `start = T`, `end = e.t`, `kind = e.key`.

  Вью рисует `ProgressView(timerInterval: start...end, countsDown: true) { } currentValueLabel: { Text(timerInterval: start...end) }`. Если `end ≤ start`, вместо таймера пишем текст «сейчас». Если событий на 24 ч нет, таймер не показываем.

### 4.3. Семейства

Один `PetWidget` (kind `"pet.main"`), `supportedFamilies` = все пять, вью выбирается по `@Environment(\.widgetFamily)`:

| Семейство | Содержимое | Кнопки |
|---|---|---|
| `systemSmall` | мордочка ~60 %, пузырь, 1 строка реплики, полоска таймера; значок `⏳2д` | нет, тап → `pet://home` |
| `systemMedium` | слева мордочка; справа имя, сердца, реплика, таймер | «Погладить» `PetIntent(.widget)`, «Хрустик» `FeedIntent(.widget)` |
| `accessoryCircular` | `Gauge(value: hearts, in: 0...max)` стиль `.accessoryCircularCapacity`, в центре мордочка-контур | нет |
| `accessoryRectangular` | мордочка + реплика + «голод через `Text(end, style: .relative)`» | нет |
| `accessoryInline` | `Text("\(name): поест к \(end, format: .dateTime.hour().minute())")` | нет |

- Режимы `tinted`, `clear`, `vibrant`: 2D-мордочка нарисована `Shape`-контурами, поэтому сама становится монохромной. Контур помечаем `.widgetAccentable()`, заливку для `@Environment(\.widgetRenderingMode) != .fullColor` выключаем. Это главный плюс 2D в v0.1.
- `containerBackground(for: .widget)` ставит только `PetWidget.swift`. Для circular — `AccessoryWidgetBackground()`.

### 4.4. Как дальше рендерить 3D в PNG (Этап 4)

- **Где:** только приложение в foreground (GPU в фоне запрещён). Рендерим при первом запуске, после смены модели или шмоток и раз в сутки при открытии, если `frames/manifest.json` старше модели. Длинный пакет продолжаем через `BGContinuedProcessingTask` (iOS 26), но только то, что успело начаться на экране.
- **Чем:** `RealityRenderer` (iOS 18+): сцена с моделью, `PerspectiveCamera`, свет, прозрачный фон → `MTLTexture` → `CGImage` → PNG с альфой. Точную сигнатуру `render(...)` сверить в SDK первым CI-прогоном. Запасной путь — `ARView(cameraMode: .nonAR)` + `snapshot(saveToHDR:)` вне экрана.
- **Что:** позы × эмоции × размеры. Остров 120 px, small/medium 360 px, accessory 150 px. Для tinted отдельно `_mono.png`: белый контур с альфой.
- **Куда:** `<группа>/pet/frames/v<modelRev>/<pose>_<size>.png` + `manifest.json {modelRev, poses, sizes}`.
- **Как читает виджет:** `FrameStore.image(pose:size:)` → ImageIO `CGImageSourceCreateThumbnailAtIndex` с `maxPixelSize`, не больше 3–4 картинок на запись. Если файла нет, рисуем `PetFaceView`. Для моно-режима `Image(...).widgetAccentedRenderingMode(.accentedDesaturated)` (iOS 18).
- **Альтернатива** для стандартной Шибы: кадры рендерит Blender в CI (03) и кладёт в бандл, на устройстве рендерятся только свои модели пользователя.

## 5. Live Activity

```swift
struct PetAttributes: ActivityAttributes {
    var petName: String
    struct ContentState: Codable, Hashable, Sendable {
        var pose: String; var want: String?; var line: String
        var hearts: Double; var heartsMax: Double; var level: Int
        var main: String                 // "feed" | "bath" | "pet" | "wake" | "open" | "none"
        var timerStart: Date?; var timerEnd: Date?; var timerKind: String?
        var updatedAt: Date
    }   // ~300 байт, при лимите 4 КБ
}
```

**Старт** (`LiveActivityController.start()`). Условия: `ActivityAuthorizationInfo().areActivitiesEnabled`, `island.enabled`, питомец жив, активности ещё нет.
- Приложение ушло в фон (`scenePhase == .background`). Это главный путь: закрыл приложение — питомец переехал в остров.
- `StartIslandIntent` из контрола, из «Команд» или по кнопке «Разбудить» на устаревшем острове. Работает из фона, проверено зондом.
- Вызов: `Activity.request(attributes:, content: .init(state:, staleDate:), pushType: nil)`. Пишем `island.startedT` и `activityId`. Запланированный старт с `startDate` в v0.1 не нужен.

**Обновление** (`update()`) — после каждого действия (`AppActions`), на смене `scenePhase`, в `didReceive` уведомления.
- Не вызываем `update`, если `ContentState` равен прошлому (Hashable), и не чаще раза в 5 с: система всё равно режет.
- `staleDate` = ближайшее из: `bathUntil`, следующее событие прогноза (`low`/`distress`/`heart`), `startedT + 8 ч`. В `isStale` вью показывает позу «дремлет», реплику `island["stale"]` и кнопку «Разбудить» (`StartIslandIntent`). Так ограничение 8 ч становится механикой: «уснул в острове — разбуди» (07 #16).
- Таймеры (`Text(timerInterval:)`, `ProgressView(timerInterval:)`) тикают сами, без обновлений.

**Мягкий рестарт.** При любом пробуждении приложения (foreground, любой `LiveActivityIntent`, действие уведомления), если `now − startedT > 7 ч`, делаем `end(…, dismissalPolicy: .immediate)` и сразу `request`. Через `BGAppRefresh` не делаем: приходит редко. Отдельное уведомление «разбуди меня в острове» в v0.1 выключено (флаг `islandWakeNote = false`): рестарт из фонового действия уведомления не проверен зондом на iOS 26 (см. вопросы).

**Конец:**
- смерть → `end(final, dismissalPolicy: .after(now + 1 ч))`, поза `.dead`;
- выключили остров в настройках → `.immediate`;
- рестарт → `.immediate`;
- если ничего не будит приложение, система сама уберёт активность из острова через 8 ч, на экране блокировки она останется до 4 ч в виде «уснул».

**Регионы** (вью в `Shared/Views/IslandViews.swift`):

| Регион | Что показывает |
|---|---|
| compact leading | `PetFaceView(pose)` 24 pt |
| compact trailing | таймер ванны или дрёмы (`Text(timerInterval:)`, `monospacedDigit`, ширина ≤ 44 pt); иначе иконка желания; иначе `♥4` |
| minimal | мордочка; при `level ≥ 2` — иконка желания красным |
| expanded leading | мордочка 44 pt + имя |
| expanded trailing | `HeartsView` с `.contentTransition(.numericText())` |
| expanded center | реплика (1 строка) |
| expanded bottom | **одна** главная кнопка `Button(intent: MainActionIntent())` с подписью по `main` + `NeedTimerView` |
| экран блокировки | строка: мордочка, реплика, таймер, главная кнопка; в `isStale` — «Разбудить» |

Расширение рисует только 2D-мордочку. Когда появятся PNG (§4.4), остров возьмёт кадр 120 px из `FrameStore`.

## 6. Уведомления

### 6.1. Планировщик (`NotificationPlanner`, чистая функция в Shared)

```swift
struct PlannedNote: Hashable, Sendable { var id: String; var date: Date; var title: String; var body: String; var category: String; var priority: Int }
static func plan(_ f: SaveFile, rules: Rules, lines: Lines, now: Double, deliveredToday: Bool) -> [PlannedNote]
```

1. `s = peek(f, now)`, `fc = forecast(s, R, o, 72)`.
2. Кандидаты из прогноза: событие → триггер, приоритет:

   | Событие | Триггер | Приоритет |
   |---|---|---|
   | `last_chance` | `last_chance` | 5 |
   | `heart` | `heart_lost` | 4 |
   | `distress.starve`, `distress.dirty`, `distress.toska` | `distress_starve`, `distress_dirty`, `distress_toska` | 3 |
   | `low.food`, `low.clean`, `low.fun`, `low.love` | `hungry`, `dirty`, `bored`, `lonely` | 2 |
   | `death` | не уведомляем | — |

   На `death` не уведомляем: о риске уже предупредил `last_chance`.
3. Подпись: `expiresT − 48 ч` и `expiresT − 24 ч` → `build_expiring`, приоритет 6.
4. «Скучаю»: `quiet = max(lastSeenT, последнее act.* в журнале)`. Даты `quiet + 3, 6, 9, 12 дней` в `wake + 3 ч` → `miss_you`, приоритет 1. После 14 дней ничего не шлём.
5. Время: если `ownerAsleep(t)`, переносим на `wake + 30 мин` того же утра. Не раньше `now + 10 мин`.
6. **Не больше 1 в местный день.** В каждом дне оставляем максимальный приоритет, при равенстве — более раннее. Если `deliveredToday` (приложение спросило `deliveredNotifications()`), день 0 пропускаем, кроме приоритетов 5–6.
7. Отсортировать, обрезать до 50 (на деле выходит меньше 10: 3 дня прогноза + 4 «скучаю» + 2 подписи). Запас до системного лимита 64 остаётся под будущие напоминания.
8. `id = "pet.\(localDayIndex)"`: при перепланировании тот же день заменяется, а не дублируется.

**Когда перепланировать:** при запуске, после каждого действия (дебаунс), при уходе в фон, в `didReceive`. Перепланирование снимает pending с префиксом `pet.` и ставит план заново.

**Разрешение** на уведомления просим после первой удачной кормёжки, а не на старте (`flags.notifAsked`).

### 6.2. Категории (`NotificationDelegate`)

- `pet.need`: действия `feed` «Покормить» и `pet` «Погладить», `options: []` (без `.foreground`). Система будит приложение в фоне, `didReceive` → `AppActions.perform(…, source: .notification)` → остров, виджеты, перепланирование.
- `pet.miss`: действие `pet`.
- `pet.build`: без действий, тап открывает настройки.
- Тап по самому уведомлению открывает приложение, на нём будет «Пока тебя не было».
- `interruptionLevel = .active`, `relevanceScore = priority/6`, `threadIdentifier = "pet"`. Time Sensitive не используем (нет прав). Notification Content Extension не заводим: расширение одно.

### 6.3. Тексты и ротация (`Lines`)

- `Lines` декодирует `lines.json` через `JSONValue` и терпит отсутствие любого раздела или ключа: подставляет нейтральное `{name} зовёт тебя` / `…` / `{name} рядом`.
- Плейсхолдеры: `{name}`, `{time}` (`HH:mm` события).
- Выбор: `pool[(stableHash(petId + section + key) + slot) mod pool.count]`. У уведомлений `slot = localDayIndex`: соседние дни берут соседние элементы, и при пуле ≥ 7 повторов за 7 дней нет без хранения истории.
- Хеш: FNV-1a 64 по UTF-8. `Hasher` нельзя: он солится на каждый запуск, и выбор поплывёт между приложением и расширением.
- Ключи, которые ждёт код:
  - `notifications`: `hungry`, `dirty`, `bored`, `lonely`, `distress_starve`, `distress_dirty`, `distress_toska`, `heart_lost`, `last_chance`, `miss_you`, `build_expiring`;
  - `widget` и `island`: все `Pose.rawValue` + `react_feed`, `react_pet`, `refuse_<reason>`, `stale`;
  - `thoughts`: `food`, `bath`, `sleep`, `play`, `love`, `walk`;
  - `away`: `slept`, `low_food`, `low_clean`, `low_fun`, `low_love`, `heart_lost`, `act_widget`, `act_island`, `act_notification`, `sign_pause`, `nothing`.

  Сверить с content/README.md, когда он появится (см. вопросы).

## 7. Главный экран v0.1

`HomeScreen`: `ZStack` из `PetStage` (на весь экран), верхнего оверлея (имя, `HeartsView`, `ThoughtBubble` над головой — 2D-оверлей, не 3D), `ActionBar` снизу и тостов.

**Сцена (`PetStage`):**

```swift
RealityView { content in
    content.camera = .virtual                         // iOS 18+: без AR и без камеры
    let pet = await PetModel.load()                   // Entity(named: "shiba", in: .main) или StubDog.make()
    content.add(pet); content.add(PetModel.camera()); content.add(PetModel.light()); content.add(PetModel.floor())
} update: { content in
    PetModel.apply(pose: model.snap.pose, reduceMotion: reduceMotion, to: content)
}
```

- `PetModel.load()` сначала проверяет `Bundle.main.url(forResource: "shiba", withExtension: "usdz")`. Если модели нет, `StubDog`:
  - `ModelEntity` из `generateBox` и `generateSphere` с `SimpleMaterial` в цветах Шибы: туловище, голова, 2 уха-коробки, хвост, 4 лапы;
  - low-poly и flat-shading совпадают со стилем A.
- Анимация позы:
  - если у usdz есть `availableAnimations`, проигрываем первую в цикле;
  - у заглушки: `happy` — подпрыгивание через `move(to:relativeTo:duration:)`, `sleep`/`nap` — лёг (поворот и сжатие по Y), `bath` — пена-сферы, `dead` — лёг серым.
- Reduce Motion: только статичные позы.
- Фон — градиент по времени суток. Комнаты в v0.1 нет.

**Жесты и действия:**
- Тап по питомцу: реакция. При `level ≥ 2` тап выполняет `mainAction` (08 #11).
- Ведёшь пальцем по питомцу (`DragGesture`, суммарный путь > 150 pt) → `.pet` (08: гладить пальцем).
- Долгое нажатие или свайп вверх → `NeedsSheet` (`.presentationDetents([.medium])`): 7 шкал и «голод 30 % к 18:00» из прогноза. Шкалы по запросу, на главном экране их нет.
- `ActionBar` (`.glassEffect()` только здесь, зоны ≥ 44 pt, шрифт ≥ 13 pt):
  - Хрустик `.feed("kibble")`, Помыть `.bath`, Играть `.play`;
  - Разбудить `.wake` — видна только во время дрёмы;
  - **Лампа** — видна с 20:00 до 02:00, ставит `owner.bedMin` = сейчас (кратно 5 мин). Питомец ляжет через 15 мин по правилам ядра, событие пишется в журнал. Это и есть «уложить» в v0.1.
  - Кормление перетаскиванием миски — после v0.1.
- Отказы ядра → тост с человеческим текстом:

  | Причина | Тост |
  |---|---|
  | `bathing` | «Он в ванне ещё 12 мин» (по `bathUntil`) |
  | `cooldown` | «Дай ему передохнуть» |
  | `asleep` | «Тсс, спит» |
  | `tired` | «Устал, пусть поспит» |
  | `not_napping` | — (кнопки и так нет) |
  | `dead` | → Memorial |

  Кнопка, которая сейчас заведомо откажет, полупрозрачна, но нажимается и объясняет причину.
- Уровень 3 → `RescueOverlay`: тёмная виньетка и одна большая кнопка «Спасти» (`mainAction`), тап по питомцу делает то же.
- `RulesScreen` (08 §4): один раз (`flags.rulesShown`), на 3-й день от `createdT` или при первом `level ≥ 2`.
- Смерть: `MemorialScreen`. Старый `SaveFile` уходит в `album/<petId>.json`, кнопка «Начать заново» → новый `petId`, новый `PetState`. Сам альбом позже.
- Шаги: `StepsSync` на foreground. `CMPedometer.queryPedometerData(from: max(lastStepsT, now − 7 д), to: now)` → `.steps(n)` с `source: .steps`. Колбэк оборачиваем в `withCheckedContinuation`, наружу отдаём только `Int`.
- Подсказка «поставь виджет и остров» после первой удачной кормёжки, повтор через 7 дней, не больше 2 раз (`flags.widgetHint*`).

**«Пока тебя не было» (`AwayScreen`):**
- Показываем на foreground, если `now − lastSeenT ≥ 30 мин` и с `lastSeenT` есть записи в журнале или была ночь. Перед показом выполняется `catchUp`, и его события уже лежат в журнале.
- Содержимое:
  1. «Тебя не было 9 ч»;
  2. «Спал 23:45–07:59» — окна `petNight` в `[lastSeenT, now]`, выборка шагом 5 мин;
  3. список из журнала с `t > lastSeenT`: свои действия с источником («Погладил из виджета в 14:02»), события («Проголодался в 12:10», «Потерял сердечко в 15:30»), `sign_pause`;
  4. текущее желание и кнопка главного действия.
- Тексты из `away[...]`, при пустом журнале — `away["nothing"]`.
- `lastSeenT = now` пишем при закрытии экрана и на каждом уходе в фон.

## 8. Бэкап на сервер (в v0.1 только интерфейс)

```swift
struct BackupSnapshot: Codable, Sendable { var file: SaveFile; var takenT: Double }
protocol BackupService: Sendable {
    func push(_ snap: BackupSnapshot) async throws          // v0.2: POST /v1/sync {sinceRev, events: outbox[≤200]}
    func pull() async throws -> BackupSnapshot?             // v0.2: state + rev из ответа /v1/sync
}
struct NoopBackup: BackupService { func push(_: BackupSnapshot) async throws {}; func pull() async throws -> BackupSnapshot? { nil } }
```

- Где вызывается:
  - `AppActions` держит `let backup: any BackupService = NoopBackup()`;
  - `push` идёт после записи (дебаунс 30 с) и при уходе в фон внутри `UIApplication.beginBackgroundTask`;
  - `pull` — только при запуске, если нет ни `state.json`, ни `state.prev.json`, ни копии в Documents.
- Уже в v0.1 работает местная страховка `MirrorBackup`: после каждой записи из приложения копия уходит в `Documents/state.mirror.json`, это контейнер приложения. Она переживает смену App Group, например переподпись другим Apple ID с другим суффиксом группы. При запуске: если в группе файла нет, а копия есть, восстанавливаем из копии.
- `outbox` уже копится в нужном виде (`id = deviceId:seq`). В v0.2 `SyncBackup` из 05 (воркер `pet-sync`, ключ P-256 устройства) заменяет `NoopBackup` одной строкой.

## 9. Риски компиляции и песочницы и как их обойти

| Риск | Обход |
|---|---|
| Типы PetCore (`PetState`, `Rules`, `Owner`, `Action`, `ForecastEvent`, `JSONValue`) не Sendable; пакет в режиме Swift 5 | Наружу из синхронного кода отдаём только свои Sendable-типы (`SaveFile`, `PetDTO`, `PetSnapshot`, `PetAction`). Глобальные правила — `nonisolated(unsafe) static let`. В файлах с PetCore при необходимости `@preconcurrency import PetCore`. Лучше всего добавить `: Sendable` в ядро (все типы — значения, правка на 10 строк, векторы не меняются) — вопрос координатору |
| Ошибки Swift 6 в системных протоколах (делегат уведомлений, CMPedometer, TimelineProvider) | Делегат: `@MainActor final class … NSObject, UNUserNotificationCenterDelegate`, методы `nonisolated … async`, из `response` достаём только `String`. Колбэки — через `withCheckedContinuation` с Sendable-результатом. Запасной план, если первая CI-сборка упрётся в десятки таких ошибок: таргету `SWIFT_VERSION = 5.0` + `SWIFT_STRICT_CONCURRENCY = complete` (ошибки станут предупреждениями), чинить постепенно |
| `static var` в интентах и других типах | Только `static let` или вычисляемые `static var x: T { … }` |
| deploymentTarget iOS 26 против 18 в probe | Всё, что используем, есть с iOS 18 (`RealityView.camera = .virtual`, контролы, `widgetAccentedRenderingMode`); 26 нужен только для `.glassEffect()`. Ставим 26.0, как решено. Если раннер `macos-26` не найдёт рантайм симулятора 26 для тестов, проблема в образе, а не в коде |
| `LiveActivityIntent` компилируется в оба таргета, а `AppActions` есть только в приложении | `#if APP_TARGET` внутри `IntentBridge`; `SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) APP_TARGET"` только у `Pet` (как в probe). Ветка `#else` пишет стейт сама, так что ничего не теряется |
| Ресурсы `lines.json` и `economy.json` должны быть в обоих таргетах; `content/` ещё не существует | В `project.yml` пути `../content/ru/lines.json` (с `optional: true`) и `../config/economy.json` с `buildPhase: resources` в обоих таргетах. Без `economy.json` приложение падает на `try!` — тест `CatalogTests` проверяет бандлы обоих таргетов. Без `lines.json` работают нейтральные тексты |
| Память расширения 30 МБ, стоимость прогноза | Без RealityKit в Shared и Widgets, прогноз на 24 ч (1440 шагов) и инкрементальный `advance`. В `TimelineTests` есть `measure`. PNG — через ImageIO-миниатюры |
| Защита файлов: виджет и интент на заблокированном телефоне | `.completeFileProtectionUntilFirstUserAuthentication` при каждой записи |
| App Group ID с суффиксом команды (`…VJYQ5469NG`) | `AppGroup.resolved` из probe, в entitlements `group.com.vadimpet.pet`, Sideloadly переписывает. Если `nil` — fallback-каталог и баннер; копия в Documents |
| Sideloadly и версии расширения | В `info.properties` обоих таргетов явно: `CFBundleExecutable: $(EXECUTABLE_NAME)`, `CFBundleVersion: $(CURRENT_PROJECT_VERSION)`, `CFBundleShortVersionString: $(MARKETING_VERSION)` |
| Лимит App ID: приложение + расширение = 2 из 10 в неделю | Не менять bundle ID между сборками, не добавлять расширений |
| Тесты на бесплатной подписи и в CI | Тесты гоняем только в CI на симуляторе, на телефон их не ставим. Для симулятора `"CODE_SIGN_IDENTITY[sdk=iphonesimulator*]": "-"`: подпись ad-hoc, группа на симуляторе работает. Тесты всё равно пишут в `PET_STORE_DIR` (tmp). Сборка `.ipa` идёт отдельным job как в probe: `CODE_SIGNING_ALLOWED=NO` + codesign appex → app |
| Имя симулятора в CI меняется с образом | `DEST=$(xcrun simctl list devices available iPhone \| grep -m1 -oE 'iPhone [^(]+' \| sed 's/ *$//')` → `-destination "platform=iOS Simulator,name=$DEST"` |
| Live Activity и виджеты не тестируются в UI-тестах | Их вью проверяются через `ImageRenderer` в `ViewRenderTests` (PNG уходят во вложения xcresult); сами регионы — руками на телефоне по чек-листу |
| `RealityRenderer` и `Entity(named:in:)` — сигнатуры iOS 18/26 не проверены компиляцией | В v0.1 только `RealityView` + `Entity(named:)` + примитивы — проверенные API. `RealityRenderer` откладываем до Этапа 4 |
| Рестарт острова из фонового действия уведомления на iOS 26 не проверен | В v0.1 выключено, рестарт кнопкой и при открытии. Зонд — отдельной задачей |
| Пользователь переводит часы | Вперёд — честная убыль (принимаем). Назад — не откатываем, `clock_back` в журнал |

## 10. `project.yml`: что отличается от probe

```yaml
name: Pet
options:
  deploymentTarget: { iOS: "26.0" }
packages:
  PetCore: { path: ../core/swift }
settings:
  base:
    SWIFT_VERSION: "6.0"
    MARKETING_VERSION: "0.1"
    CURRENT_PROJECT_VERSION: "1"
    TARGETED_DEVICE_FAMILY: "1"
    CODE_SIGN_STYLE: Manual
    DEVELOPMENT_TEAM: ""
    "CODE_SIGN_IDENTITY[sdk=iphonesimulator*]": "-"
targets:
  Pet:
    type: application
    platform: iOS
    sources:
      - App
      - Shared
      - { path: ../config/economy.json, buildPhase: resources }
      - { path: ../content/ru/lines.json, buildPhase: resources, optional: true }
      # - { path: Assets/shiba.usdz, buildPhase: resources, optional: true }   # Этап 4
    dependencies: [{ target: PetWidgets }, { package: PetCore }]
    settings: { base: { PRODUCT_BUNDLE_IDENTIFIER: com.vadimpet.pet, SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) APP_TARGET" } }
    info: { path: App/Info.plist, properties: { CFBundleDisplayName: "Питомец", NSSupportsLiveActivities: true,
            NSMotionUsageDescription: "Питомец гуляет вместе с тобой по шагам", UILaunchScreen: {},
            UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait], CFBundleURLTypes: [{ CFBundleURLSchemes: [pet] }] } }
    entitlements: { path: App/App.entitlements, properties: { com.apple.security.application-groups: [group.com.vadimpet.pet] } }
  PetWidgets:
    type: app-extension
    platform: iOS
    sources: [Widgets, Shared, { path: ../config/economy.json, buildPhase: resources },
              { path: ../content/ru/lines.json, buildPhase: resources, optional: true }]
    dependencies: [{ package: PetCore }]
    settings: { base: { PRODUCT_BUNDLE_IDENTIFIER: com.vadimpet.pet.widgets } }
    info: { path: Widgets/Info.plist, properties: { CFBundleDisplayName: "Питомец",
            CFBundleExecutable: "$(EXECUTABLE_NAME)", CFBundleVersion: "$(CURRENT_PROJECT_VERSION)",
            CFBundleShortVersionString: "$(MARKETING_VERSION)",
            NSExtension: { NSExtensionPointIdentifier: com.apple.widgetkit-extension } } }
    entitlements: { path: Widgets/Widgets.entitlements, properties: { com.apple.security.application-groups: [group.com.vadimpet.pet] } }
  PetTests:
    type: bundle.unit-test
    platform: iOS
    sources: [Tests, { path: ../core/vectors, buildPhase: resources, type: folder }]
    dependencies: [{ target: Pet }]          # XcodeGen сам выставит TEST_HOST
  PetUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [UITests]
    dependencies: [{ target: Pet }]
schemes:
  Pet:
    build: { targets: { Pet: all } }
    test: { targets: [PetTests, PetUITests], gatherCoverageData: false }
    run: { config: Debug }
```

Env для тестов (читает `Paths`/`Clock`, в релизе игнорируется под `#if DEBUG`):

| Переменная | Что делает |
|---|---|
| `PET_STORE_DIR` | каталог стейта |
| `PET_NOW` | фиксированное «сейчас» |
| `PET_RESET=1` | начать с чистого стейта |
| `PET_SEED=critical\|nap\|bath` | готовое состояние |
| `PET_AWAY_H=10` | `lastSeenT = now − 10 ч` |

## 11. Порядок написания кода

1. `Shared/`: `PetDTO` → `SaveFile` → `PetStore` → `PetRunner` → `Catalog`/`Lines` → `Presenter`. Сразу тесты (`PetDTOTests`, `PetStoreTests`, `PetRunnerTests`, `PresenterTests`).
2. `Shared/Views` + `ViewRenderTests`.
3. `Widgets/` (провайдер, `PetWidget`, `PetLiveActivity`, контролы) + `Intents.swift`.
4. `App/`: `PetApp`, `AppModel`, `AppActions`, `LiveActivityController`, `HomeScreen` с заглушкой.
5. Уведомления (`NotificationPlanner` + тесты → `NotificationScheduler` + `NotificationDelegate`).
6. `AwayScreen`, `RescueOverlay`, `RulesScreen`, `SignWatch`, `MirrorBackup`, `StepsSync`, UI-тесты.
