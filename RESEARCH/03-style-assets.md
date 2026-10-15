# 03. Стиль и пайплайн ассетов «Питомца»

Дата: 15.10.2026. Исследование, никаких установок не делалось. Мудборд: `RESEARCH\moodboard\` (16 картинок + `moodboard.json`).

## Вывод

1. **Стиль держится на текстурах, а не на полигонах.** Все 6 рефов владельца (Nintendogs с Luigi-кепкой, котёнок в костюме лягушки, Petz-бигль, пудель, Sims 2 Pets) — это 500–3000 треугольников + **фото/рисованная текстура шерсти 128–256 px с билинейным «мылом»**. Бесплатные low-poly звери (Quaternius и пр.) почти все flat-color — их **придётся перетекстуривать**. Это основной объём арт-работы, а не моделинг.
2. **Скелет для собак есть бесплатно (CC0).** Quaternius Ultimate Animated Animals (Shiba, Husky, Wolf и др.) — один общий квадропед-скелет с одинаковыми именами костей, 13 анимаций (idle ×3, walk, gallop, eat, attack, jump, hit, death). Это готовое «семейство quadruped». **Нет sit и sleep** — их придётся анимировать руками в Blender (позы простые, 1–2 дня).
3. **Риск №1 (анимации квадропедов) закрывается не AI, а переиспользованием скелета.** Из AI-сервисов только Tripo документированно ригает квадропедов, но из пресетов у него только `quadruped:walk`. Meshy ригает «humanoid/quadruped» без описания костей. Mixamo/AccuRIG — только двуногие (для «тунг-тунг-сахура» подходят).
4. **Рендер:** RealityKit (SceneKit с WWDC25 в режиме только критичных фиксов). Ретро-эффекты: `CustomMaterial` (геометрический модификатор — vertex snapping; surface-шейдер — квантование цвета, туман) + `PostProcessEffect` (iOS 26, низкое разрешение + дизеринг). Affine-текстуры — теоретически через `custom_attribute` (трюк uv·w / w), но на мелком питомце лучше не включать.
5. **Конвертация на Windows возможна:** Blender CLI → USDZ (арматура + анимация). Ограничение USD: «один файл — одна анимация». Решение: все клипы подряд на одной таймлайн-дорожке + `clips.json` с диапазонами, нарезка в коде (`AnimationView(trimStart:trimEnd:)`). Reality Converter / Reality Composer Pro — только Mac (нужны лишь для проверки на облачном Mac).
6. **Рекомендую направление B «Petz/Sims 2 Pets PS2»** с ползунком «ретро-фильтр» (до C). Оно ближе всего к рефам 2–4, 6 и лучше всего показывает прогрессию «лохматый → красивый».

---

## 1. Живые примеры стиля (12)

| # | Что | Ссылка | Что в нём хорошего для нас |
|---|---|---|---|
| 1 | **Haunted PS1** (сообщество + Demo Disc 2020/2021/Flipside Frights) | https://hauntedps1.itch.io/demodisc2020 | Эталон «простая комната + туман + тёплая лампа + низкое разрешение». Комнаты собираются из 10–20 объектов. Мудборд 16. |
| 2 | **godot-psx-style-demo** (MenacingMecha, MIT) | https://github.com/MenacingMecha/godot-psx-style-demo · https://menacingmecha.itch.io/godot-psx-style-demo | Полный набор: vertex snapping, affine, глубина цвета + дизеринг, туман. Самый читаемый код для портирования в Metal. Мудборд 13. |
| 3 | **PS1/PSX Visuals — GD4 Port** (scolastico, MIT) | https://www.godotengine.org/asset-library/asset/4687 | Глобальные uniform-ы (одна ручка «силы ретро» на всю сцену) — так и нужно сделать ползунок. |
| 4 | **Ultimate Retro Shader Collection** (Zorochase, MIT) | https://zorochase.itch.io/ultimate-retro-shader-collection-for-godot | Отдельные шейдеры PS1 / N64 / «мягкий» PS2 — видно разницу между эпохами. |
| 5 | **Bonvikt — PSX-звери** (Black Cat PSX, French Bulldog PSX, PS1 Dog) | https://sketchfab.com/3d-models/black-cat-psx-62416ff46cef45599c51dc9bc0b83b43 | 466–770 треугольников + фото-текстура низкого разрешения — ровно «мыльный» вид рефов. Мудборд 07, 08. |
| 6 | **McSteeg — PSX Animals: Cats** (платно, $4.99) | https://mcsteeg.itch.io/psx-animals-cats | Самый близкий к Petz набор: 9 анимаций (2 idle, бег, **sit + sit loop**, «месит лапами», испуг, потягивание, **умывание**), PSD с узорами шерсти + 5 окрасов. Мудборд 14 (баннер Farm Pack того же автора). |
| 7 | **DreamNoms — low-poly звери** (Sketchfab, CC BY) | https://sketchfab.com/3d-models/stylized-low-poly-german-shepherd-18d8fbe184c5448283762893b6ea9752 | 852 треугольника, 13 анимаций, в т.ч. **лечь** и **почесаться** — хороший образец набора поведения. Мудборд 09, 10. |
| 8 | **Quaternius Ultimate Animated Animals** (CC0) | https://quaternius.com/packs/ultimateanimatedanimals.html | Общий скелет на 12 зверей; база семейства quadruped. Мудборд 01, 02. |
| 9 | **Kenney Cube Pets** (CC0, обновлён в марте 2026) | https://kenney.nl/assets/cube-pets | Образец семейства «blob»: куб-тело, 1–3 кости, анимации squash & stretch. Мудборд 12. |
| 10 | **Dog Petting Simulator** (Studio Cacti, демо) | https://studiocacti.itch.io/dog-petting-simulator-demo | Яркий уютный low-poly двор, миски, забор — «светлая» альтернатива; механика глажки. Мудборд 15. |
| 11 | **PSX Shaders Pro** (Daniel Ilett; Unity URP / Godot, платно) | https://danielilett.itch.io/psx-shaders-pro-for-unity-urp | Хорошо описанный список настроек: разрешение, snapping, affine, цветовая глубина, CRT. Как чек-лист фич. |
| 12 | **Nintendogs / Petz / Catz / Sims 2 Pets** | рефы владельца `refs\1–6.png` | Коммерческие игры — **только внутренний референс**. Шапка поверх модели, клетчатый пол, фото-шерсть, абсурдные костюмы. |

## 2. Ретро-шейдеры и рендер

### Техники и что из них реально на iOS (RealityKit)

| Техника | Как делается классически | В RealityKit / Metal | Оценка |
|---|---|---|---|
| Низкое внутреннее разрешение + nearest-апскейл | Рендер в маленький таргет, upscale без фильтра | (а) **iOS 26 `PostProcessEffect`** на `RealityView` (`content.renderingEffects.customPostProcessing`): compute-шейдер даунсемплит и пишет в target блоками N×N. (б) Дешёвый трюк для `ARView`/UIKit: `contentScaleFactor = 0.25…0.5` + `layer.magnificationFilter = .nearest` (проверить на устройстве). | Да |
| Vertex snapping / jitter | Квантование позиции в clip/screen space | Geometry modifier `CustomMaterial`: посчитать позицию через `uniforms().model_to_world()/world_to_view()/view_to_projection()`, округлить к сетке экрана, вернуть разницу через `set_model_position_offset`. Проще: квантовать в view space. | Да |
| Affine texture mapping | `noperspective` UV | Прямого `noperspective` нет. Трюк: в модификаторе положить `(uv·w, w)` в `set_custom_attribute`, в surface-шейдере взять `uv = a.xy / a.z`. Перспективная интерполяция `uv·w` и `w` даёт ровно аффинный UV. Не проверено на устройстве. | Возможно; для питомца не нужно, только пол |
| Квантование цвета + дизеринг | 15-бит цвет + матрица Байера 4×4 | Post-process (iOS 26) на весь кадр или в surface-шейдере на материал (`unlit`-модель, чтобы свет не «размыл» квантование) | Да |
| Vertex (Gouraud) lighting | Свет в вершинах | В `unlit` + свой Ламберт в модификаторе → `custom_attribute` → surface. Или обычный `lit` с одним направленным светом + IBL низкого качества — визуально почти то же. | Да |
| Туман | Линейный по глубине | В surface-шейдере по view-depth (`unlit`) или в post-process. На форуме Apple была жалоба на чёрный `sourceDepthTexture` в post-process — делать туман в материале. | Да |
| Текстуры 64–256 px | Маленькие текстуры + bilinear (PS2) / nearest (PS1/DS) | `MaterialParameters.Texture(resource, sampler:)` с `MTLSamplerDescriptor` (min/mag nearest или linear). Mipmaps выключить для «хрустящего» вида. | Да |

Важно:
- Шейдеры `CustomMaterial` компилируются в `default.metallib` приложения в Xcode — это делает облачный Mac / CI, на Windows не нужно.
- Reality Composer Pro / ShaderGraph — только Mac. Писать шейдеры кодом на Metal, а не графом.
- Не использовать SceneKit: soft-deprecated с WWDC25 (сессия 288 «Bring your SceneKit project to RealityKit»).

### Открытые реализации для портирования
- **Godot (GLSL-подобный):**
  - MenacingMecha/godot-psx-style-demo (MIT): vertex snap + affine + dither.
  - scolastico psx_visuals_gd4 (MIT).
  - Zorochase collection (MIT).
  - fcidade psx-godot-shader: https://store.godotengine.org/asset/fcidade/psx-godot-shader/
- **Unity (HLSL):**
  - PSX Shader4Unity: https://kelvymcampos.itch.io/psx-shader4unity (бесплатно, лицензию смотреть в репо).
  - PSXEffects: https://discussions.unity.com/t/psxeffects-playstation-one-graphics-in-unity/720976
- **Apple:**
  - https://developer.apple.com/documentation/realitykit/custommaterial
  - https://developer.apple.com/documentation/realitykit/postprocesseffect
  - Пример compute post-process: https://developer.apple.com/documentation/realitykit/implementing-postprocess-effects-using-metal-compute-functions

Все формулы (snap, Bayer 4×4, квантование `floor(c*levels)/levels`) переносятся в Metal один-в-один, это 20–40 строк.

## 3. Бесплатные модели собак и кошек (кандидаты)

Треугольники и кости проверены по GLB-заголовкам (poly.pizza) и Sketchfab API. Почти везде вместо текстур flat-цвета. Под рефы нужна перетекстурка в 128–256 px.

| # | Модель | Ссылка | Лицензия | Tris | Риг / анимации | Подходит под стиль |
|---|---|---|---|---|---|---|
| 1 | Quaternius **Shiba Inu** | https://poly.pizza/m/y4wdQpg767 | CC0 | 1812 | 46 костей, общий скелет Ultimate. Attack, Death, Eating, Gallop, Gallop_Jump, Idle, Idle_2, Idle_2_HeadLow, HitReact ×2, Jump_ToIdle, Walk | ★★★ база собаки, перетекстурить |
| 2 | Quaternius **Husky** | https://poly.pizza/m/wcWiuEqwzq | CC0 | 1822 | 49 костей, тот же набор | ★★★ |
| 3 | Quaternius **Wolf** | https://poly.pizza/m/P1gU3Qkr9r | CC0 | 1928 | 51 кость, тот же набор | ★★ (донор анимаций) |
| 4 | Quaternius **German Shepherd** | https://poly.pizza/m/Hssa6NPc6W | CC-BY 3.0 | 4898 | 50 костей, Run вместо Gallop; есть атлас-текстура | ★★ |
| 5 | Quaternius **Dog** (Animated Animals) | https://poly.pizza/m/2kUk0QqpCg | CC0 | 3604 | 16 костей (Body/Head/Tail/4 ноги). Idle, Idle_Eating, Walk, Run, Jump, Headbutt, Death | ★★ проще риг, проще одежда |
| 6 | Quaternius **Cat** (Animated Animals) | https://poly.pizza/m/qKICY6xla2 | CC0 | 2448 | тот же скелет 16 костей и анимации, что у Dog | ★★★ кот с тем же скелетом, что пёс #5 |
| 7 | J-Toastie **Cat** | https://poly.pizza/m/DJ9rpAhrh3 | CC-BY 3.0 | 1856 | 22 кости с понятными именами (Head, Neck, tail1-4, лапы), только IdleCat; есть albedo | ★★★ хорошая сетка кошки |
| 8 | Bonvikt **Black Cat PSX** | https://sketchfab.com/3d-models/black-cat-psx-62416ff46cef45599c51dc9bc0b83b43 | CC BY 4.0 | 466 | риг, 4 анимации | ★★★ уже «PS-вид» |
| 9 | Bonvikt **French Bulldog PSX** | https://sketchfab.com/3d-models/french-bulldog-psx-647fa9e3f53b4898826ef398f0a9f6dd | CC BY 4.0 | 770 | риг | ★★★ уже «PS-вид» |
| 10 | DreamNoms **Stylized Low Poly German Shepherd** | https://sketchfab.com/3d-models/stylized-low-poly-german-shepherd-18d8fbe184c5448283762893b6ea9752 | CC BY 4.0 | 852 | 13 анимаций: бег, **лечь**, почесаться, прыжок… | ★★ |
| 11 | DreamNoms **Chubby Pallas Cat** | https://sketchfab.com/3d-models/chubby-pallas-cat-rigged-and-animated-9f9122ec0c2340c5a5ce9db4aef8b3f7 | CC BY 4.0 | 934 | риг, 3 анимации | ★★ «лохматая» стадия |
| 12 | hello142567 **Cute Dog (animated)** | https://sketchfab.com/3d-models/cute-dog-animated-96ffe7e6a59243f88bfb9055a2bfaaea | CC BY 4.0 | 1950 | 24 анимации (самый большой набор) | ★★ мультяшнее рефов |
| 13 | DreamNoms **Tuxedo Cat Animated 2.0** | https://sketchfab.com/3d-models/tuxedo-cat-animated-20-783fcb78b55b4394a212c2b6392e1113 | CC BY 4.0 | 6376 | 6 анимаций, вращаемые глаза | ★ тяжеловат |
| 14 | baydinman **Cartoon Cat** | https://sketchfab.com/3d-models/cartoon-cat-4a738eaed9d34547a3f5a705a0e37c6a | CC BY 4.0 | 4126 | 25 анимаций | ★ мультяшный |
| 15 | micaelsampaio **Stylized Dog / Cat Low Poly** | https://sketchfab.com/3d-models/stylized-dog-low-poly-7dcc84a595d641fdba37c9d10b551577 | CC BY 4.0 (автор просит не перепродавать) | 978 / 888 | 4 анимации у собаки | ★★ |
| 16 | Vr-cvantorium **cat Rigged** | https://sketchfab.com/3d-models/cat-rigged-eccebebd5a60484eaa49036f8a4b6ed7 | CC BY 4.0 | 794 | 3 анимации | ★★ |
| 17 | Статика Poly by Google: Beagle / Puppy / Kitten | https://poly.pizza/m/0BnDT3T1wTE · https://poly.pizza/m/3nFLBC3aXen · https://poly.pizza/m/dBJgGEu5bHW | CC-BY 3.0 | 650–712 | без рига | ★★ форма «щенок» под перенос весов |
| 18 | Kenney **Cube Pets** | https://kenney.nl/assets/cube-pets | CC0 | малые | анимированы | семейство blob |

Платно и дёшево:
- McSteeg PSX Animals: Cats ($4.99). Есть sit/умывание/потягивание. Коммерческое использование можно, распространять как ассет нельзя. Пака собак у автора нет.
- Fab «Animated CAT & DOG – 3D LOW POLY» (idle/sit/walk/run/eat/bark; лицензию смотреть): https://www.fab.com/listings/10aec0b5-73fd-4816-85f9-39e8caba3859

**Не брать:** AnimalMesh3D Puppy, Silent Hill cat от vinrax — это CC **NonCommercial**.

Квадропед-сокеты на скелете Quaternius Ultimate (проверено по именам костей):

| Сокет | Кость |
|---|---|
| head | `Head` |
| neck | `Neck1` |
| back | `Torso2` |
| tail | `Tail1` |
| paw_fl / paw_fr | `FrontLowerLeg.L/.R` |
| paw_bl / paw_br | `BackLowerLeg.L/.R` |
| уши | `Ear1..4.L/R` |

Возможно, в Ultimate-паке есть **Fox**: это по памяти, при скачивании пака проверить. Пропорции лисы ближе к кошке, поэтому кошку можно было бы сделать на её скелете. Если лисы нет, подогнать кошачью сетку под скелет Shiba. Тогда пёс и кот попадут в одно семейство и будут делить одежду.

## 4. AI-генерация 3D (состояние на осень 2026)

| Сервис | Версия 2026 | Бесплатно | Лицензия результата (free) | Low-poly / ретопология | Авто-риг | Текстуры |
|---|---|---|---|---|---|---|
| **Meshy** | Meshy-6 (янв. 2026) | 100 кредитов/мес (генерация ≈20; по отзывам на free скачивание ограничено) | **CC BY 4.0** на free; Pro $20/мес — частная | «Topology Mesh» / Low Poly: пресеты 3K/10K/30K/100K или своё число, quad/tri; Remesh | humanoid **и** quadruped, авто-определение; имена костей не документированы. Animate: 500+ пресетов, в основном гуманоидные | хорошие PBR, но «современные», под PS2 перепекать |
| **Tripo** | Rig v2.5-20260210 | ~200–300 кредитов/мес | **CC BY 4.0**, модели публичные; Pro $19.90 | smart low-poly, quad | **biped, quadruped, hexapod, octopod, avian, serpentine, aquatic**; Rig Check = 0 кредитов, риг = 25; кости в нотации `tripo` или `mixamo` | хорошие |
| **Hunyuan3D** (Tencent) | 3.0/3.1 Pro (закрытые, API); открытые веса 2.0/2.1/Omni | 20 генераций в день на 3d.hunyuanglobal.com | открытые веса — Tencent Hunyuan Community License (есть ограничения по регионам: проверить для Сербии) | Smart Topology tri/quad, Polygen 1.5 даёт quad-сетки | нет своего | очень хорошие |
| **Rodin / Hyper3D** | Gen-2.5 (Fast ≤20K граней) | 10 кредитов, скачивание ≈40 → фактически платно | платно | Quad-режим, задаётся число полигонов | нет | лучшие среди всех, но не наш стиль |
| **TRELLIS.2** (Microsoft) | 4B, дек. 2025 | бесплатно локально | **MIT** | нет, нужна своя децимация | нет | PBR (O-Voxel) |
| **Stable Fast 3D / SPAR3D** (Stability) | SF3D 2024, SPAR3D 2025 | бесплатно локально | Stability Community License: бесплатно при выручке < $1M/год | уже лёгкие сетки, UV-развёртка | нет | средние |

Замечания:
- TRELLIS.2 требует Linux и NVIDIA ≥24 ГБ — на этом ПК не пойдёт.
- Free-результаты Meshy и Tripo под CC BY 4.0. Для личного приложения это нормально, но в «Титрах» нужна строка атрибуции.

**Вывод по AI:** использовать только как «болванку формы» (например, тунг-тунг-сахур, костюмы, мебель).
- Не доверять AI-ригу квадропеда: у Tripo из пресетов только walk, у Meshy нет описания костей.
- Для питомца лучше перенести веса с готового скелета Quaternius (Data Transfer в Blender). Тогда работают все уже готовые анимации.

Пайплайн AI-болванки:
1. Концепт-картинка: спереди или в 3/4, нейтральная поза, лапы раздельно.
2. Генерация в Meshy/Tripo с low-poly 3K.
3. Blender:
   - `Decimate` (Collapse, до 1.5–3k tris) или Instant Meshes / QuadriFlow (`Remesh → QuadriFlow`) для аккуратной сетки.
   - Новая UV (Smart UV Project).
   - **Bake** диффуза с хай-поли в 256×256 (Cycles → Bake → Diffuse color, selected-to-active).
   - Пройтись кистью: размыть, добавить «шерстяной» шум.
4. Риг:
   - Квадропед: подогнать скелет Quaternius и `Data Transfer → Vertex Groups` (или Robust Weight Transfer), поправить веса.
   - Двуногий: Mixamo / AccuRIG / Tripo biped.

## 5. Скелеты и анимации (главный риск)

### Инструменты авто-рига
| Инструмент | Квадропеды | Цена | Комментарий |
|---|---|---|---|
| **Mixamo** | нет | бесплатно | Только гуманоид. Для «тунг-тунг-сахура» (полено с руками-ногами) подойдёт: маркеры ставятся на любой меш с 2 руками и 2 ногами. |
| **AccuRIG 2.0** (Reallusion) | нет (Reallusion в 2023 сказали «не планируем») | бесплатно, экспорт нужен бесплатный аккаунт ActorCore | Двуногие + доступ к 4500+ анимациям ActorCore. |
| **Tripo Rig** | **да** (quadruped и ещё 5 типов) | 25 кредитов | Анимаций для квадропеда мало (`preset:quadruped:walk`). |
| **Meshy Rig/Animate** | заявлено (авто-определение) | кредиты | Имена костей и квадропед-пресеты не задокументированы; рекомендуют T/A-позу. |
| **Anything World** | да (кошки, собаки и пр.) | free tier неясен | Плагины для Maya/3ds Max и API; авто-риг + анимации животных. Можно попробовать на 1–2 моделях. |
| **Rigify** (встроен в Blender) | **да**: готовые метариги Cat, Wolf, Horse | бесплатно | Надёжный ручной путь. Для экспорта нужен «game-ready» слой: только deform-кости (`only_deform_bones`). |
| **Auto-Rig Pro** | да (пресеты dog/horse, Smart) | платный аддон Blender | Хорош для экспорта в игры (чистая иерархия). |
| **UniRig** (Tsinghua + VAST) | да, обучен на людях и животных (Rig-XL, 14k моделей) | код MIT, данные и веса — свои лицензии | Требует NVIDIA GPU, исследовательский уровень. |

### Семейства скелетов (предложение)

Один **контракт сокетов** на все семейства. Это дополнительные кости (или пустышки) с фиксированными именами поверх «родного» скелета модели. Для каждой модели — маленький `rig_map.json` «сокет → кость», чтобы не переименовывать чужие кости.

| Сокет | quadruped (пёс/кот) | biped (тунг-тунг-сахур, гуманоиды) | blob (Kenney-кубы, слайм) |
|---|---|---|---|
| `socket_root` | Body/Root | Hips | Root |
| `socket_head` (шапки) | Head | Head | Body (верх) |
| `socket_face` (очки, маски) | Head + смещение | Head + смещение | Body (перед) |
| `socket_neck` (ошейник, бант) | Neck1 | Neck | — |
| `socket_back` (рюкзак, крылья, седло) | Torso2 | Spine2 | Body |
| `socket_tail` (бантик на хвост) | Tail1 | — | — |
| `socket_paw_fl/fr/bl/br` (тапки) | Front/BackLowerLeg | hand_l/r, foot_l/r | — |

Правила:
- **Шапка — одна на все семейства.** Жёсткий меш крепится к `socket_head`. Для каждой модели в `rig_map.json` хранится `{offset, rotation, scale}`. Лягушачья шапка с рефа 6 и кепка Луиджи с рефа 5 — это именно такой случай.
- **Одежда на тело — внутри семейства.** Скиннится на скелет семейства: квадропед Quaternius Ultimate или его 16-костный вариант. Хранится в том же файле, что и питомец, и включается через `isEnabled`. Тапки — 4 жёстких меша на `socket_paw_*`.
- **RealityKit не умеет «прицепить entity к кости».** Нужна своя `System`:
  - Каждый кадр берёт `ModelEntity.jointNames` и `jointTransforms`.
  - Накапливает трансформы по иерархии до нужного сокета.
  - Ставит transform аксессуару.
  - Это известный приём, 30–50 строк.
- **Прогрессия «голый и рваный → красивый»:**
  1. Смена текстуры: колтуны и грязь → чистая шерсть, 3–4 ступени.
  2. Отдельный скиннутый меш «клочков шерсти» (hair cards), который «стригут».
  3. Blend shapes для худобы и пушистости (USD blend shapes экспортируются из Blender).
  4. Аксессуары.

### Анимации, которых не хватает
Нужно: idle, walk, **sit**, **sleep**, eat. Плюс «радость», «просит», «грустит», «моется».
- Есть у Quaternius: idle, walk, gallop, eat, jump.
- **Нет sit, sleep, lie.** Это почти статичные позы с переходом и «дыханием»: 2–4 ключа плюс цикл. Делаются руками в Blender за часы, а не дни.
- Ретро-приём: ключи с шагом 2–3 кадра и интерполяция `Constant` (stepped 10–12 fps). Выглядит «по-PS2» и экономит работу.
- Доноры идей (CC BY, можно ретаргетнуть): DreamNoms German Shepherd (лечь, почесаться), Cute Dog (24 клипа). Платно: McSteeg Cats (sit, умывание).
- Ретаргет между скелетами в Blender: встроенного удобного нет. Варианты: Rokoko Retargeting (бесплатный аддон, нужен аккаунт), Auto-Rig Pro Remap (платно), Copy Rotation + bake. Проще не ретаргетить и держать всех на одном скелете.

### Стандарты
- **VRM 0.x/1.0** — стандарт для гуманоидов (обязательные humanoid-кости, spring bones для ушей и хвостов). На iOS читается **VRMKit** (MIT, модуль VRMRealityKit, iOS 18+). Для тунг-тунг-сахура можно использовать гуманоидную карту костей VRM как именование семейства biped. Для квадропедов стандарта нет — фиксируем свой контракт сокетов (таблица выше).
- Quaternius и Mixamo уже дают предсказуемые имена (`mixamorig:Head` и т.п.). Tripo умеет `mixamo`-нотацию для biped.

## 6. Конвертация glTF/GLB → USDZ

| Путь | Windows? | Скелет + анимация | Несколько клипов |
|---|---|---|---|
| **Blender CLI** (`blender -b file.blend --python export.py`), `bpy.ops.wm.usd_export(filepath="pet.usdz", export_animation=True, export_armatures=True, export_shapekeys=True, only_deform_bones=True)`. Расширение `.usdz` пакует сразу. | **да** | да: UsdSkel с 4.0 (PR #111931), импорт rest-позы улучшен в 4.5; у команды уже работает Blender 5.2 | **один клип** (активная action / таймлайн) |
| Apple **Reality Converter** | нет, только Mac | да | нет |
| Apple **usdzconvert** (Python-скрипты USDPython) | официально Mac; на Windows теоретически через `pip usd-core` (не проверялось, ставить ничего не стали) | частично | нет |
| **Reality Composer Pro 3** | Mac | да | **да**: AnimationLibraryComponent, нарезка клипов «ножницами», анимации переиспользуются между entity с одинаковым скелетом |

Проблема «одна анимация на USD». Официального фикса нет: ответ Apple на форуме в августе 2025 — https://developer.apple.com/forums/thread/797061. Три обхода:
1. **Рекомендую: одна дорожка + `clips.json`.**
   - В Blender NLA все клипы ставятся подряд с паузой в 1 кадр. Экспорт одним USDZ.
   - Рядом лежит `clips.json`: `{"idle":[0,60,"loop"],"walk":[61,90,"loop"],"sit_in":[91,110,"once"],...}`.
   - В Swift: `availableAnimations[0].definition` → `AnimationView(source:, trimStart:, trimEnd:)` → `AnimationResource.generate(with:)`.
   - Полностью собирается на Windows скриптом.
2. Один USDZ на клип. Клипы грузятся как отдельные entity, и их анимации проигрываются на основной модели (пути суставов должны совпадать — проверить). Минус: N файлов на питомца.
3. **Без USDZ: GLB прямо в приложение.**
   - VRMKit / VRMRealityKit (MIT, iOS 18+) рендерит glTF/GLB со скиннингом, всеми анимациями и spring bones.
   - GLTFKit2 (MIT) хорошо парсит, но поддержка RealityKit не очевидна.
   - Плюс: один файл, все клипы, конвертация не нужна. Минус: сторонняя зависимость и свои материалы. Держать как запасной путь.

Грабли:
- Грузить через `Entity(named:)` / `Entity.load`, **не** `ModelEntity.loadModel`, иначе анимации теряются.
- Blender пишет материалы как `UsdPreviewSurface`. Сэмплер (nearest) и ретро-шейдер всё равно задавать в коде через `CustomMaterial`.
- Перед экспортом применять все модификаторы, кроме Armature. Bendy bones не экспортируются. Не больше 4 весов на вершину.
- Проверять результат на облачном Mac или устройстве (Reality Converter / `usdchecker`).

---

## Три направления стиля (на выбор владельцу)

### A. «Nintendogs / DS-открытка» — светло и мило
- Светлая комната и **клетчатый пол** (реф 5, 6).
- Пастельные цвета, мягкий тёплый свет.
- Фото-шерсть 128 px с bilinear.
- Без jitter и дизеринга; разрешение ×0.5 «для мыла».
- Камера низко, «на уровне носа», питомец крупно.
- Абсурд — через шапки и костюмы, а не через рендер.

Картинки: рефы 4, 5, 6; мудборд **06** (щенок Poly), **10** (пушистый манул), **15** (светлый двор), **12** (как выглядят blob-зверьки в той же гамме).

### B. «Petz / Sims 2 Pets PS2» — уютно-реалистично (рекомендую)
- Более реалистичные пропорции и **фото-текстуры шерсти 256 px с пятнами и окрасами**. PSD-слои окрасов — как у McSteeg.
- Комнаты с обоями, деревом, ковром. Тёплая лампа, лёгкий туман по углам.
- Vertex lighting, квантование цвета до ~5 бит на канал, очень лёгкий дизеринг, разрешение ×0.5.
- Лучше всего показывает прогрессию «колтуны и грязь → чистая блестящая шерсть».

Картинки: рефы 2, 3, 4; мудборд **07, 08** (PSX-коты и собаки на фото-текстуре), **14** («мыльная» шерсть McSteeg), **16** (простая комната, тёплый свет), **09** (набор поз).

### C. «Haunted-cute PS1» — мем и абсурд
- Разрешение ×0.25–0.33, **vertex jitter**, дизеринг Байера, палитра 256 цветов, густой туман, affine на полу.
- Тунг-тунг-сахур, «щенок посреди хоррор-коридора» (реф 1).
- Ярко, но криво и смешно. Хорошо как режим и пасхалка, плохо как основной (устаёт глаз).

Картинки: реф 1; мудборд **13** (эталон шейдера), **16** (комната-хоррор), **07** (кот с горящими глазами), **01/03** (flat-color звери под таким фильтром будут выглядеть именно так).

**Предложение:** B как основа. Глобальный ползунок «Ретро» 0…1 (B → C) в настройках одной uniform-переменной: разрешение, сила snapping, число цветов. Режим C — разблокируемый «ретро-телевизор».

## Рекомендуемый пайплайн ассетов

Бюджет на питомца:
- 1.5–3k треугольников, ≤50 костей.
- 1 атлас 256×256 (голова 128 + тело 128 по площади) + 3–4 варианта «ухоженности».
- Аксессуар: 50–300 треугольников, 64–128 px.

1. **База скелета (раз и навсегда).**
   - Quaternius Ultimate Animated Animals (CC0): Shiba или Husky → «пёс»; «кот» — на Fox, если он есть в паке, иначе подогнать под скелет Shiba. Альтернатива: пара Dog + Cat с общим 16-костным скелетом.
   - Добавить кости-сокеты `socket_*`, записать `rig_map.json`.
   - Семейство biped: Mixamo или AccuRIG на тунг-тунг-сахура, переименовать по таблице сокетов.
   - Семейство blob: 2–3 кости.
2. **Форма.**
   - Править сетку Quaternius под щенячьи пропорции: большая голова, короткие лапы. Веса сохраняются.
   - Или AI-болванка (Meshy/Tripo, low-poly 3K) → Decimate/QuadriFlow → Data Transfer весов со скелета-базы.
3. **Текстура (главная работа).**
   - Развёртка в один атлас. Фото-шерсть (свои фото, CC0-текстуры) или запечь с AI-модели, потом даунскейл до 256 с блюром.
   - Варианты: `scruffy` / `ok` / `clean` / `groomed`. Окрасы — отдельные PSD-слои.
4. **Анимации.**
   - Взять idle/walk/eat/jump у Quaternius. Дорисовать sit, sleep, lie, beg, happy, sad, wash (stepped 12 fps).
   - Всё подряд на одной NLA-дорожке + `clips.json`.
5. **Аксессуары.**
   - Шапки — жёсткие меши на `socket_head` с таблицей смещений на модель.
   - Костюмы — скиннутые меши семейства в том же .blend, включаются флагом.
6. **Экспорт на Windows.** `blender -b pet.blend --python export_usdz.py` → `pet.usdz` + `clips.json` + `rig_map.json`. Один скрипт на все модели. Лог: треугольники, кости, размер.
7. **iOS.**
   - `Entity(named:)` → нарезка клипов по `clips.json`.
   - `CustomMaterial` (unlit + snapping + квантование + туман, сэмплер nearest/linear по направлению).
   - Post-process на iOS 26 (низкое разрешение + дизеринг).
   - Своя `System` для сокетов.
8. **Проверка.** Облачный Mac / CI: `usdchecker`, сборка, скриншот сцены. Запасной путь при проблемах с USDZ — GLB через VRMKit.

Атрибуции для экрана «Титры»: CC0 не требует, но Quaternius и Kenney поблагодарить; все CC BY (Sketchfab, J-Toastie, Poly by Google, free-результаты Meshy/Tripo) — обязательно с автором и ссылкой.

## Источники

**Стиль и шейдеры**
- https://hauntedps1.itch.io/demodisc2020 · https://hauntedps1.itch.io/demodisc2021
- https://www.pcgamer.com/uk/inside-the-next-indie-frontier-ps1-style-horror-games/
- https://github.com/MenacingMecha/godot-psx-style-demo · https://menacingmecha.itch.io/godot-psx-style-demo
- https://www.godotengine.org/asset-library/asset/4687
- https://zorochase.itch.io/ultimate-retro-shader-collection-for-godot
- https://store.godotengine.org/asset/fcidade/psx-godot-shader/
- https://danielilett.itch.io/retro-shaders-pro-for-godot · https://danielilett.itch.io/psx-shaders-pro-for-unity-urp
- https://kelvymcampos.itch.io/psx-shader4unity · https://discussions.unity.com/t/psxeffects-playstation-one-graphics-in-unity/720976
- https://studiocacti.itch.io/dog-petting-simulator-demo
- https://kenney.nl/assets/cube-pets · https://opengameart.org/node/185352

**Apple / RealityKit**
- https://developer.apple.com/documentation/realitykit/custommaterial
- https://developer.apple.com/documentation/realitykit/postprocesseffect
- https://developer.apple.com/documentation/realitykit/implementing-postprocess-effects-using-metal-compute-functions
- https://developer.apple.com/documentation/realitykit/bringing-your-scenekit-projects-to-realitykit
- https://developer.apple.com/forums/thread/797061 (несколько анимаций в USDZ)
- https://developer.apple.com/forums/thread/720152 (geometry modifier)

**Модели**
- https://quaternius.com/packs/ultimateanimatedanimals.html
- poly.pizza: https://poly.pizza/m/y4wdQpg767 · /wcWiuEqwzq · /P1gU3Qkr9r · /Hssa6NPc6W · /2kUk0QqpCg · /qKICY6xla2 · /2f54vbV0In · /1gXKv15ik8 · /DJ9rpAhrh3 · /aT17TtLWOL · /0BnDT3T1wTE · /3nFLBC3aXen · /dBJgGEu5bHW · /4dXgbKLHD9 · /9bqPCxOyrk · /YvVobPlTlQ · /ovFy5UldDq
- Sketchfab: ссылки в таблице раздела 3 (данные — https://api.sketchfab.com/v3/models/<uid>)
- https://mcsteeg.itch.io/psx-animals-cats
- https://www.fab.com/listings/10aec0b5-73fd-4816-85f9-39e8caba3859
- https://opengameart.org/content/animated-animales-low-poly

**AI 3D и риг**
- Meshy:
  - https://docs.meshy.ai/en/webapp/guides/3d-model/rigging
  - https://docs.meshy.ai/en/webapp/guides/animate
  - https://docs.meshy.ai/en/webapp/pricing
  - https://www.meshy.ai/tutorials/make-low-poly-3d-models
  - https://docs.meshy.ai/en/webapp/guides/3d-model/remesh
- Tripo:
  - https://developers.tripo3d.com/en/models/rig
  - https://developers.tripo3d.com/en/docs/animations-retarget
  - https://docs.comfy.org/built-in-nodes/TripoRetargetNode
  - https://www.costbench.com/software/ai-3d-generation/tripo-ai/free-plan/
- Hunyuan3D:
  - https://www.tencent.com/en-us/articles/2202235.html
  - https://help.scenario.com/articles/5967392966-hunyuan-3d-models-the-essentials
- Rodin / Hyper3D:
  - https://help.scenario.com/en/articles/rodin-hyper3d-models-the-essentials/
  - https://costbench.com/software/ai-3d-generation/rodin-hyper3d/
- TRELLIS.2:
  - https://huggingface.co/microsoft/TRELLIS.2-4B
  - https://comfyui-wiki.com/en/news/2025-12-18-microsoft-trellis2-3d-generation
- Stability (SF3D, SPAR3D):
  - https://stability.ai/license
  - https://huggingface.co/stabilityai/stable-fast-3d
- AccuRIG:
  - https://80.lv/articles/reallusion-launches-free-rigging-tool-accurig-2-0
  - https://forum.reallusion.com/523069/Animals
- Anything World: https://anything.world/blog/rigged-ready-to-rumble
- UniRig: https://www.skills.sh/akillness/jeo-skills/unirig (вторичный источник; проверить LICENSE в репозитории)

**Конвертация**
- https://docs.blender.org/manual/en/4.1/files/import_export/usd.html
- https://projects.blender.org/blender/blender/pulls/111931
- https://developer.blender.org/docs/release_notes/4.5/pipeline_assets_io/
- VRMKit (tattn, MIT, VRMRealityKit) и GLTFKit2 (warrenm, MIT) — GitHub.

Не проверено руками (пометка для следующего шага):
- точные имена параметров `usd_export` в Blender 5.2;
- трюк affine через `custom_attribute`;
- `contentScaleFactor` + nearest для `ARView`;
- проигрывание клипа из другого USDZ на основной модели;
- лимиты free у Anything World.
