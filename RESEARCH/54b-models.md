# Волна 54b: свои модели → готовые кандидаты (исследование, 01.11.2026)

Только исследование: в сборку ничего не попало, решения за Вадимом. Миску, мячик (Poly by Google) и пса
(Quaternius) не трогал.

- Лист превью: `C:\Users\ryanc\pet-assets\candidates\wave54b\sheet.png`. Слева в красной рамке «сейчас» (кадр из
  снимков CI ui-99 / ui-51), справа кандидаты, синяя рамка = рекомендация.
- Скачанное: `C:\Users\ryanc\pet-assets\candidates\wave54b\<группа>__<кандидат>\`. В каждой папке model.glb,
  source.json (автор, лицензия, ссылка), preview.png и info.json (треугольники, вес, текстуры, габариты).
  Целые наборы Kenney лежат в `_kenney_<набор>\`.
- Инструменты (вне папки скачанного): `C:\Users\ryanc\pet-assets\tools\wave54b\`.
  - pp.py: поиск poly.pizza.
  - dl.py: скачивание GLB.
  - kenney.py / kpick.py: наборы Kenney.
  - r54b.py: рендер в Blender 5.2, Workbench.
  - render_all.py.
  - sheet54b.py + sheet54b.json: лист превью.
  - table54b.py: таблица по info.json.
- Цифры треугольников и веса посчитаны Blender'ом по скачанным файлам, а не взяты со страниц.
- У Kenney City Kit Suburban, Holiday и Food текстура `Textures/colormap.png` (512 px, 11–13 КБ) лежит рядом с GLB
  и в «КБ» не входит.

## 1. Инвентаризация своих моделей и процедурной геометрии

| Что | Где в коде | Как выглядит | Оценка |
|---|---|---|---|
| Раннер: дерево | `App/RunnerScene.swift:568` `sideProp("tree")` | куб-ствол + 2 зелёных шара | слабо |
| Раннер: куст | там же, `bush` | 2 слипшихся шара | слабо |
| Раннер: домики A/B/C | там же, `houseA/B/C` | коробка, плоская плита-крыша, плашки-окна | слабо |
| Раннер: фонарь | там же, `lamp` | столб + шар | слабо |
| Раннер: забор | там же, `fence` | белые бруски | слабо |
| Раннер: ящик | `App/RunnerScene.swift:508` `obstacle` crate | 2 гладкие коробки стопкой | слабо |
| Раннер: скамейка | там же, bench | 2 бруска на чёрных ножках | слабо |
| Раннер: клумба | там же, flowerbed | коричневая коробка + 4 цветных шара | слабо |
| Раннер: голуби | там же, pigeons | шары + коробка | слабо |
| Раннер: лужа | там же, puddle | плоский голубой диск | нормально (так и должно быть) |
| Раннер: косточка-монета | `App/RunnerScene.swift:555` `bone()` | золотой брусок + 4 шара | слабо / нормально: читается, но грубо |
| Раннер: дорога, трава, биомы | `RunnerScene.swift` ~425 | плоские тайлы | нормально |
| Находки прогулки | `App/PetRoom.swift:418` `findProp` | палка (цилиндр + сучок), шишка (сплюснутая сфера + куб), носок (3 бруска), лист (плоский брусок + черешок), камешек (сплюснутая сфера) | слабо |
| Комната: стены, пол-каркас | `App/PetRoom.swift:95` `room()` | плоскости, пол — текстура ambientCG | нормально |
| Комната: окно, полка (база) | `PetRoom.swift:253` `baseWindow`, `:307` `baseShelf` | рамы из брусков | нормально |
| Кухня по уровням | `App/RoomDecor.swift:168` `kitchen` | холодильник из коробок, бункер-кормушка (ур. 2), полка и колпак (ур. 3) | нормально |
| Ванна по уровням | `RoomDecor.swift:224` `bath` | овальный цилиндр на ножках, джакузи, спа с уточкой, свечи, полотенце | нормально / слабо (ванна — цилиндр) |
| Окно с видом двора и будкой | `RoomDecor.swift:279` `window`, `:355` `kennelHouse` | плоские плашки внутри окна (2.5D) | нормально, стиль «картинки» |
| Лежанка, балдахин, игровой угол, полки | `RoomDecor.swift:402` `bed`, `:453` `canopy`, `:497` `play`, `:681` `shelf` | примитивы, матовые | нормально |
| Сезонный декор | `App/SeasonDecor.swift:40–` (снеговик, тюльпаны, подсолнух, тыква) | YardArtModel ~0,2 м, плоские нормали | нормально |
| Станции и ярусы двора, районы | `App/YardModels.swift:188` (YardArtModel), `:439` `station`, `:736` `mill`, `:905` `garden`; `App/YardDistrictArt.swift` | дата-модели ≤400 треуг. на станцию, бюджет считают тесты, собирается в Linux | нормально, менять дорого |
| Вещи на псе | `Shared/WearMesh.swift` (262–628) | скиннинг под кости пса | нормально, менять дорого (нужен риг) |
| Заглушка пса | `App/PetStage.swift` ~785 | примитивы, только если usdz не загрузился | не трогать |

**Самые слабые 8.** Все в раннере: там примитивы видно крупно и в движении (см. снимки ui-99).
1. Домики.
2. Ящик.
3. Скамейка.
4. Куст.
5. Дерево.
6. Забор.
7. Клумба.
8. Голуби.

Ещё кандидаты подобраны для косточки, фонаря, находок прогулки, ванны, холодильника и сезонного декора.

## 2. Кандидаты

Источники: poly.pizza (Quaternius, Kay/Isa Lousberg = KayKit, Poly by Google и другие авторы) и kenney.nl
(наборы Nature, Furniture, Holiday, Food, City Kit Suburban, все CC0). Поиск на poly.pizza под конец отвечал
429/502/503, поэтому остальное добрано из наборов Kenney.

Бюджет: ≤2000 треуг., текстура ≤512 px или цвета материала, файл ≤300 КБ. Все кандидаты в бюджет треугольников
и веса влезают. Атласы Kay/Isa — 1024 px: перед сборкой их нужно ужать до 512.

### 2.1 Дерево (раннер)
| Кандидат | Треуг. | Файл | Лицензия | Страница | Плюсы / минусы |
|---|---|---|---|---|---|
| `1tree__a-quaternius` Tree, Quaternius | 1810 | 98 КБ, цвета | CC0 | https://poly.pizza/m/9nvGuZlbpE | красивое, автор пса / тяжёлое для повторов вдоль дороги, 5,6 м |
| `1tree__b-google` Tree, Poly by Google | 157 | 5 КБ, текст. 256 | CC-BY 3.0 | https://poly.pizza/m/6pwiq7hSrHr | лёгкое / нужна подпись, масштаб ×500 |
| `1tree__c-bittman-pine` Pine Tree, Danni Bittman | 264 | 20 КБ, цвета | CC-BY 3.0 | https://poly.pizza/m/2Qo-fmVKuSG | ёлка для зимнего биома / подпись |
| `1tree__d-kenney-suburban` tree-large | 42 | 5 КБ, colormap 512 | CC0 | https://kenney.nl/assets/city-kit-suburban | один стиль с домиками / очень простое |
| `1tree__e-kenney-nature` tree_default | 114 | 9 КБ, цвета | CC0 | https://kenney.nl/assets/nature-kit | **рекомендую**: лёгкое, читается, без текстуры |

### 2.2 Куст
| Кандидат | Треуг. | Файл | Лицензия | Страница | Плюсы / минусы |
|---|---|---|---|---|---|
| `1bush__a-quaternius` Bush, Quaternius | 364 | 20 КБ, цвета | CC0 | https://poly.pizza/m/92EytlU1El | **рекомендую**: круглый куст, как сейчас по силуэту / тёмно-зелёный, осветлить материал |
| `1bush__b-isa` Bush, Isa Lousberg | 180 | 26 КБ, текст. 1024 | CC0 | https://poly.pizza/m/I5KhMKZKju | мягкий / атлас ужать до 512 |
| `1bush__c-quaternius-berries` Bush with Berries | 795 | 44 КБ, цвета | CC0 | https://poly.pizza/m/TSbIxkDtxF | вариант для разнообразия / тяжелее |
| `1bush__d-kenney-nature` plant_bushDetailed | 104 | 9 КБ, цвета | CC0 | https://kenney.nl/assets/nature-kit | лёгкий / это листья-розетка, а не куст |
| `1bush__e-kenney-simple` plant_bush | 32 | 4 КБ, цвета | CC0 | https://kenney.nl/assets/nature-kit | минимум / слишком плоский |

### 2.3 Домики
| Кандидат | Треуг. | Файл | Лицензия | Страница | Плюсы / минусы |
|---|---|---|---|---|---|
| `1house__a-quaternius` House | 1028 | 56 КБ, цвета | CC0 | https://poly.pizza/m/L7h0SjZX2K | автор пса / средневековая хижина — не к улице |
| `1house__b-google` House | 1272 | 117 КБ, цвета, 49 мешей | CC-BY 3.0 | https://poly.pizza/m/6PGyqELX8M- | классический домик / подпись, масштаб ~117 м, 49 мешей |
| `1house__c-kenney-a` building-type-a | 1174 | 96 КБ, colormap 512 | CC0 | https://kenney.nl/assets/city-kit-suburban | **рекомендую** (вместе с c и f — три разных дома одного стиля) |
| `1house__d-kenney-c` building-type-c | 1196 | 97 КБ | CC0 | там же | второй дом набора |
| `1house__e-kenney-f` building-type-f | 1616 | 135 КБ | CC0 | там же | крупный, для парка / самый тяжёлый |

### 2.4 Фонарь
| Кандидат | Треуг. | Файл | Лицензия | Страница | Плюсы / минусы |
|---|---|---|---|---|---|
| `1lamp__a-quaternius` Street Light | 324 | 10 КБ, цвета | CC0 | https://poly.pizza/m/nFwrlcLvM5 | **рекомендую**: чистый силуэт / 5,6 м, ужать |
| `1lamp__b-kay` Streetlight, Kay Lousberg | 176 | 28 КБ, текст. 1024 | CC0 | https://poly.pizza/m/vPFSLYh6sg | похож / атлас ужать |
| `1lamp__c-isa-lantern` Street Lantern | 424 | 36 КБ, текст. 1024 | CC0 | https://poly.pizza/m/Zp1b44poac | парковый фонарь / атлас |
| `1lamp__d-kenney-lantern` lantern (Holiday) | 172 | 17 КБ, colormap 512 | CC0 | https://kenney.nl/assets/holiday-kit | тёплый «старинный» / из праздничного набора |

### 2.5 Забор
| Кандидат | Треуг. | Файл | Лицензия | Страница | Плюсы / минусы |
|---|---|---|---|---|---|
| `1fence__a-quaternius` Fence | 212 | 12 КБ, цвета | CC0 | https://poly.pizza/m/r0n40F7FKx | **рекомендую**: низкий деревянный, стыкуется в ленту |
| `1fence__b-kay` Fence (Halloween) | 380 | 42 КБ, текст. 1024 | CC0 | https://poly.pizza/m/aE3GIx8jIH | кованый / мрачный, атлас |
| `1fence__c-kenney` Fence Fortified | 276 | 17 КБ, цвета | CC0 | https://poly.pizza/m/9FQPNr0sdJ | доски / высокий, «крепость» |
| `1fence__d-kenney-suburban` fence | 88 | 9 КБ, colormap | CC0 | https://kenney.nl/assets/city-kit-suburban | один стиль с домами / коричневая плита |
| `1fence__e-kenney-low` fence-low | 180 | 18 КБ, colormap | CC0 | там же | лёгкий / почти не виден издали |

### 2.6 Ящик (препятствие)
| Кандидат | Треуг. | Файл | Лицензия | Страница | Плюсы / минусы |
|---|---|---|---|---|---|
| `2crate__a-quaternius` Cube Crate | 264 | 12 КБ, цвета | CC0 | https://poly.pizza/m/YAghI6GBls | **рекомендую**: ящик с распорками, стопку 2 шт. оставить |
| `2crate__b-kay` Crate (открытый) | 132 | 31 КБ, текст. 1024 | CC0 | https://poly.pizza/m/yCBoU0iyOk | / открытый — хуже как стена |
| `2crate__c-voyage-fruit` Fruit Crate, BlenderVoyage | 196 | 15 КБ, цвета | CC0 | https://poly.pizza/m/aXulVWHOeV | реечный / низкий |
| `2crate__d-kenney-box` cardboardBoxClosed | 60 | 5 КБ, цвета | CC0 | https://kenney.nl/assets/furniture-kit | картонная коробка, есть в наборе комнаты / почти как сейчас |

### 2.7 Скамейка
| Кандидат | Треуг. | Файл | Лицензия | Страница | Плюсы / минусы |
|---|---|---|---|---|---|
| `2bench__a-quaternius` Bench | 376 | 21 КБ, цвета | CC0 | https://poly.pizza/m/jLxjFxFRpw | **рекомендую**: парковая, автор пса |
| `2bench__b-google` Bench | 168 | 23 КБ, цвета | CC-BY 3.0 | https://poly.pizza/m/2EvQDFgG1H3 | дерево + металл / подпись, масштаб ~500 км |
| `2bench__c-amitay` Bench, Ev Amitay | 288 | 21 КБ, цвета | CC-BY 3.0 | https://poly.pizza/m/dOSjmdmKaxi | / подпись |
| `2bench__d-kenney-holiday` bench | 160 | 15 КБ, colormap | CC0 | https://kenney.nl/assets/holiday-kit | яркая / мультяшнее остального |

### 2.8 Клумба
| Кандидат | Треуг. | Файл | Лицензия | Страница | Плюсы / минусы |
|---|---|---|---|---|---|
| `2bed__a-jtoastie-planter` Planter & Bushes, J-Toastie | 622 | 51 КБ, цвета | CC-BY 3.0 | https://poly.pizza/m/wn85Xr9lM3 | длинная, как препятствие / подпись |
| `2bed__b-isa-pot` Medium Pot | 216 | 32 КБ, текст. 1024 | CC0 | https://poly.pizza/m/y05UXwo0fM | горшок / пустой, атлас |
| `2bed__c-madsen-raised` Raised bed, Dan Vinge Madsen | 660 | 36 КБ, цвета | CC-BY 3.0 | https://poly.pizza/m/aTU8O8XERgM | грядка / подпись, пустая |
| `2bed__d-kenney-planter` planter (Suburban) | 204 | 19 КБ, colormap | CC0 | https://kenney.nl/assets/city-kit-suburban | **рекомендую**: кусты в бортике, стиль домов |

### 2.9 Голуби
| Кандидат | Треуг. | Файл | Лицензия | Страница | Плюсы / минусы |
|---|---|---|---|---|---|
| `2bird__a-jeremy-dove` Dove, jeremy | 366 | 22 КБ, цвета | CC-BY 3.0 | https://poly.pizza/m/dGEa6IbVDP_ | **рекомендую**: сидящий голубь / подпись, масштаб ×24 |
| `2bird__b-google-bird` Bird | 386 | 40 КБ, цвета | CC-BY 3.0 | https://poly.pizza/m/8Ph79kHbt9s | / летящий чёрный — не голубь |
| `2bird__c-google-dove` Dove | 690 | 46 КБ, текст. 32 | CC-BY 3.0 | https://poly.pizza/m/2jmH3trzPFf | похож / тяжелее |

CC0-голубя на poly.pizza и в наборах Kenney не нашлось.

### 2.10 Косточка-монета
| Кандидат | Треуг. | Файл | Лицензия | Страница | Плюсы / минусы |
|---|---|---|---|---|---|
| `2coin__a-quaternius-bone` Bone | 304 | 16 КБ, цвета | CC0 | https://poly.pizza/m/uMs0lDp1u3 | **рекомендую**: перекрасить в золото |
| `2coin__b-kay-bone` Bone, Kay Lousberg | 204 | 24 КБ, текст. 1024 | CC0 | https://poly.pizza/m/2jLwMoAb2y | ровная / атлас |
| `2coin__c-google-bone` Bone | 634 | 17 КБ, цвета | CC-BY 3.0 | https://poly.pizza/m/fNEj4sHr1zk | / подпись, тяжелее |

### 2.11 Находки прогулки (все Kenney, CC0)
| Кандидат | Треуг. | Файл | Страница | Заменяет |
|---|---|---|---|---|
| `3find__stick-a-kenney-log` log | 200 | 13 КБ, цвета | https://kenney.nl/assets/nature-kit | палку (уменьшить, удлинить) |
| `3find__stick-b-kenney-stump` stump_round | 56 | 5 КБ | там же | / пень, не палка |
| `3find__pebble-a-kenney-rock` rock_smallA | 16 | 2 КБ | там же | **камешек, рекомендую** |
| `3find__pebble-b-kenney-stoneflat` stone_smallFlatA | 20 | 2 КБ | там же | плоский камешек |
| `3find__sock-a-kenney-red` sock-red (Holiday) | 168 | 13 КБ, colormap | https://kenney.nl/assets/holiday-kit | носок / это рождественский чулок |
| `3find__sock-b-kenney-green` sock-green | 168 | 13 КБ | там же | то же |
| `3find__cone-alt-kenney-mushroom` mushroom_red | 48 | 6 КБ | https://kenney.nl/assets/nature-kit | вместо шишки — гриб |
| `3find__cone-alt-kenney-pinesmall` tree_pineSmallA | 164 | 12 КБ | там же | ёлочка как «шишка» — плохо |

Готовых шишки и листа под бюджет не нашёл.

### 2.12 Ванна и холодильник (Kenney Furniture Kit, CC0)
Это тот же набор, из которого уже стоят цветок, книжки и мишка (волна 53).

| Кандидат | Треуг. | Файл | Страница | Плюсы / минусы |
|---|---|---|---|---|
| `4bath__a-kenney-bathtub` bathtub | 602 | 34 КБ, цвета | https://kenney.nl/assets/furniture-kit | настоящая ванна / одна на все уровни, джакузи и спа останутся своими |
| `5fridge__a-kenney-fridge` kitchenFridge | 250 | 19 КБ | там же | |
| `5fridge__b-kenney-fridge-small` kitchenFridgeSmall | 152 | 12 КБ | там же | по размеру ближе к нынешнему |
| `5fridge__c-kenney-fridge-large` kitchenFridgeLarge | 436 | 29 КБ | там же | двухдверный |

Холодильники у Kenney серые, нынешний мятный читается лучше. Перекрашивать придётся в любом случае.

### 2.13 Сезонный декор (Kenney, CC0)
| Кандидат | Треуг. | Файл | Страница |
|---|---|---|---|
| `6season__snowman-a-kenney` snowman (Holiday) | 446 | 45 КБ, colormap | https://kenney.nl/assets/holiday-kit |
| `6season__snowman-b-kenney-hat` snowman-hat | 555 | 54 КБ | там же |
| `6season__pumpkin-a-kenney-food` pumpkin (Food) | 188 | 19 КБ, colormap | https://kenney.nl/assets/food-kit |
| `6season__pumpkin-b-kenney-crop` crop_pumpkin (Nature) | 120 | 10 КБ, цвета | https://kenney.nl/assets/nature-kit |
| `6season__tulip-a-kenney-flower-red` flower_redA | 76 | 6 КБ | там же |
| `6season__sunflower-a-kenney-flower-yellow` flower_yellowA | 76 | 6 КБ | там же (обычный жёлтый цветок, не подсолнух) |

## 3. Рекомендация

**Раннер, готовый набор.** Мелочь берём у Quaternius: CC0, цвета без текстур, тот же автор, что пёс. Дома и клумбу
берём из Kenney City Kit Suburban: подходящих домов у Quaternius нет.
- Дерево: Kenney tree_default.
- Куст: Quaternius Bush.
- Домики: Kenney building-type a, c, f.
- Фонарь: Quaternius Street Light.
- Забор: Quaternius Fence.
- Ящик: Quaternius Cube Crate.
- Скамейка: Quaternius Bench.
- Клумба: Kenney planter.
- Голуби: jeremy Dove (CC-BY).
- Косточка: Quaternius Bone в золоте.

Вес набора ≈ 480 КБ GLB, в usdz примерно столько же. Сейчас примитивы весят 0 КБ.
Треугольники в кадре:
- 4–6 домов × ~1200 + до 10 деревьев × 114 + мелочь ≈ 8–10 тыс.
- Пёс — около 4 тыс.
- Для iPhone Air это немного.

**Находки прогулки:**
- Камешек — Kenney rock_smallA.
- Палка — Kenney log, уменьшенный.
- Носок, шишку и лист оставить своими: готовых подходящих нет, а носок Kenney — рождественский чулок.

**Комната:**
- Ванну и холодильник по желанию. Уровневые варианты (джакузи, спа, бункер, колпак) всё равно остаются своими,
  выигрыш небольшой.
- Ванна Kenney как база уровня 1 — да, если Вадиму не нравится цилиндр.

**Не менять:**
- Сезонный декор и двор (YardArtModel). Там бюджет треугольников под тестами и сборка в Linux, а переход на usdz
  ломает этот конвейер ради модели размером 0,2 м.
- Вещи на псе (скиннинг).
- Стены, окно и полки.

## 4. Вопросы Вадиму

1. Ставить ли в раннер готовые модели вместо примитивов? Этот же вопрос открыт с волны 55b, DECISIONS.
   **Рекомендую да**, набором из раздела 3: +~480 КБ к ipa (сейчас 7,44 МБ).
2. Голуби — CC-BY (jeremy). Нужна подпись в «Об игре» и в ASSETS_LICENSES.md. Если не хочется CC-BY, голубей
   можно оставить примитивом или заменить препятствие. **Рекомендую jeremy Dove с подписью.**
3. Косточка: менять на Quaternius Bone в золоте или оставить свою, она хорошо читается как монета?
   **Рекомендую менять.**
4. Находки прогулки: заменить только камешек и палку? **Рекомендую да.** Шишка, лист и носок остаются своими.
5. Ванна и холодильник Kenney? **Рекомендую пока нет:** уровни всё равно свои. Если цилиндр-ванна режет глаз —
   ванну Kenney на уровень 1.
6. Сезонный декор на Kenney (снеговик, тыква)? **Рекомендую нет:** дорого по конвейеру, выигрыш мал.

## 5. Риски

- **Масштаб.**
  - Poly by Google приходит в масштабе 100 м – 500 км (скамейка ~500 км, дом ~117 м, голубь jeremy ×24).
  - Quaternius — в метрах: фонарь и дерево 5,6 м.
  - Kenney — около 1 единицы.
  - Каждой модели нужен свой коэффициент, плюс снимок для проверки.
- **Материалы.**
  - Сцена использует матовую обработку `PetRoom.matteMaterial`. У Quaternius несколько материалов-цветов,
    это ок.
  - У Kenney Suburban / Holiday / Food внешняя `colormap.png`: при конвертации в usdz её нужно встроить, иначе
    модель станет белой.
  - Атласы Kay/Isa 1024 px ужать до 512.
- **Многомешевые модели Google** (дом — 49 мешей): лишние draw calls. Слить меши при конвертации.
- **Вес и производительность.** Дома повторяются вдоль дороги: держать их в пуле объектов (как сейчас), а не
  клонировать. Проверить FPS и CPU раннера в PerfUITests: бюджет CPU 20 %, покой уже 15,8–19,1 %.
- **Лицензии.** CC-BY (голубь; при выборе — Google и Madsen/J-Toastie) — подпись в «Об игре» и ASSETS_LICENSES.md.
  CC0 — по традиции проекта тоже вписать в ASSETS_LICENSES.md.
- **Конвертация GLB → usdz.** Её делает существующий пайплайн props (Blender / usd-core). Повороты осей Y-up/Z-up
  проверять по снимку.
- **Стиль.** Kenney Suburban чуть мультяшнее Quaternius. Если Вадиму важна однородность, дома заменить нечем:
  Quaternius даёт только средневековую хижину.
- **Поиск.** poly.pizza под конец отвечал 502/503, часть запросов (ванна, шишка, лист) не прошла. Возможно, там
  есть ещё варианты.
