# 01. Подпись, установка и сборка без Mac и без платного аккаунта

Дата исследования: 15.10.2026. Устройство: iPhone Air, iOS 26.x, ПК на Windows, бесплатный Apple ID.

---

## Вывод одной строкой

Схема «приложение + один WidgetKit-extension + App Group» на бесплатном Apple ID **технически работает**. Для этого нужны 4 условия:
- код сам находит переименованную App Group во время работы;
- push-функции не используются, Live Activity запускается с `pushType: nil`;
- `.ipa` собирается в GitHub Actions на `macos-26` через XcodeGen с ad-hoc подписью и entitlements;
- первая установка и продление идут с ПК через Sideloadly или Impactor.

SideStore (продление на самом телефоне) в октябре 2026 нестабилен. Главный внешний риск прямо сейчас — сломанный вход Apple ID в сайдлоадерах (ошибка -80045 и 503 с 12–15.10.2026).

---

## Детали по пунктам

### 1. Что доступно на бесплатном Apple ID

#### 1.1. Установка приложения с extension

Ставится. Каждый `.appex` получает **свой App ID**: AltStore и SideStore регистрируют `1 + число_extensions` App ID. Это видно в коде `FetchProvisioningProfilesOperation.swift`: `requiredAppIDs = 1 + application.appExtensions.count`.

Bundle ID переписывается так:
- приложение: `<исходный_id>.<TEAMID>`;
- extension: `<исходный_id>.<TEAMID>.<суффикс>`.

В SideStore есть 3 режима обработки extensions:
- «Keep App Extensions (Register App ID for Each Extension)»;
- «Keep app extensions (use main profile)», появился в 0.6.2 (PR #1012). Экономит App ID, но работа виджета в этом режиме не подтверждена;
- «Remove app extensions».

Sideloadly умеет удалять extensions («Remove individual or all app extensions»), по умолчанию оставляет их.

Подтверждённые примеры из сентября 2026, когда виджет-extension работал после сайдлоада:
- MCDuckler/mailcoach-ios: XcodeGen, приложение + виджет, SideStore;
- CedricMillard/testWidget в issue SideStore #1437, бесплатный аккаунт;
- huulanka/hippocampus PR #7: виджет с Control + App Group на бесплатном Personal Team, подписанный через Xcode.

#### 1.2. App Groups

Доступны на бесплатном аккаунте: в таблице Apple в колонке «Apple Developer» стоит галочка. Но сайдлоадер **переименовывает группу**:
- AltStore и SideStore делают `group.<id>` → `group.<id>.<TEAMID>`. Группа создаётся через API с именем «AltStore group …» и привязывается к обоим App ID.
- После переподписи AltStore и SideStore кладут реальный список групп в `Info.plist` под ключ `ALTAppGroups`. Это видно в `ResignAppOperation.swift`.
- Подпись делается **entitlements из профиля**, а не из приложения (AltSign `ALTSigner.mm`). Всё, чего нет в профиле, молча выпадает.
- Какие группы нужны, сайдлоадер **читает из подписи бинарника**. Поэтому `.ipa` из CI должна быть подписана ad-hoc (`codesign -s -` или `ldid -S`) с entitlements, где есть `com.apple.security.application-groups`. Без этого сайдлоадер не узнает о группе.
- Как Sideloadly переименовывает группу, **не проверено**: это закрытый код. Скорее всего тоже добавляет суффикс. Это вопрос для сборки-зонда.

Вывод для кода: нельзя жёстко прописывать ID группы. Нужен резолвер, который пробует группы по очереди и берёт первую, для которой `FileManager.containerURL(forSecurityApplicationGroupIdentifier:) != nil`. Порядок перебора:
1. ID из конфигурации;
2. `ALTAppGroups` из `Bundle.main.infoDictionary`;
3. `ALTAppGroups` родительского приложения (для extension это `../../Info.plist`);
4. `application-groups` из `embedded.mobileprovision`.

Готовая реализация такого резолвера есть в `SharedStore.swift` у mailcoach-ios.

Известные баги SideStore с группами и виджетами:
- **#1437** (08–09.2026, SideStore 0.6.3, iOS 26.6.1, бесплатный аккаунт): виджет не читает `UserDefaults(suiteName:)` группы. Мейнтейнер: «исправлено в nightly». Для уже установленного он советует сделать «resign».
- **#1438**: виджеты показывают нули на 0.6.3 / iOS 26.3.1. Исправлять не будут, предлагают nightly.
- **#1504**: виджета 0.6.4 нет в галерее. Помогли nightly и перезагрузка.
- **#1462** (02.09.2026): `.appex` подписан без `CS_EXECSEG_MAIN_BINARY` и не запускается. Через iloader и Impactor работает.
- **#1467** (iOS 26.6.1, 0.6.4): extension убит с CODESIGNING «Invalid Page». Исправлено в nightly (CodeSignKit 15f95c1, 03.09.2026).

Ещё одна находка: в IncomeMeter PR #9 (28.09.2026) при установке через SideStore группа оказалась `MISSING`. Автор ушёл на Live Activity, которой группа не нужна: данные передаются через `ContentState`.

#### 1.3. Live Activity и Dynamic Island

Отдельного entitlement нет. Нужно только `NSSupportsLiveActivities = YES` в Info.plist приложения. **Работают локально** на Personal Team. Подтверждение — LoopKit/Loop issue #2532 (22.09.2026, iOS 27):
- запрос с `pushType: .token` без `aps-environment` падает с `ActivityInput error 0`;
- с `pushType: nil` всё работает.

Значит, обновлять Live Activity можно только из приложения: пока оно в фоне с Background modes, из App Intent или из `LiveActivityIntent`. Удалённых push-обновлений и push-to-start нет.

Грабля Sideloadly: в FindMyFriends PR #12 (05.09.2026, Sideloadly 0.60, iOS 27) extension определился как `%%1.appex`, а потом установка упала с «bundleVersion missing». Что сделать:
- в Info.plist extension явно прописать `CFBundleExecutable = $(EXECUTABLE_NAME)`;
- там же прописать `CFBundleVersion` и `CFBundleShortVersionString`, совпадающие с приложением.

#### 1.4. Интерактивные виджеты, App Intents, Control Center, Shortcuts

Entitlement не нужен. App Intents, App Shortcuts, `Button(intent:)` и `Toggle(intent:)` в виджете, `ControlWidget` — всё без capability. Capability «Siri» нужна только для старого SiriKit (INIntents), и на бесплатном аккаунте она недоступна.

Подтверждение: hippocampus PR #7 (24.09.2026). На бесплатном Personal Team Control в виджет-extension:
- выполняет intent;
- пишет в shared defaults группы;
- приложение читает это значение.

Оговорка: это проверено подписью через Xcode, а не через SideStore. Сами авторы оставили открытым вопрос «как это поведёт себя с SideStore».

#### 1.5. Остальные API

| API | Нужен платный entitlement? | Что нужно |
|---|---|---|
| CoreMotion (CMPedometer, CMMotionActivity) | Нет | `NSMotionUsageDescription` |
| Локальные уведомления (UNUserNotificationCenter) | Нет | Разрешение от пользователя. `.timeSensitive` недоступен: Time Sensitive Notifications нет на бесплатном аккаунте |
| BGTaskScheduler (BGAppRefresh / BGProcessing) | Нет | Background modes (доступны бесплатно): `fetch` и/или `processing` + `BGTaskSchedulerPermittedIdentifiers` |
| App Intents / Shortcuts / Spotlight | Нет | Ничего |
| Remote push (APNs) | **Да, недоступно** | Включая push для Live Activity |
| iCloud / CloudKit / KVS | **Да, недоступно** | Синхронизацию делать через свой сервер |
| Sign in with Apple, Game Center, In-App Purchase, Wallet, WeatherKit | **Да, недоступно** | |
| HealthKit | Нет, доступно | Если понадобятся шаги из Health |

**Полный список по таблице Apple «Supported capabilities (iOS)»** (developer.apple.com, 2026), колонка «Apple Developer» (бесплатно):

- **Доступно:** App Groups, Background Modes, Data Protection, HealthKit, HomeKit, Inter-App Audio, Keychain Sharing, Maps (без маршрутизации), Wireless Accessory Configuration.
- **Недоступно:** 5G Network Slicing, Access WiFi Information, App Attest, Apple Pay, Associated Domains, AutoFill Credential Provider, ClassKit, Communication Notifications, DriverKit/MIDI, Extended Virtual Addressing, Family Controls, FileProvider Testing, Fonts, Game Center, Group Activities, Head Pose, HealthKit Estimate Recalibration, HLS Interstitial, Hotspot, iCloud (CloudKit, Documents, KVS), ID Verifier, In-App Purchase, Increased Debugging Memory Limit, Journaling Suggestions, Low Latency HLS, Matter, MDM domains, Media Device Discovery, Messages Collaboration, Multipath, NFC Tag Reading, Network Extensions, On Demand Install, Personal VPN, Push to Talk, Push Notifications, Sensitive Content Analysis, Shared with You, Sign in with Apple, SIM Inserted, SiriKit, Spatial Audio, Sustained Execution, Time Sensitive Notifications, Wallet, WeatherKit.

Нюансы:
- SideStore issue #1616 (24.09.2026): у SideStore в `freeFeatures` только `appGroups` и `interAppAudio`. Он выбрасывает даже `increased-memory-limit`, который AltStore 2.3 сохраняет.
- **Файл entitlements должен быть минимальным**: только `com.apple.security.application-groups`. Лишние ключи вроде `aps-environment` или iCloud могут сломать обновление App ID у сайдлоадера.
- Для 3D-рендера (SceneKit/RealityKit) memory-limit не нужен. Но для виджета действует жёсткий системный лимит памяти extension, около 30 МБ. **3D в виджете не рендерить**, только заранее отрисованные картинки.

### 2. Лимиты бесплатного аккаунта

- **3 активных приложения** на устройстве, подписанных бесплатным сертификатом. Считаются **приложения, а не extensions**. Если пользоваться SideStore или AltStore, они **сами занимают 1 из 3 слотов**.
- **10 App ID за скользящие 7 дней.** Каждый extension — отдельный App ID. App ID нельзя удалить: он «истекает» через 7 дней после установки или продления. Ошибки SideStore 1009/3013 означают «лимит App ID».
- **Что значит «1 приложение + 1 extension»:** 2 App ID при каждой установке или продлении с тем же bundle ID. Повторные продления те же ID **не тратят заново**, если bundle ID не меняется. Из 10 ID остаётся 8 на эксперименты.
- В SideStore 0.7.0 nightly есть открытые баги #1632 (03.10.2026) и #1661 (15.10.2026): удалённые extensions **снова регистрируются при refresh** и съедают App ID.
- **Сертификат.** Бесплатных development-сертификатов ограниченное число. Каждый новый инструмент на новом ПК может выпустить свой сертификат и отозвать чужой. iloader и Impactor умеют показывать и отзывать сертификаты и App ID.
- **Срок жизни подписи — 7 дней.** Если не продлить, приложение и виджеты перестают запускаться. Данные в контейнере при этом сохраняются, пока приложение не удалено.

### 3. Sideloadly, AltStore, SideStore и др. на Windows, октябрь 2026

| | Sideloadly 0.70.x | AltStore classic (AltServer 1.8.x) | SideStore 0.6.4 / 0.7.0 nightly | Impactor 2.7.0 | iloader 2.3.8 |
|---|---|---|---|---|---|
| Где идёт подпись | ПК | Телефон, через AltServer на ПК | Телефон | ПК | ПК: ставит SideStore и импортирует IPA |
| Продление без ПК | Нет. Демон продлевает по Wi-Fi, ПК должен быть включён | Нет, нужен AltServer в той же сети | **Да**, через LocalDevVPN/StosVPN + pairing-файл | Нет. Автопродление с ПК | Нет, только установщик |
| Открытый код | Нет | Да | Да | Да | Да |
| iOS 26 | Заявлен «iOS 7 – 26+» | Работает, но всё зависит от AltServer | Хрупко: 0.6.4 помечен «DO NOT USE»; на 26.4+ lockdown-pairing не работает, нужен rppairing; на 26.7 и 27 ошибка DeviceEndpointNotInitialized (#1623) | Поддерживается, 14.10 исправлены заголовки GrandSlam | Поддерживается |
| Вход Apple ID 12–15.10.2026 | Смешанные отчёты, кому-то помог кэш сертификата | Есть сообщения о -80045 | Сломан, фиксы в nightly (PR #1655, #1657, #1660) | v2.7.0 с фиксом | v2.3.8 работает с 2FA через доверенное устройство, SMS 2FA сломана |
| Требования на Windows | iTunes и iCloud с сайта Apple (не из Store), Bonjour для Wi-Fi | iTunes, iCloud | Нужен ПК только для первой установки через iloader | iTunes | iTunes (usbmuxd) |

Известные поломки 2026 года:
- **12–15.10.2026: вход Apple ID.** GSA (gsa.apple.com) отвечает -80045 «This action cannot be completed at this time» и 503 на anisette-данные клиента Android/Pixel. Затронуты SideStore (#1645, #1647, #1652, #1658), iloader (#859, #883, #920, #928) и частично Sideloadly и AltServer. Обход: Windows-anisette (ani.jkcoxson.com, ani2.stikstore.app). Часть аккаунтов не проходит и с ним. iloader 2.3.7 починил -80045, но сломал SMS 2FA. iloader 2.3.8 (15.10) починил 503, но нужен повторный 2FA. Ситуация **ещё меняется**.
- **LocalDevVPN 1.3** сменил IP туннеля на 10.7.1.1, и SideStore перестал видеть устройство (#1460, сентябрь – 11.10.2026). Обходы: переустановить VPN, указать 10.7.0.0/32, перейти на RPPairing.
- **iOS 26.4+**: lockdown-pairing через VPN не поддерживается, нужен RPPairing (#1656, 14.10.2026). На iOS 26.6.2 lockdownd через LocalDevVPN рвёт соединение, это видно и у Sideloadly (aircards #10, 07.10.2026).
- **iOS 26.4+, ошибка 27 в SideStore**: решается обновлением до nightly.
- Подпись extensions в SideStore (#1462, #1467) исправлена только в nightly.

**Рекомендация по инструменту:**
1. **Основной: Sideloadly** (или Impactor как открытая альтернатива с автопродлением). Подпись и продление с ПК по USB или Wi-Fi.
   - Плюсы: не тратит слот на SideStore, так что доступно 3 из 3; меньше багов с подписью extensions; не нужен VPN на телефоне.
   - Минус: ПК должен хотя бы раз в 7 дней быть включён и в одной сети с телефоном. Можно и просто подключать кабель раз в неделю.
2. **Опционально позже: SideStore nightly**, когда стабилизируются вход Apple ID и RPPairing на iOS 26.x. Устанавливать через iloader.

**Установка Sideloadly на Windows** (выполняет пользователь сам, этот агент ничего не ставил):
1. Удалить iTunes и iCloud из Microsoft Store, если они стоят. Поставить **версии с сайта Apple** (apple.com/itunes/download/win64, iCloud for Windows web-installer). Bonjour идёт вместе с ними.
2. Скачать Sideloadly с **sideloadly.io**, только с официального сайта, и установить.
3. Подключить iPhone кабелем, на телефоне нажать «Доверять». Sideloadly должен увидеть устройство.
4. Ввести Apple ID **в окне Sideloadly**. Лучше отдельный Apple ID под сайдлоад, а не основной. 2FA — через доверенное устройство.
5. Перетащить `.ipa` и в Advanced options проверить:
   - extensions **не** удаляются;
   - «Bundle ID» не трогать;
   - включить «Enable automatic re-sign» / «Wi-Fi», если нужно автопродление.
6. На iPhone: Настройки → Основные → VPN и управление устройством → доверять профилю разработчика.
7. Настройки → Конфиденциальность и безопасность → **Режим разработчика → Вкл**, затем перезагрузка. Без этого на iOS 16+ приложения с development-подписью не запускаются.
8. Для продления по Wi-Fi: один раз включить в iTunes «Синхронизировать с этим iPhone по Wi-Fi», после этого демон Sideloadly продлевает сам.

### 4. Сборка без Mac

**Генератор проекта: XcodeGen.** Версия 2.46.0, 16.07.2026. Один `project.yml`, ставится через `brew install xcodegen` прямо на раннере. Tuist 4.x мощнее, но у него больше движущихся частей и он продвигает своё облако. Для одного приложения с одним extension он избыточен.

Важное в `project.yml` (по образцу mailcoach-ios):
- target `Pet` с типом `application` и target `PetWidget` с типом `app-extension`;
- у extension: `NSExtension.NSExtensionPointIdentifier = com.apple.widgetkit-extension`, `APPLICATION_EXTENSION_API_ONLY = YES`, `SKIP_INSTALL = YES`;
- у приложения extension указан в `dependencies` с `embed: true`, чтобы он попал в `PlugIns/`;
- `CODE_SIGNING_ALLOWED = NO`, `CODE_SIGN_STYLE = Manual`, `CODE_SIGN_ENTITLEMENTS` у каждого target;
- в Info.plist приложения: `NSSupportsLiveActivities`, `UIBackgroundModes [fetch, processing]`, `BGTaskSchedulerPermittedIdentifiers`, `NSMotionUsageDescription`;
- в Info.plist extension: явные `CFBundleExecutable`, `CFBundleVersion` и `CFBundleShortVersionString`, такие же, как у приложения;
- номер сборки — UTC-метка, например `$(date -u +%Y%m%d%H%M)`. Так сайдлоадер видит, что версия обновилась;
- `IPHONEOS_DEPLOYMENT_TARGET`: 18.0 или 26.0. Нужно для Control widget (iOS 18+) и `LiveActivityIntent` (iOS 17+).

**Раннеры GitHub Actions** (runner-images, образ 20260907):
- `macos-26` / `macos-26-arm64`: macOS 26.6.2, **Xcode 26.6 по умолчанию** (17F113). Также есть 26.5, 26.4.1, 26.3, 26.2, 26.1.1 и 26.0.1. iOS SDK 26.0–26.5.
- `macos-15`: Xcode 16.4 по умолчанию, плюс 26.0.1–26.3.
- Xcode 27 есть в public preview (runner-images #14404).
- **Брать `macos-26` и явно выбирать Xcode**: `sudo xcode-select -s /Applications/Xcode_26.6.app`. На Apple Developer Forums (тред 795881) пишут, что неподписанная сборка может незаметно взять старый SDK.

**Схема workflow** (по образцу пайплайнов SideStore nightly.yml и mailcoach-ios build.yml):

```yaml
name: build-ipa
on: { push: { branches: [main] }, workflow_dispatch: {} }
jobs:
  ipa:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - run: sudo xcode-select -s /Applications/Xcode_26.6.app
      - run: brew install xcodegen ldid
      - run: xcodegen generate
      - run: |
          xcodebuild -project Pet.xcodeproj -scheme Pet -configuration Release \
            -sdk iphoneos -destination 'generic/platform=iOS' \
            -derivedDataPath build \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
      - name: ad-hoc sign with entitlements (inner first)
        run: |
          APP=build/Build/Products/Release-iphoneos/Pet.app
          codesign --force --sign - --entitlements Config/PetWidget.entitlements "$APP/PlugIns/PetWidget.appex"
          codesign --force --sign - --entitlements Config/Pet.entitlements "$APP"
          codesign -d --entitlements - "$APP" | grep application-groups
          codesign -d --entitlements - "$APP/PlugIns/PetWidget.appex" | grep application-groups
      - run: |
          mkdir -p out/Payload && cp -R build/Build/Products/Release-iphoneos/Pet.app out/Payload/
          cd out && zip -qry Pet.ipa Payload
      - uses: actions/upload-artifact@v4
        with: { name: Pet-ipa, path: out/Pet.ipa }
```

Вместо `codesign -s -` можно использовать `ldid -S<entitlements>`, так делает SideStore. Подписывать сначала `.appex`, потом `.app`.

**Переподписывают ли сайдлоадеры appex?** Да. AltStore и SideStore выпускают профиль на каждый extension и подписывают каждый бандл (`ALTSigner.mm`). Sideloadly подписывает вложенные бандлы. Баги подписи extension есть только у SideStore 0.6.x (#1462, #1467), в nightly они исправлены.

**Минуты:**
- **Публичный репозиторий**: стандартные раннеры GitHub, включая macOS, бесплатны и без лимита минут. Это проще всего, но код и `.ipa` будут публичными.
- **Приватный репозиторий**: GitHub Free даёт 2000 минут в месяц. macOS с 01.01.2026 стоит $0.062 за минуту (было $0.08), то есть примерно в 10 раз дороже Linux. На деле это **около 200 macOS-минут в месяц**. Сборка XcodeGen + маленький проект занимает 5–10 минут, значит 20–40 сборок в месяц. Множитель лучше проверить в Billing.
- **Codemagic**: 500 бесплатных минут на M2 в месяц на личном аккаунте, 1 параллельная сборка. Хороший запасной вариант для приватного кода.
- **Bitrise**: бесплатный Hobby-план существует, но его условия в 2026 **не проверены**. Не рекомендую: та же задача, больше настройки.

### 5. Риски

| Риск | Вероятность | Что делать |
|---|---|---|
| Сломанный вход Apple ID в сайдлоадерах (как 12–15.10.2026) | Высокая, бывает несколько раз в год | Держать 2 инструмента (Sideloadly + Impactor или iloader). Не продлевать в последний день: начинать на 5–6-й день. Обновлять инструменты |
| iOS-обновление ломает pairing/VPN (26.4, 26.6.x, 26.7, 27) | Высокая для SideStore, ниже для USB | Основной канал — USB или Wi-Fi с ПК. Не ставить x.0 сразу |
| Подпись истекла, приложение не запускается | Гарантирована через 7 дней | Автопродление Sideloadly, напоминание в календаре. Данные не теряются, пока приложение не удалено |
| Отзыв сертификата (другой инструмент или ПК выпустил новый) | Средняя | Один Apple ID — один основной инструмент. Ревизию сертификатов делать через iloader или Impactor |
| Кончились 10 App ID (эксперименты, смена bundle ID, баг SideStore #1632/#1661) | Средняя | Bundle ID **не менять** после первой установки. Не ставить чужие IPA с этого Apple ID. Ждать 7 дней |
| Конфликт bundle ID с чужим приложением | Низкая | Уникальный префикс, например `com.vadim.pet`. Сайдлоадеры к тому же добавляют `.TEAMID` |
| Потеря данных при смене bundle ID или App Group (другой инструмент даст другой суффикс группы) | Средняя | Резолвер группы во время работы. Основные данные держать в контейнере **приложения**, в группе только снимок для виджета. Экспорт и бэкап на сервер синхронизации |
| Apple ужесточит бесплатную подпись | Низкая или средняя | План Б: платный аккаунт ($99), архитектура не меняется |

---

## Рекомендуемая схема

1. **Код**: GitHub, лучше публичный репозиторий ради бесплатных минут. Если нужен приватный, бюджета около 200 macOS-минут хватит, запас — Codemagic. Генерация проекта через **XcodeGen**.
2. **Targets**: `Pet` (app) + `PetWidget` (один WidgetKit extension). В extension собраны:
   - home- и lock-screen-виджеты;
   - `ControlWidget`;
   - `ActivityConfiguration` для Live Activity и Dynamic Island.
3. **Entitlements**: только `com.apple.security.application-groups = [group.com.vadim.pet]` у обоих target. Больше ничего.
4. **Код**:
   - резолвер App Group во время работы (`ALTAppGroups` → `embedded.mobileprovision` → настроенный ID) с проверкой `containerURL`;
   - если группы нет, виджет показывает заглушку, а Live Activity работает через `ContentState`;
   - `Activity.request(..., pushType: nil)`;
   - интерактив через `AppIntent` / `LiveActivityIntent`;
   - фоновые задачи через `BGAppRefreshTask`;
   - уведомления только локальные, без `.timeSensitive`.
5. **CI**: `macos-26`, Xcode 26.6, сборка без подписи → ad-hoc `codesign` с entitlements (сначала appex, потом app) → проверка grep → `Payload/` → zip → `.ipa` в artifacts или Releases.
6. **Установка**: Sideloadly на Windows по USB при первой установке, дальше демон по Wi-Fi.
   - Займёт 2 App ID и 1 из 3 слотов.
   - Режим разработчика и доверие профилю на телефоне.
   - Запасной инструмент: Impactor (открытый, автопродление с ПК).
   - SideStore nightly — позже и только как эксперимент.
7. **Перед реальной разработкой — сборка-зонд** (минимальное приложение + виджет + Control + Live Activity + запись в группу). Она отвечает на вопросы ниже.

---

## Открытые вопросы, которые проверит только сборка-зонд на телефоне

1. Какой **bundle ID и какую App Group** выдаёт Sideloadly 0.70.x? Кладёт ли он `ALTAppGroups` в Info.plist, или группу видно только в `embedded.mobileprovision`?
2. **Видит ли виджет общую группу** (`UserDefaults(suiteName:)` и файлы в `containerURL`) после установки через Sideloadly, Impactor и SideStore nightly? Учесть баг #1437.
3. Запускается ли **Live Activity с `pushType: nil`** на iPhone Air (iOS 26.x) и обновляется ли из `LiveActivityIntent` и фоновой задачи?
4. Работают ли **Control Center widget** и `Button(intent:)` в виджете после сайдлоада, а не после Xcode?
5. Сохраняются ли **данные в контейнере группы и приложения** после продления подписи и после переустановки тем же инструментом? А при смене инструмента?
6. Работает ли режим SideStore «use main profile» (1 App ID на всё) для виджета, или он ломает extension?
7. Насколько стабильно **автопродление Sideloadly по Wi-Fi** на этом iPhone Air с iOS 26.x? Учесть разрывы lockdownd, как в aircards #10.
8. Входит ли **Apple ID пользователя** в Sideloadly после инцидента -80045/503 и проходит ли 2FA через доверенное устройство?
9. Вписывается ли **3D-сцена** приложения в фоновое выполнение, и не убивает ли система extension виджета по памяти, если в нём только картинки?
10. Срабатывают ли `BGAppRefreshTask` и CMPedometer (запрос шагов за период) у development-подписанного приложения так же, как у App Store-приложения?

---

## Источники со ссылками

**Apple**
- Supported capabilities (iOS), таблица ADP / ADEP / Apple Developer, проверено 15.10.2026: https://developer.apple.com/help/account/reference/supported-capabilities-ios
- Apple Developer Forums, тред о неподписанных сборках и SDK: https://developer.apple.com/forums/thread/795881

**Код AltStore и SideStore (логика переподписи)**
- AltStore `FetchProvisioningProfilesOperation.swift` (bundle ID `.TEAMID`, App ID на каждый extension, `group.X.TEAMID`): https://github.com/altstoreio/AltStore/blob/master/AltStore/Operations/FetchProvisioningProfilesOperation.swift
- AltStore `ResignAppOperation.swift` (`ALTAppGroups` в Info.plist): https://github.com/altstoreio/AltStore/blob/master/AltStore/Operations/ResignAppOperation.swift
- AltSign `ALTSigner.mm` (подпись entitlements профиля): https://github.com/rileytestut/AltSign
- Документация SideStore, коды ошибок (1009/3013/3014/3015, 7 дней, 10 App ID): https://docs.sidestore.io
- Релизы SideStore (0.6.2 от 01.07.2025, 0.6.3 от мая 2026, 0.6.4 от 09.09.2026 «DO NOT USE», 0.7.0-alpha от 15.09.2026, nightly 13.10.2026): https://github.com/SideStore/SideStore/releases

**Issues и PR SideStore 2026**
- #1437, виджет не видит группу (20.08–06.09.2026): https://github.com/SideStore/SideStore/issues/1437
- #1438, виджеты показывают 0: https://github.com/SideStore/SideStore/issues/1438
- #1460, LocalDevVPN 1.3 / 10.7.1.1 (02.09–11.10.2026): https://github.com/SideStore/SideStore/issues/1460
- #1462, appex без CS_EXECSEG_MAIN_BINARY (02.09.2026): https://github.com/SideStore/SideStore/issues/1462
- #1467, «Invalid Page» у extension (iOS 26.6.1, 09.2026): https://github.com/SideStore/SideStore/issues/1467
- #1504, виджета нет в галерее: https://github.com/SideStore/SideStore/issues/1504
- #1616, на free выпадает memory-limit (24.09.2026): https://github.com/SideStore/SideStore/issues/1616
- #1623, DeviceEndpointNotInitialized на iOS 26.7/27 (26.09.2026): https://github.com/SideStore/SideStore/issues/1623
- #1632 и #1661, удалённые extensions регистрируются снова (03.10 и 15.10.2026): https://github.com/SideStore/SideStore/issues/1632 и https://github.com/SideStore/SideStore/issues/1661
- #1645 / #1647 / #1652 / #1658, -80045 / 503 при входе (12–15.10.2026), фиксы в PR #1655 / #1657 / #1660: https://github.com/SideStore/SideStore/issues/1652
- #1656, на iOS 26.4+ нужен RPPairing (14.10.2026): https://github.com/SideStore/SideStore/issues/1656
- PR #1012, режим «use main profile» для extensions: https://github.com/SideStore/SideStore/pull/1012

**Другие инструменты**
- iloader (релизы 2.3.7 от 13.10.2026 и 2.3.8 от 15.10.2026, issues #859/#883/#920/#928): https://github.com/nab138/iloader
- Impactor (v2.6.5 от 28.09.2026, v2.7.0 от 14.10.2026): https://github.com/claration/impactor
- Sideloadly (0.70.x, «iOS 7 – 26+», удаление extensions, Wi-Fi автопродление): https://sideloadly.io
- aircards #10, lockdownd рвётся на iOS 26.6.2 (07.10.2026): см. поиск GitHub «aircards issue 10 lockdownd»

**Подтверждения работы на бесплатной подписи**
- LoopKit/Loop #2532, Live Activity на Personal Team работает с `pushType: nil` (22.09.2026): https://github.com/LoopKit/Loop/issues/2532
- huulanka/hippocampus PR #7, Control + App Group на free Personal Team (24.09.2026): https://github.com/huulanka/hippocampus/pull/7
- nadolc/IncomeMeter PR #9, Live Activity без App Group через SideStore (28.09.2026): https://github.com/nadolc/IncomeMeter/pull/9
- Chayce22315/FindMyFriends PR #12, Sideloadly и `CFBundleExecutable` у Live Activity extension (05.09.2026): https://github.com/Chayce22315/FindMyFriends/pull/12
- CedricMillard/testWidget, тестовый виджет с группой: https://github.com/CedricMillard/testWidget

**Сборка**
- MCDuckler/mailcoach-ios: XcodeGen, app + WidgetKit, CI без подписи → ad-hoc codesign → ipa, резолвер группы `SharedStore.swift` (коммиты от 30.09.2026): https://github.com/MCDuckler/mailcoach-ios
- Пайплайн SideStore (`nightly.yml` на `macos-26`, `Makefile` с `ldid -S`): https://github.com/SideStore/SideStore/tree/develop/.github/workflows
- runner-images, образ macos-26-arm64 (20260907), Xcode 26.6 по умолчанию с 21.07.2026 (#14344), Xcode 27 preview (#14404): https://github.com/actions/runner-images
- XcodeGen 2.46.0 (16.07.2026): https://github.com/yonaskolb/XcodeGen/releases
- Tuist: https://github.com/tuist/tuist/releases
- Тарифы GitHub Actions (2000 минут на Free, macOS $0.062 за минуту с 01.01.2026): https://docs.github.com/en/billing/managing-billing-for-your-products/managing-billing-for-github-actions/about-billing-for-github-actions
- Тарифы Codemagic (500 бесплатных минут M2 в месяц): https://codemagic.io/pricing/
