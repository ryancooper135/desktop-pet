# Волна 61: слабые самодельные 3D-модели и готовые замены

ТЗ v3, «Волна 54», пункт 4, плюс модели для «Раннера» (волна 55b). Это только исследование: код приложения не менялся, сами модели в репо не кладём, здесь лежат только PNG-превью.

- Скачанное лежит локально в `C:\Users\ryanc\pet-assets\candidates\wave61\<предмет>__<вариант>\`. В каждой папке есть `model.glb` и `source.json` (название, автор, лицензия, ссылка).
- Превью рендерились в Blender 5.2 (Workbench, один фон, одна камера). Вид «сейчас» — рендер дампа `YardArt` или кадр из CI-артефакта Pet-screens.
- Фильтр: только CC0 или CC-BY, не больше 2000 треугольников, текстура не больше 512 px, вес до 300 КБ в usdz. «Вес» в таблицах — это glb плюс внешняя текстура (у Kenney ≈12 КБ). В usdz обычно выходит примерно ×1.1–1.3 от glb.
- Миска и мяч сделаны в волне 58, их не трогал.

## PNG-листы (`design/wave61/png/`)

| Лист | Что на нём |
|---|---|
| `0-overview.png` | Все самодельные модели «сейчас» с оценкой слабо/норм |
| `1-runner-roadside.png` | Раннер, обочина: дерево, куст, дом, фонарь, забор |
| `2-runner-obstacles.png` | Раннер: ящик, скамейка, клумба, голуби, монета-косточка |
| `3-room.png` | Комната: холодильник, ванна |
| `4-season.png` | Сезонный декор двора: снеговик, тыква, подсолнух, тюльпаны |
| `5-yard-stations.png` | Двор: 5 станций и фургон переезда |

Как читать: оранжевая рамка — то, что сейчас в игре; зелёная рамка с меткой «беру» — моя рекомендация. Красным подписана текстура 1024, которую перед сборкой надо ужать до 512.

## Оценка самодельного

| Где | Предмет | Код | Оценка | Почему |
|---|---|---|---|---|
| Раннер | куст | `RunnerScene.swift` («bush») | **слабо** | два гладких шара |
| Раннер | забор | `RunnerScene.swift` («fence») | **слабо** | белые планки без перекладин |
| Раннер | ящик-препятствие | `RunnerScene.swift` (`.crate`) | **слабо** | два голых бокса |
| Раннер | скамейка | `RunnerScene.swift` (`.bench`) | **слабо** | набор брусков |
| Раннер | клумба | `RunnerScene.swift` (`.flowerbed`) | **слабо** | коробка и цветные шарики |
| Раннер | монеты-косточки | `RunnerScene.swift` (`.coin`) | **слабо** | стопка жёлтых кусочков |
| Раннер | дерево, дом A/B/C, фонарь, голуби | `RunnerScene.swift` | нет кадра | в CI-кадры не попали; судя по коду, собраны из примитивов, как и остальное |
| Комната | ванна | `RoomDecor.swift` `bath()` | **слабо** | овальный цилиндр |
| Комната | холодильник | `RoomDecor.swift` | слабо/норм | коробка со швом |
| Двор, сезон | снеговик | `SeasonArt` | **слабо** | ромбы вместо шаров |
| Двор, сезон | тыква | `SeasonArt` | **слабо** | похожа на волчок |
| Двор, сезон | подсолнух, тюльпаны | `SeasonArt` | норм | читаются, оставить |
| Двор | 8 станций | `YardModels.swift` | норм | единый стиль; узлы анимации (лопасти, колесо, конвейер) зашиты в модель |
| Двор | декор районов и ярусы | `YardDistrictArt.swift` | норм | редкий, но в масштабе сцены работает |
| Двор | фургон переезда | `YardMove.swift` | нет кадра | 3D в CI пустое; узел «van» несёт пса в кабине |
| Пёс | вещи (корона, шарф, плащ, бант) | `PetWear.swift` | норм | подогнаны к костям пса, готовые не сядут |
| Комната | вид из окна, будка | `PetRoom.swift` | норм | плоская картинка, мелкая деталь |

## Кандидаты и рекомендации

Колонка «тр» — треугольники, посчитанные в Blender по glb. Колонка «КБ» — вес glb вместе с текстурой.

### Раннер: обочина (`1-runner-roadside.png`)

**Дерево**

| # | Модель | Автор | Лицензия | Ссылка | тр | КБ | Плюс / минус |
|---|---|---|---|---|---|---|---|
| 1 ★ | tree_default (Nature Kit) | Kenney | CC0 | https://kenney.nl/assets/nature-kit | 114 | 9 | + лёгкое, без текстуры, цвет перекрашивается / − простое |
| 2 | Pine Tree | Danni Bittman | CC-BY | https://poly.pizza/m/2Qo-fmVKuSG | 264 | 21 | + ель даёт разнообразие парку / − нужна атрибуция |
| 3 | Tree | Quaternius | CC0 | https://poly.pizza/m/9nvGuZlbpE | 1810 | 98 | + самое красивое / − тяжёлое для многих копий |

Рекомендация: Kenney tree_default как основное дерево и Bittman Pine как второй вариант.

**Куст**

| # | Модель | Автор | Лицензия | Ссылка | тр | КБ | Плюс / минус |
|---|---|---|---|---|---|---|---|
| 1 ★ | Bush | Quaternius | CC0 | https://poly.pizza/m/92EytlU1El | 364 | 21 | + объёмный, читается / − тёмный, нужен светлее тон |
| 2 | plant_bushDetailed | Kenney | CC0 | https://kenney.nl/assets/nature-kit | 104 | 10 | + очень лёгкий / − больше похож на траву |
| 3 | Bush | Isa Lousberg | CC0 | https://poly.pizza/m/I5KhMKZKju | 180 | 27 | + мягкая форма / − текстура 1024, ужать до 512 |

Рекомендация: Quaternius Bush, перекрасить в зелёный раннера.

**Дом (houseA/B/C)**

| # | Модель | Автор | Лицензия | Ссылка | тр | КБ | Плюс / минус |
|---|---|---|---|---|---|---|---|
| 1 ★ | building-type-a (City Kit Suburban) | Kenney | CC0 | https://kenney.nl/assets/city-kit-suburban | 1174 | 108 | + в наборе есть варианты c и f для A/B/C в одном стиле / − текстура-палитра 512 |
| 2 | House | Quaternius | CC0 | https://poly.pizza/m/L7h0SjZX2K | 1028 | 56 | + без текстуры / − деревенский сарай, не город |
| 3 | building-type-f | Kenney | CC0 | https://kenney.nl/assets/city-kit-suburban | 1616 | 147 | + двухэтажный / − тяжелее |

Рекомендация: Kenney Suburban a, c и f на три варианта дома (1174, 1196 и 1616 тр).

**Фонарь**

| # | Модель | Автор | Лицензия | Ссылка | тр | КБ | Плюс / минус |
|---|---|---|---|---|---|---|---|
| 1 ★ | Street Light | Quaternius | CC0 | https://poly.pizza/m/nFwrlcLvM5 | 324 | 11 | + лёгкий, без текстуры / − современный, строгий |
| 2 | lantern (Holiday Kit) | Kenney | CC0 | https://kenney.nl/assets/holiday-kit | 172 | 30 | + уютный, в духе питомца / − текстура 512 |
| 3 | Streetlight | Kay Lousberg | CC0 | https://poly.pizza/m/vPFSLYh6sg | 176 | 28 | + лёгкий / − текстура 1024 |

Рекомендация: Quaternius Street Light. Если нужен уютнее — Kenney lantern.

**Забор**

| # | Модель | Автор | Лицензия | Ссылка | тр | КБ | Плюс / минус |
|---|---|---|---|---|---|---|---|
| 1 ★ | Fence | Quaternius | CC0 | https://poly.pizza/m/r0n40F7FKx | 212 | 13 | + классический деревянный, тайлится / − нет |
| 2 | Fence Fortified | Kenney | CC0 | https://poly.pizza/m/9FQPNr0sdJ | 276 | 18 | + плотный / − глухой, закрывает вид |
| 3 | Fence | Kay Lousberg | CC0 | https://poly.pizza/m/aE3GIx8jIH | 380 | 43 | + красивая кованая / − текстура 1024, «городской» стиль |

Рекомендация: Quaternius Fence.

### Раннер: препятствия и монета (`2-runner-obstacles.png`)

**Ящик**

| # | Модель | Автор | Лицензия | Ссылка | тр | КБ | Плюс / минус |
|---|---|---|---|---|---|---|---|
| 1 ★ | Cube Crate | Quaternius | CC0 | https://poly.pizza/m/YAghI6GBls | 264 | 13 | + сразу читается как препятствие / − тёмный |
| 2 | Fruit Crate | BlenderVoyage | CC0 | https://poly.pizza/m/aXulVWHOeV | 196 | 15 | + милый / − низкий и решётчатый, хуже виден |
| 3 | Crate | Kay Lousberg | CC0 | https://poly.pizza/m/yCBoU0iyOk | 132 | 31 | + лёгкий / − открытый сверху, текстура 1024 |

Рекомендация: Quaternius Cube Crate, стопкой по 2 как сейчас.

**Скамейка**

| # | Модель | Автор | Лицензия | Ссылка | тр | КБ | Плюс / минус |
|---|---|---|---|---|---|---|---|
| 1 ★ | Bench | Quaternius | CC0 | https://poly.pizza/m/jLxjFxFRpw | 376 | 21 | + парковая со спинкой / − тёмная |
| 2 | bench (Holiday Kit) | Kenney | CC0 | https://kenney.nl/assets/holiday-kit | 160 | 28 | + яркая, мультяшная / − текстура 512 |
| 3 | Bench | Ev Amitay | CC-BY | https://poly.pizza/m/dOSjmdmKaxi | 288 | 21 | + аккуратная / − атрибуция |

Рекомендация: Quaternius Bench. Kenney — если хочется ярче.

**Клумба**

| # | Модель | Автор | Лицензия | Ссылка | тр | КБ | Плюс / минус |
|---|---|---|---|---|---|---|---|
| 1 ★ | planter (City Kit Suburban) | Kenney | CC0 | https://kenney.nl/assets/city-kit-suburban | 204 | 31 | + низкая, как препятствие / − кусты вместо цветов, можно добавить Kenney flower (76 тр) |
| 2 | Planter & Bushes | J-Toastie | CC-BY | https://poly.pizza/m/wn85Xr9lM3 | 622 | 52 | + деревянный ящик / − атрибуция, тяжелее |
| 3 | Medium Pot | Isa Lousberg | CC0 | https://poly.pizza/m/y05UXwo0fM | 216 | 33 | + горшок / − не клумба, текстура 1024 |

Рекомендация: Kenney planter и 2–3 Kenney flower_red/yellow сверху (всего ≈430 тр).

**Голуби**

| # | Модель | Автор | Лицензия | Ссылка | тр | КБ | Плюс / минус |
|---|---|---|---|---|---|---|---|
| 1 ★ | Dove | jeremy | CC-BY | https://poly.pizza/m/dGEa6IbVDP_ | 366 | 22 | + сидящий голубь, мягкий стиль / − атрибуция |
| 2 | Bird | Poly by Google | CC-BY | https://poly.pizza/m/8Ph79kHbt9s | 386 | 40 | + в полёте / − чёрный ворон, не голубь |
| 3 | Dove | Poly by Google | CC-BY | https://poly.pizza/m/2jmH3trzPFf | 690 | 46 | + реалистичный голубь / − тяжелее |

Рекомендация: jeremy Dove. CC0-голубя в нужном весе не нашёл.

**Монета-косточка**

| # | Модель | Автор | Лицензия | Ссылка | тр | КБ | Плюс / минус |
|---|---|---|---|---|---|---|---|
| 1 ★ | Bone | Quaternius | CC0 | https://poly.pizza/m/uMs0lDp1u3 | 304 | 17 | + чёткая кость / − перекрасить в золото |
| 2 | Bone | Poly by Google | CC-BY | https://poly.pizza/m/fNEj4sHr1zk | 634 | 17 | + плавная / − тяжелее для многих монет |
| 3 | Bone | Kay Lousberg | CC0 | https://poly.pizza/m/2jLwMoAb2y | 204 | 24 | + лёгкая / − текстура 1024 |

Рекомендация: Quaternius Bone в золотом цвете. На трассе десятки монет, поэтому лучше один меш, раздаваемый через `clone`.

### Комната (`3-room.png`)

**Ванна**

| # | Модель | Автор | Лицензия | Ссылка | тр | КБ | Плюс / минус |
|---|---|---|---|---|---|---|---|
| 1 ★ | Bathtub | CreativeTrio | CC0 | https://poly.pizza/m/2MbbdwbTjt | 474 | 42 | + отдельностоящая со смесителем, уютная / − текстура-палитра 128 |
| 2 | bathtub (Furniture Kit) | Kenney | CC0 | https://kenney.nl/assets/furniture-kit | 602 | 35 | + без текстуры / − встроенная, «квадратная» |
| 3 | Bathtub | Quaternius | CC0 | https://poly.pizza/m/wrOzCX3k48 | 248 | 11 | + самая лёгкая / − тёмно-серая, перекрашивать |

Ещё был Isa Lousberg Bath (https://poly.pizza/m/6Rt3WkC0w3, 1716 тр, текстура 1024): красивый, но тяжёлый.

Рекомендация: CreativeTrio Bathtub. Утёнок и пена (уровни ванны в `RoomDecor.bath`) остаются своими поверх.

**Холодильник**

| # | Модель | Автор | Лицензия | Ссылка | тр | КБ | Плюс / минус |
|---|---|---|---|---|---|---|---|
| 1 ★ | Fridge (ретро) | Quaternius | CC0 | https://poly.pizza/m/3NYolcXB1o | 1186 | 54 | + ретро с ручками, лучше всего ложится в уютную комнату / − 1186 тр, текстура 512 |
| 2 | kitchenFridgeSmall | Kenney | CC0 | https://kenney.nl/assets/furniture-kit | 152 | 13 | + очень лёгкий / − та же коробка, что сейчас |
| 3 | Kitchen Fridge | Quaternius | CC0 | https://poly.pizza/m/8sjRm8fnHh | 404 | 17 | + двухдверный / − тёмный, офисный |

Рекомендация: Quaternius Fridge (ретро). Если важен вес — оставить свой.

### Сезонный декор двора (`4-season.png`)

**Снеговик**

| # | Модель | Автор | Лицензия | Ссылка | тр | КБ | Плюс / минус |
|---|---|---|---|---|---|---|---|
| 1 ★ | snowman-hat (Holiday Kit) | Kenney | CC0 | https://kenney.nl/assets/holiday-kit | 555 | 67 | + цилиндр, шарф, руки-ветки — всё как у нашего / − текстура 512 |
| 2 | snowman (Holiday Kit) | Kenney | CC0 | https://kenney.nl/assets/holiday-kit | 446 | 58 | + легче / − без шляпы |
| 3 | Snowman | jeremy | CC-BY | https://poly.pizza/m/aVl3UrWiDg1 | 1280 | 70 | + классические шары / − тяжелее, атрибуция |

Рекомендация: Kenney snowman-hat.

**Тыква**

| # | Модель | Автор | Лицензия | Ссылка | тр | КБ | Плюс / минус |
|---|---|---|---|---|---|---|---|
| 1 ★ | Pumpkin | Kay Lousberg | CC0 | https://poly.pizza/m/LkZRzB1CXf | 306 | 25 | + самая «тыквенная» форма / − текстура 1024, ужать до 512 |
| 2 | pumpkin (Food Kit) | Kenney | CC0 | https://kenney.nl/assets/food-kit | 188 | 30 | + лёгкая / − текстура 512 |
| 3 | Pumpkin | Quaternius | CC0 | https://poly.pizza/m/bvLvqnU1jX | 644 | 37 | + рёбра, без текстуры / − тёмная |

Рекомендация: Kay Pumpkin. Если не хочется ужимать текстуру — Kenney pumpkin. Листья вокруг можно оставить свои.

**Подсолнух и тюльпаны** — свои норм, менять не советую. Для справки:

| Модель | Автор | Лицензия | Ссылка | тр | КБ | Почему не беру |
|---|---|---|---|---|---|---|
| Sunflower | jeremy | CC-BY | https://poly.pizza/m/a9qW8wSfaaX | 756 | 42 | красивый в горшке, но в 8 раз тяжелее нашего (96) |
| flower_yellowA | Kenney | CC0 | https://kenney.nl/assets/nature-kit | 76 | 7 | не подсолнух |
| Tulip | jeremy | CC-BY | https://poly.pizza/m/aho9NdFUBFu | 960 | 53 | один тюльпан, а у нас горшок с тремя (×3 = 2880 тр) |
| flower_redA | Kenney | CC0 | https://kenney.nl/assets/nature-kit | 76 | 7 | хуже нашего |

### Двор: станции и фургон (`5-yard-stations.png`)

Станции оценены как норм. Готовые модели ломают единый стиль платформ и узлы анимации (`spin` у лопастей, колеса, конвейера). Ниже варианты на случай, если решим менять.

| Станция | # | Модель | Автор | Лицензия | Ссылка | тр | КБ | Плюс / минус |
|---|---|---|---|---|---|---|---|---|
| Котелок каши (сейчас 314 тр) | 1 ★ | Cauldron | Quaternius | CC0 | https://poly.pizza/m/QaWJOPa6Gt | 1238 | 46 | + сразу «котёл» / − в 4 раза тяжелее нашего |
| | 2 | Caldron | CreativeTrio | CC0 | https://poly.pizza/m/P36cOeZHyX | 974 | 76 | + на треноге, с варевом / − «ведьминский» |
| | 3 | Cooking Pot | Quaternius | CC0 | https://poly.pizza/m/jAUb3FoCN7 | 260 | 15 | + лёгкий / − кастрюля |
| Пирожковая печь (312) | 1 | Chiminea | Zsky | CC-BY | https://poly.pizza/m/vyPksecx1G | 450 | 32 | + уличная печь / − не пекарня |
| | 2 | Oven | Quaternius | CC0 | https://poly.pizza/m/VNjPRwui7t | 528 | 22 | + плита / − кухонная, не для двора |
| | 3 | Oven | Kay Lousberg | CC0 | https://poly.pizza/m/FGnRmwfjsT | 542 | 57 | + яркая / − микроволновка, текстура 1024 |
| Лунная мельница (330) | 1 | Windmill | Quaternius | CC0 | https://poly.pizza/m/WUbU1Nct2W | 1714 | 123 | + красивая / − лопасти не отдельным узлом, тяжёлая |
| | 2 | Windmill | Poly by Google | CC-BY | https://poly.pizza/m/ctIRaIM3zXu | 584 | 269 | + форма / − 269 КБ из-за текстуры |
| | 3 | Windmill | Pixel | CC-BY | https://poly.pizza/m/9BIMVqxyHV | 1985 | 293 | + детальная / − на грани всех лимитов |
| Сушилка сухариков (300) | 1 | Washing Line | J-Toastie | CC-BY | https://poly.pizza/m/nGU4m9V7ez | 536 | 38 | + сушилка / − «зонтик» для белья, не сухарики |
| | 2 | Towel Rack | Quaternius | CC0 | https://poly.pizza/m/8R9fXwL11r | 192 | 11 | + лёгкая / − вешалка для полотенца |
| Фотобудка (260) | 1 | Photo booth | jeremy | CC-BY | https://poly.pizza/m/dmssJFoQM4N | 648 | 36 | + именно фотобудка / − плоский шкаф, хуже нашей |
| | 2 | Instant Camera | Nick Slough | CC-BY | https://poly.pizza/m/AYBr4bMYvS | 494 | 44 | + можно как вывеску на крыше / − не будка |

Рекомендация по станциям: оставить свои. Единственный разумный обмен — котелок на Quaternius Cauldron, поставленный на нашу платформу.

**Фургон переезда** (`YardMove.swift`; в нём узел «van» с псом в кабине)

| # | Модель | Автор | Лицензия | Ссылка | тр | КБ | Плюс / минус |
|---|---|---|---|---|---|---|---|
| 1 | Taxi | Kay Lousberg | CC0 | https://poly.pizza/m/u5PhZQ35XG | 1256 | 84 | + мультяшный стиль / − такси, а не фургон; текстура 1024 |
| 2 | Caravan | Poly by Google | CC-BY | https://poly.pizza/m/77t77GQMubf | 1366 | 117 | + «дом на колёсах» по смыслу / − без кабины, текстура 1024 |
| 3 | Van | Poly by Google | CC-BY | https://poly.pizza/m/aT_24cDaW1a | 1946 | 43 | + фургон / − выглядит как SUV, на пределе по треугольникам |

Рекомендация: оставить свой. Готовые не дают кабину под пса, а лёгкого мультяшного фургона в CC0 не нашлось: Quaternius Truck — 5546 тр, Sushi Truck — 14442.

## Отброшено по лимитам

| Модель | Почему |
|---|---|
| Quaternius Mill | 7018 тр |
| Tower Windmill | 4464 тр |
| Camera stand | 5492 тр |
| Google Camera | 1.5 МБ |
| Quaternius Truck, Sushi Truck | 5546 и 14442 тр |
| Google Van2 | 5434 тр |
| Polygonal Mind Snowman | 4940 тр, 937 КБ |
| J-Toastie Snowman | 3268 тр |
| Google Snowman 2 | 3176 тр |
| Yonemoto Snow Man | 2314 тр |
| Quaternius Flowers | 364 КБ |
| Bird house | 2316 тр |

Будки-конуры не искал: это мелкая деталь в окне.

## Атрибуция CC-BY

Если берём CC-BY, в экран «О программе» или в `CREDITS` нужно добавить строки вида «<Название> by <автор>, CC-BY 3.0, via Poly Pizza». Из рекомендованных CC-BY только jeremy Dove. Остальные рекомендации — CC0.

## Перед сборкой (следующая волна)

1. glb → usdz через `usd-core`, проверить масштаб: у Google-моделей единицы в сантиметрах, размеры 100+.
2. Текстуры 1024 ужать до 512 (Kay, Isa).
3. Тёмные модели Quaternius (куст, ящик, скамейка) перекрасить в палитру раннера.
4. Монеты и кусты раздавать через `clone` от одного меша.
