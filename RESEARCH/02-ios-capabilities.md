# 02. Что разрешает iOS 26 питомцу без пушей и платного аккаунта

Дата: 15.10.2026. Рамки: sideload с бесплатного Apple ID, без APNs, без Family Controls и Screen Time. Телефон iPhone Air с Dynamic Island. Архитектура: приложение, одно расширение WidgetKit (виджеты + Live Activity + Control) и App Group.

Пометки: **[Apple]** значит официальная дока или WWDC, **[форум]** значит Apple Developer Forums, **[сторонний]** значит блог или видео, **[вывод]** значит моё заключение, которое нужно проверить зондом.

---

## Вывод

1. **Питомец в острове возможен, но он не «живёт» сам по себе.** Live Activity держится до 8 ч в острове, а на экране блокировки ещё до 4 ч. Своего кода у неё нет: ни сети, ни таймеров, только SwiftUI-снимок состояния до 4 КБ. «Жизнь» в остров приносят три вещи:
   - системные таймеры: `Text(timerInterval:)` и `ProgressView(timerInterval:)` тикают сами, без обновлений;
   - переходы `contentTransition` и `transition` при каждом обновлении, до 2 с анимации;
   - обновления из процесса приложения: кнопки `LiveActivityIntent` прямо в острове, контрол в Пункте управления, действия уведомлений, редкие фоновые окна.

   Частые обновления не работают: с iOS 18 система режет их примерно до одного раза в 5–15 с, и это дорого по батарее.
2. **Перезапуск через 8 ч без пушей можно сделать через интент.** `LiveActivityIntent` (из кнопки в острове, контрола или ярлыка Команд) запускает процесс приложения в фоне без открытия, а оттуда разрешено **стартовать** новую Live Activity. С iOS 26 есть и запланированный старт `request(...startDate:)`, но запланировать его можно только пока приложение живо.
3. **Виджеты — это открытки.** Перезагрузок 40–70 в сутки, записи timeline не чаще раза в 5 мин. Кнопки и тумблеры на AppIntent работают, и их нажатия в бюджет не входят. «Анимацию» в виджете дают только системные таймеры и хаки со шрифтами. В режимах Liquid Glass «прозрачный» и «тонированный» непрозрачные спрайты превращаются в белые силуэты, поэтому спрайты нужны с альфой и проверкой в этих режимах.
4. **Привычки владельца без Screen Time** берём из:
   - шагов: `CMPedometer`, история за 7 дней;
   - HealthKit: **доступен на бесплатной подписи**, это сон, шаги, mindful-минуты;
   - геозон: `CLMonitor` (дом, работа);
   - автоматизаций Команд, которые пользователь собирает руками. Они вызывают App Intent питомца: «зарядка подключена», «открыл TikTok», «будильник выключен», «пришёл домой». С iOS 17 они идут без подтверждения, но всегда показывают баннер о запуске.

   Поставить автоматизацию из приложения программно нельзя.
5. **Уведомления** только локальные: до 64 ожидающих, у повторяющихся свой лимит. Можно картинку или GIF во вложении, свой звук (голос питомца) и кнопки-действия, которые выполняются в фоне без открытия. Time Sensitive (пробивает «Фокус») требует entitlement, которого на бесплатной подписи нет, это проверит зонд.
6. **3D: нативный RealityKit.** SceneKit в iOS 26 помечен deprecated: Apple называет это «soft deprecation, maintenance mode», он работает, но не развивается. Для PS2-look в iOS 26 есть:
   - `PostProcessEffect` для RealityView: даунсэмпл, дизеринг, палитра;
   - `CustomMaterial` с geometry modifier: дрожание вершин, affine-искажение;
   - `GeometricPin` для шмоток на костях.

   `RealityRenderer` рендерит офскрин в `MTLTexture`, а оттуда в PNG. Это для пререндера кадров в виджеты и остров, но **только в foreground**: GPU в фоне на iPhone запрещён.
7. **Godot или Unity не нужны.** Виджеты, Live Activity, контролы и интенты всё равно пишутся на Swift. Движок добавит вес, сборку под Mac и/или облако и мост между двумя мирами, а выигрыш даст только в редакторе сцен. Вердикт: Swift + SwiftUI + RealityKit, ассеты в USDZ (из Blender).
8. **Голос «как у Тома»** делается полностью штатно:
   - `AVAudioEngine` + `AVAudioUnitTimePitch` (+1000…+1200 центов) — повтор фразы смешным голосом;
   - `SpeechAnalyzer`/`SpeechTranscriber` (новое в iOS 26, on-device) или `SFSpeechRecognizer` с `requiresOnDeviceRecognition` — для команд «сидеть», «молодец», имени питомца.

   Есть ли русский в новом `SpeechTranscriber`, проверит зонд.
9. **iOS 27 уже вышла** (WWDC26). Для нас там:
   - остров в ландшафте (`isDynamicIslandLimitedInWidth`);
   - Live Activity в StandBy на 200% (`activityBackgroundTint`);
   - семейство `systemExtraLargePortrait`.

   Изменений лимитов, бюджетов или старта из фона в сессиях не заявлено. Код под iOS 26 будет работать и на 27.

---

## По пунктам: можно / нельзя / хак (цена)

### 1. Live Activity без пушей

| | |
|---|---|
| **Можно** | Стартовать из foreground: `Activity.request(attributes:content:)`. **Стартовать из фона через `LiveActivityIntent`**: Apple прямо пишет, что система запускает процесс приложения, выполняет интент и стартует Live Activity; пример — контрол в Пункте управления. Обновлять и завершать из фона (BackgroundTasks, обработчик действия уведомления, интент). Запланированный старт в iOS 26: `request(attributes:content:pushType:style:alertConfiguration:startDate:)`, `alertConfiguration` обязателен. `staleDate` переводит состояние в «устарело» (`context.isStale`), остров сам покажет «спит / скучает» без обновлений. `relevanceScore`, если активностей несколько. `dismissalPolicy`: `.default` (до 4 ч на экране блокировки), `.immediate`, `.after(date)`. Кнопки и тумблеры `Button(intent:)` прямо в развёрнутом острове и на экране блокировки. `LiveActivityIntent` выполняется **в процессе приложения**, то есть доступен весь код и App Group. Анимации до 2 с: `.transition(.opacity/.move/.slide/.push)`, `.contentTransition(.numericText(countsDown:))`. |
| **Нельзя** | Жить дольше 8 ч в острове (+4 ч на экране блокировки = 12 ч максимум). Сеть и геолокация внутри Live Activity: у неё своя песочница. Данные больше 4 КБ (статические и динамические вместе). Картинки больше размера презентации: старт может не пройти. Контент выше 160 pt обрезается. Минимальный вид — кружок около 28 pt. Частые обновления: с iOS 18 их режут примерно до раза в 5–15 с; инженер Apple советует около 15 с, а для отсчётов использовать таймер-текст. Анимации на Always-On (`isLuminanceReduced`). Кнопки на заблокированном телефоне работают только после разблокировки. Push-to-start, broadcast и push-обновления: нужен APNs. |
| **Хак (цена)** | **«Вечный» остров.** За 30–60 мин до 8 ч приложение (в любом фоновом окне или по интенту) завершает старую активность и стартует новую. Цена: нужен повод, чтобы приложение проснулось. Надёжные поводы — нажатие кнопки, контрол, действие уведомления; BGAppRefresh приходит редко. Реалистично: локальное уведомление «⭐ скучает, тапни» с фоновым действием «Погладить», и это действие перезапускает активность. **«Дыхание» и моргание** без обновлений: `Text(timerInterval:)` со своим шрифтом, где глифы — кадры спрайта (хак Bryce Bostwick, см. «Виджеты»). Цена: сложная подготовка шрифта; работа внутри Live Activity не подтверждена, это зонд. **Шкалы голода и сна** через `ProgressView(timerInterval:)`: тикают сами, но без кастомных стилей. **Смена позы** раз в 15+ с через `update` с `contentTransition`/`transition`: работает, но расходует батарею и упирается в троттлинг. Механика Pixel Pals и Island Pet публично не раскрыта; по отзывам 2024–2025, питомец Island Pet «живой» только при открытой игре. |

### 2. Виджеты (Home, Lock Screen, StandBy) и Controls

| | |
|---|---|
| **Можно** | Timeline с записями на будущее (смена настроения по расписанию без пробуждения приложения). Кнопки и тумблеры на AppIntent: «покормить» прямо с домашнего экрана. Обычный AppIntent выполняется в процессе расширения, после `perform()` перезагрузка timeline гарантирована. Не тратят бюджет: приложение в foreground, нажатие AppIntent, активная аудиосессия или Now Playing, анимации, смена локали. Анимированные переходы между записями: с iOS 17 обновление анимируется. Совет David Smith: угол поворота наращивать, а не сбрасывать. `ProgressView(timerInterval:)` и `Text(timerInterval:)` обновляются непрерывно. `@Environment(\.widgetRenderingMode)` + `.widgetAccentedRenderingMode(...)` + `.widgetAccentable()` — своя вёрстка под Liquid Glass. Режим разработчика WidgetKit в Настройках снимает бюджеты для отладки. **Controls** (`ControlWidgetButton`/`ControlWidgetToggle`) в Пункте управления, на экране блокировки и на кнопке Action с AppIntent, OpenIntent или SetValueIntent. Через `LiveActivityIntent` контрол может стартовать Live Activity. iOS 27: семейство `systemExtraLargePortrait`. |
| **Нельзя** | Перезагружаться чаще 40–70 раз в сутки (раз в 15–60 мин), записи timeline чаще раза в 5 мин. Свой рендер, Metal или RealityKit внутри виджета, а также больше 30 МБ памяти в расширении (EXC_RESOURCE). Свои PNG в иконке Control: только SF Symbol или свой символ (SVG-шаблон в каталоге символов). Push-обновления виджетов (`WidgetPushHandler`, iOS 26): нужен APNs. В режимах «прозрачный» и «тонированный» непрозрачные картинки становятся белым силуэтом; `.fullColor` Apple советует только для обложек медиа, хотя на практике (форум 809767) его ставят и спрайтам. |
| **Хак (цена)** | **Анимация шрифтом-таймером** (Bryce Bostwick, «Apple's Widget Backdoor»): `Text(timerInterval:)` + свой шрифт, где цифры или лигатуры — кадры, плюс маски и перекрывающиеся таймеры. Обычный таймер даёт около 1 кадра/с, с ухищрениями до ~30 кадров/с. Цена: надёжность падает на 150–200 таймерах, очень трудоёмко, анимация жёстко зашита в шрифт. Для моргания и покачивания 2–4 кадрами этого хватит. **`_clockHandRotationEffect`** (приватный API системных часов) даёт ~20 кадров/с вращения. Цена: приватный API, нужен реэкспорт через старый Xcode, может сломаться в любом обновлении. Для себя допустимо, но не рекомендую. **Память:** картинки грузить с диска App Group по URL, держать мало записей timeline, спрайты маленькие (до 2× размера показа). |

### 3. Привычки владельца без Screen Time

| | |
|---|---|
| **Можно** | **CMPedometer**: `queryPedometerData` за последние 7 дней (шаги, этажи, дистанция), `startUpdates` пока приложение живо. Нужен `NSMotionUsageDescription`. **HealthKit**: по таблице Apple capability доступна на бесплатном аккаунте; это сон, шаги, mindful-минуты, «время в дневном свете» (если пишет часы). **CLMonitor** (iOS 17+): вход и выход из круговой зоны «дом», «работа», «зал»; события будят приложение в фоне. **Команды → автоматизации**: «Приложение открыто/закрыто» (TikTok → «питомец ревнует»), «Зарядное устройство подключено» (сон телефона), «Будильник остановлен» (проснулся), «Прибытие/Уход», «Время суток», «Фокус вкл./выкл.», NFC-метка у миски. С iOS 17 почти все запускаются «Выполнять сразу», локация тоже. Действием служит App Intent питомца из App Shortcuts: `OwnerEventIntent(kind: .appOpened("TikTok"))`. Он работает в фоне, пишет событие в App Group и при необходимости перезагружает виджет или обновляет Live Activity. Последнее — **[вывод]**: если интент сделать `LiveActivityIntent`, он выполнится в процессе приложения. |
| **Нельзя** | Узнать, какие приложения открывались и сколько: это только Screen Time и Family Controls, на бесплатной подписи недоступно. Поставить автоматизацию за пользователя: такого API нет. Убрать баннер «Выполняется автоматизация». Импортировать готовый `.shortcut` файлом без подписи: с iOS 15 нужна подпись, `shortcuts sign` есть только на macOS. Иначе пользователь делится iCloud-ссылкой со своего iPhone. Фоновая доставка HealthKit с гарантированной частотой: обычно не чаще раза в час, и как это ведёт себя на бесплатной подписи — неизвестно, это зонд. |
| **Хак (цена)** | **Набор iCloud-ссылок на готовые Команды**: один раз собрать на iPhone и раздать себе по ссылке. Автоматизации всё равно создаются руками, это 5–10 минут разовой настройки. **NFC-стикер у кровати или миски**: автоматизация «NFC» становится игровым действием «покормил», «уложил». Цена: стикер около 1 € и баннер при каждом срабатывании. **Агрегировать шаги и сон** при каждом открытии приложения и в BGAppRefresh, а не ловить в реальном времени. |

### 4. Локальные уведомления

| | |
|---|---|
| **Можно** | До **64** ожидающих запросов на приложение; повторяющийся считается за один (инженер Apple, форум 811171). `UNCalendarNotificationTrigger`, `UNTimeIntervalNotificationTrigger`, `UNLocationNotificationTrigger`. Вложения `UNNotificationAttachment`: PNG и GIF питомца (GIF анимируется в развёрнутом виде). Свой звук из бандла, до 30 с: питомец «пищит». Категории с действиями: действие **без** `.foreground` будит приложение в фоне и вызывает `userNotificationCenter(_:didReceive:withCompletionHandler:)`. Там можно покормить, обновить App Group, перезагрузить виджеты и **перезапустить Live Activity**. `.textInput`-действие: ответить питомцу текстом прямо из уведомления. `interruptionLevel = .active/.passive`, `relevanceScore` для сводки. |
| **Нельзя** | Push (APNs). `.timeSensitive` в обход «Фокуса»: нужен entitlement Time Sensitive Notifications, которого нет у бесплатного аккаунта. `.critical`: нужно разрешение Apple. Больше 64 ожидающих: остальные молча отбрасываются. |
| **Хак (цена)** | **Скользящее окно**: при каждом пробуждении (открытие, действие, интент, BGAppRefresh) пересчитывать ближайшие ~50 уведомлений по прогнозу состояния питомца. Цена: если приложение долго не просыпается, расписание устаревает; поэтому последние уведомления в окне — «я скучаю, загляни». **Notification Content Extension** (свой UI в развёрнутом уведомлении) — это **второе** расширение, оно ломает правило «одно расширение» и тратит лишний App ID. Не нужно. |

### 5. Фоновая работа (общая для пп. 1–4)

| | |
|---|---|
| **Можно** | `BGAppRefreshTask`: время выбирает система, на практике от раза в несколько часов до раза в день, работа длится около 2–5 с (форумы 729824, 725675). `BGContinuedProcessingTask` (iOS 26): продолжить начатую в foreground задачу с прогрессом в системном UI. Подходит для долгого пререндера кадров после смены шмоток. Background modes на бесплатном аккаунте разрешены. |
| **Нельзя** | GPU и Metal в фоне на iPhone: ошибка «Insufficient Permission (to submit GPU work from background)». Фоновый GPU есть только у iPad с M3+ (ответ DTS, форумы 816774, 801229). Значит, никакого RealityKit-рендера в фоне. |
| **Хак (цена)** | Держать приложение живым через тихое аудио или фоновую локацию — злоупотребление background modes. Цена: батарея и риск, что iOS убьёт процесс. Не рекомендую. |

### 6. 3D на iOS 26

| | |
|---|---|
| **Можно** | **RealityKit**: `RealityView` (iOS 18+), скелетная анимация из USDZ, `GeometricPin` + `entity.pins.set(named:skeletalJointName:)` (iOS 18+) — шапка, очки, ошейник на кости. `CustomMaterial` (iOS 15+): Metal surface shader и geometry modifier (vertex snapping, PS1/PS2-дрожание, flat/vertex-lighting). `ShaderGraphMaterial` (iOS 18+). **`PostProcessEffect` + `PostProcessEffectContext` (iOS 26)** — пост-процесс прямо в RealityView: рендер в низком разрешении, nearest-апскейл, дизеринг Байера, 15/16-битная палитра, туман. `MeshInstancesComponent` (iOS 26) для травы и предметов. **`RealityRenderer`** (iOS 18+): `updateAndRender(deltaTime:cameraOutput:...)` в свою `MTLTexture`, это офскрин-рендер **кадров для виджетов и острова** (`CIImage`/`CGImage` → PNG в App Group). Старый путь: `ARView.renderCallbacks.postProcess` (iOS 15+). |
| **Нельзя** | Рендер в фоне (см. п. 5). Рендер внутри виджета или Live Activity. Ставку на SceneKit: в доках Apple он deprecated с 26.0 («SceneKit is deprecated, use RealityKit instead»). По WWDC25-288 это soft deprecation без планов удаления, но новых фич не будет. |
| **Хак (цена)** | Если `PostProcessEffect` не даст глубину (на форуме жалобы: depth читается чёрным), туман и аутлайн делать в `CustomMaterial` по расстоянию до камеры. Цена: больше шейдерного кода. Low-res можно сделать честно: `RealityRenderer` рендерит в маленькую текстуру (например 320×240), а SwiftUI показывает её с `.interpolation(.none)`. Цена: свой цикл рендера и жесты руками. |

**Godot или Unity: вердикт — не брать.**
- Godot: официально для iOS-экспорта нужен macOS + Xcode. Есть сторонние CI-обходы (build-ios от mak448a, апрель 2026; ShipThis), то есть ещё одна хрупкая прослойка поверх нашей облачной сборки.
- Unity: тяжёлый рантайм, лицензия, тот же Xcode-проект на выходе.
- Главное: виджеты, Live Activity, Controls, App Intents, уведомления, HealthKit, CMPedometer и CLMonitor пишутся только на Swift. Значит, всё равно два мира плюс мост по App Group, а на бесплатной подписи вес и сложность только мешают.
- RealityKit закрывает задачу целиком: низкополигональный персонаж, кости, шмотки, пост-эффект, офскрин-рендер.

### 7. Голос «как у Тома» и распознавание

| | |
|---|---|
| **Можно** | `AVAudioEngine`: микрофон → запись → воспроизведение через `AVAudioUnitTimePitch` (`pitch` +1000…+1200 центов, `rate` 1.1–1.3) + немного `AVAudioUnitReverb` или `Distortion`. VAD по уровню сигнала: питомец «слушает», пока владелец говорит, и повторяет после паузы. **`SpeechAnalyzer` + `SpeechTranscriber`** (iOS 26, on-device, модели скачивает система) для команд и имени; `DictationTranscriber` — более «диктовочный» вариант. Перед использованием проверять `isAvailable` и `supportedLocales`. Fallback: `SFSpeechRecognizer(locale: ru-RU)` с `requiresOnDeviceRecognition = true`. `FoundationModels` (iOS 26, Apple Intelligence on-device) — разбор смысла фразы, если язык и устройство поддерживаются. Нужны `NSMicrophoneUsageDescription` и `NSSpeechRecognitionUsageDescription`. |
| **Нельзя** | Слушать микрофон из виджета, Live Activity или в фоне без активной аудиосессии. Siri-фразы для запуска: Siri capability недоступна на бесплатном аккаунте. Сами App Shortcuts, по моему выводу, entitlement не требуют, это зонд. |
| **Хак (цена)** | Нет нужды. Если русского нет в `SpeechTranscriber`, используем `SFSpeechRecognizer`; он поддерживает русский on-device. |

---

## Рекомендации для архитектуры

1. **Таргеты:** `PetApp` (SwiftUI + RealityKit) и **одно** расширение `PetWidgets`, где лежат все виджеты, `ActivityConfiguration` и `ControlWidget`. Плюс App Group `group.<id>.pet`. Это 2 App ID, что важно для лимита бесплатного аккаунта. Notification Content/Service Extension не заводить.
2. **Источник правды — `PetState`** (JSON или SQLite в App Group) с **детерминированной моделью времени.** Голод, сон и настроение вычисляются функцией `state(at: Date)` из последнего события и констант, а не тикают таймером. Тогда виджет, остров, уведомления и Windows-клиент показывают одно и то же без пробуждений, а timeline виджета заранее содержит записи «через 2 ч проголодается».
3. **Общий модуль `PetIntents`** (target membership: приложение + расширение): `FeedIntent`, `PetIntent`, `SleepIntent`, `OwnerEventIntent`, `StartIslandIntent`.
   - Все, что трогают остров, делать `LiveActivityIntent`: они выполняются в процессе приложения и могут стартовать и перезапускать активность.
   - Для Команд их отдают через `AppShortcutsProvider`.
4. **Кадры:** приложение в foreground (после смены шмоток или погоды и при каждом открытии) рендерит `RealityRenderer`'ом набор PNG поз × эмоций × размеров (остров ~28–40 pt @3x, виджеты small/medium) **с альфой** и кладёт в App Group. Если пакет большой, через `BGContinuedProcessingTask`. Виджет и Live Activity только показывают готовые PNG, памяти минимум.
5. **Остров:**
   - стартовать при открытии приложения и из контрола «Выпустить ⭐ в остров»;
   - `staleDate` ставить на момент «проголодается», и тогда вид сам переключится на «грустный»;
   - шкалы через `ProgressView(timerInterval:)`, отсчёт до «сна» через `Text(timerInterval:)`;
   - кнопки «покормить» и «погладить» — `LiveActivityIntent` в развёрнутом виде;
   - перезапуск после 8 ч через фоновое действие уведомления или нажатие.
6. **Уведомления:** скользящее окно до ~50 штук, пересчёт при каждом пробуждении. Категории с фоновыми действиями («Покормить», «Погладить», «Ответить»), GIF во вложении, свой звук.
7. **Привычки:** `HealthKit` (сон и шаги) + `CMPedometer` + 1–2 зоны `CLMonitor`, агрегировать при пробуждениях. Плюс страница в приложении «Подключи привычки»: iCloud-ссылки на готовые Команды и пошаговая инструкция для автоматизаций «открыл приложение X», «поставил на зарядку», «выключил будильник».
8. **3D-стиль:** `CustomMaterial` (vertex snap + affine-подобная деформация UV + плоский свет) + `PostProcessEffect` (низкое разрешение, дизеринг, палитра). Ассеты в USDZ из Blender, шмотки через `GeometricPin` на именованные кости.
9. **Голос:** отдельный экран или режим «Слушает» на `AVAudioEngine`. Распознавание через `SpeechTranscriber` с fallback на `SFSpeechRecognizer`.
10. **Задел на iOS 27:** учитывать `isDynamicIslandLimitedInWidth` (ландшафт) и StandBy (`activityBackgroundTint`, `showsWidgetContainerBackground`). Под 26 эти ветки просто не включаются (`if #available`).

---

## Что проверит только сборка-зонд

Минимальное приложение + расширение, подписанное тем же путём, что и боевое (бесплатный Apple ID, sideload). Проверить на iPhone Air:

1. **App Group после переподписи** инструментом sideload: видят ли приложение и расширение один контейнер и переживают ли данные переподпись через 7 дней.
2. **HealthKit на бесплатной подписи**: выдаётся ли capability, работает ли `enableBackgroundDelivery`, нет ли конфликта explicit App ID (форум 834802).
3. **Старт Live Activity из фона через `LiveActivityIntent`** из контрола, из кнопки в острове и из ярлыка Команд, когда приложение выгружено.
4. **Перезапуск через 8 ч** из фонового действия уведомления (`end` + `request` в `didReceive`).
5. **Реальная частота локальных `update`**: сколько проходит на iOS 26 и 27 и как быстро наступает троттлинг.
6. **Шрифт-таймер внутри Live Activity**: работает ли кастомный шрифт с `Text(timerInterval:)` в острове и на экране блокировки, какой fps.
7. **Картинки из App Group в Live Activity и виджете**: загрузка с диска, лимит размера, память расширения (30 МБ).
8. **Liquid Glass**: как выглядят спрайты в «прозрачном» и «тонированном» режимах с `.fullColor` и без.
9. **`.timeSensitive` без entitlement**: игнорируется молча или ломает доставку.
10. **App Shortcuts и автоматизации без Siri capability**: видит ли Команды интенты приложения на бесплатной подписи, запускаются ли «сразу».
11. **CMPedometer и HealthKit из расширения** (в интенте, выполняемом в расширении) или только из приложения.
12. **`RealityRenderer` → PNG**: скорость пакета кадров, работает ли `PostProcessEffect` в офскрин-рендере или только в `RealityView`.
13. **`SpeechTranscriber.supportedLocales`**: есть ли `ru`; скачивается ли модель.
14. **Версия iOS на iPhone Air** (26.x или уже 27) и поведение острова в ландшафте и StandBy.

---

## Источники

Apple, официальная документация (текущие версии на 15.10.2026, получены через JSON-API developer.apple.com):
- Displaying live data with Live Activities — https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities (лимиты 8+4 ч, 4 КБ, 160 pt, старт из фона через LiveActivityIntent, startDate в iOS 26, staleDate, анимации до 2 с)
- Activity.request(attributes:content:pushType:style:alertConfiguration:startDate:) — https://developer.apple.com/documentation/activitykit/activity
- Adding interactivity to widgets and Live Activities — https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities (в каком процессе выполняются интенты)
- Keeping a widget up to date — https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date (40–70 перезагрузок, 5 мин, исключения из бюджета)
- Optimizing your widget for accented rendering mode and Liquid Glass — https://developer.apple.com/documentation/widgetkit/optimizing-your-widget-for-accented-rendering-mode-and-liquid-glass
- Creating controls to perform actions across the system — https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system
- Supported capabilities (iOS) — https://developer.apple.com/help/account/reference/supported-capabilities-ios (колонка «Apple Developer», то есть бесплатный аккаунт: App Groups, HealthKit, Background modes — да; Push, Time Sensitive, Siri, Family Controls, iCloud — нет)
- Declaring your actionable notification types — https://developer.apple.com/documentation/usernotifications/declaring-your-actionable-notification-types
- BGContinuedProcessingTask — https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask
- Preparing your Metal app to run in the background — https://developer.apple.com/documentation/metal/preparing-your-metal-app-to-run-in-the-background
- CMPedometer — https://developer.apple.com/documentation/coremotion/cmpedometer
- CLMonitor — https://developer.apple.com/documentation/corelocation/clmonitor
- SceneKit (deprecatedAt 26.0) — https://developer.apple.com/documentation/scenekit
- RealityRenderer — https://developer.apple.com/documentation/realitykit/realityrenderer
- PostProcessEffect (iOS 26) — https://developer.apple.com/documentation/realitykit/postprocesseffect
- CustomMaterial — https://developer.apple.com/documentation/realitykit/custommaterial
- GeometricPin — https://developer.apple.com/documentation/realitykit/geometricpin
- AVAudioUnitTimePitch — https://developer.apple.com/documentation/avfaudio/avaudiounittimepitch
- SpeechAnalyzer / SpeechTranscriber (iOS 26) — https://developer.apple.com/documentation/speech/speechanalyzer
- Shortcuts: что нового в iOS 26 / macOS 26 (Apple Support 125148) — https://support.apple.com/en-us/125148

Apple, WWDC:
- WWDC25-278 «What's new in widgets» (06.2025) — https://developer.apple.com/videos/play/wwdc2025/278/
- WWDC25-288 (SceneKit → RealityKit, soft deprecation) — https://developer.apple.com/videos/play/wwdc2025/288/
- WWDC26-223 «Live Activities essentials» (06.2026) — https://developer.apple.com/videos/play/wwdc2026/223/ (ландшафт, `isDynamicIslandLimitedInWidth`, StandBy)
- WWDC26-277 «WidgetKit foundations» (06.2026) — https://developer.apple.com/videos/play/wwdc2026/277/ (`systemExtraLargePortrait` на iOS 27)

Apple Developer Forums:
- Троттлинг Live Activity в iOS 18 — https://developer.apple.com/forums/thread/758475 , https://developer.apple.com/forums/thread/758465
- Лимит 64 уведомлений — https://developer.apple.com/forums/thread/811171 , https://developer.apple.com/forums/thread/765490
- Память расширения 30 МБ — https://developer.apple.com/forums/thread/713561 , /733347 , /842805 , /779546
- Серые квадраты в clear-режиме — https://developer.apple.com/forums/thread/809767
- Свои картинки в Controls не показываются — https://developer.apple.com/forums/thread/762618
- Personal team: App Groups и HealthKit, explicit App ID — https://developer.apple.com/forums/thread/834802
- BGAppRefresh на практике — https://developer.apple.com/forums/thread/729824 , /725675
- GPU в фоне только iPad M3+ — https://developer.apple.com/forums/thread/816774 , /801229

Сторонние:
- heise, «Live is not live» (2024) — о троттлинге Live Activities в iOS 18 (heise.de)
- Bryce Bostwick, «Apple's Widget Backdoor» (YouTube) — https://www.youtube.com/watch?v=NdJ_y1c_j_I ; пересказ на Hackaday (hackaday.com)
- David Smith, заметка об анимации обновлений виджетов в iOS 17 (06.11.2023)
- Matthew Cassinelli, автоматизации без подтверждения в iOS 17 (01.08.2023) — https://matthewcassinelli.com
- Fueled о Pixel Pals («clever dev work around Apple's limitations»); отзывы Island Pet в App Store 2024–2025
- Godot: Exporting for iOS (нужны macOS и Xcode) — https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html ; сторонний CI build-ios (mak448a, 04.2026), ShipThis
- Блог про Codex CLI (08.06.2026) утверждает, что SceneKit будет «deprecated в iOS 27». **Не подтверждено** Apple: в доках стоит 26.0 и soft deprecation.
