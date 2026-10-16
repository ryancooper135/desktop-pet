# 10. 3D-пайплайн: Shiba (Quaternius) → shiba.usdz для RealityKit

Дата: 16.10.2026. Стиль A «Nintendogs» (решение 16.10, DECISIONS.md). На ПК ничего не ставилось. Blender работает только в облаке (GitHub Actions, Linux).

## Вывод

1. **Источник:** Quaternius «Ultimate Animated Animals», Shiba Inu. Лицензия **CC0 1.0**: можно в коммерческом приложении, указывать автора не обязательно (в «Об игре» всё равно напишем). Копия лежит в `tools/assets/source/shiba.glb`.
2. **Путь:** `shiba.glb` → `build_clips.py` (numpy: позы sit/lie/sleep, все клипы на одной шкале, палитра стиля A) → Blender 5.2.2 в фоне (импорт glTF, материалы, экспорт USD со скелетом) → `check_usdz.py` (usd-core, ARKit-проверки) → артефакт `shiba-usdz`.
3. **Анимация:** в USD у скелета одна анимация. Поэтому все 21 клип идут подряд в одной анимации `Clips` (24 fps), а `clips.json` хранит, где какой. В приложении один раз берём `availableAnimations.first` и режем его через `AnimationView(trimStart:trimEnd:)`.
4. **Позы sit / lie / sleep** в паке отсутствуют. Они собраны процедурно из чисел в `poses.json` (повороты костей и сдвиг тела, ноги держатся на полу через IK). Править можно без Blender: меняем числа, пушим, смотрим PNG-превью в артефакте. Превью можно собрать и на ПК, ему нужен только numpy.
5. **Кадры виджета** рисует само приложение, пока открыто: `RealityRenderer` → текстура → PNG в контейнер App Group → `WidgetCenter.reloadAllTimelines()`. Виджет только показывает PNG.

## Источник

| | |
|---|---|
| Пак | https://quaternius.com/packs/ultimateanimatedanimals.html |
| Модель | https://poly.pizza/m/y4wdQpg767 (Quaternius, CC0), файл `static.poly.pizza/ba6d0ee3-bcc0-4ef0-9d3c-a3e245b41c77.glb` |
| Файл в репо | `tools/assets/source/shiba.glb`, 851 196 байт, sha256 `9cbd4f1e12f85024126eab6a2c5706c099196df1a10db74e6c8b67bac3fff54a` |
| Геометрия | 1950 треугольников, 1 меш, 6 материалов (`Main`, `Main_Light`, `Black`, `Eyes_White`, `Eyes_Pupil`, `Eyes_Black`), **UV нет** |
| Скелет | 46 костей: `Body → Back`(таз) / `Torso…Neck1–3 → Head → Ear1–4.L/R`, передние `FrontShoulder → FrontUpperLeg → FrontLowerLeg`, задние `BackShoulder → BackLeg → BackUpperLeg → BackLowerLeg`, `Tail1–3`, IK-кости `IKFrontLeg/IKBackLeg.*` |
| Ориентация | Y вверх, морда к +Z, длина около 3,6 единицы. В приложении масштаб подгоняем по `visualBounds` |

CI берёт модель только из репозитория. В сеть ходит только за Blender: официальный tar с download.blender.org, sha256 сверяется с официальным файлом `.sha256`.

## Анимации (`clips.json`)

24 fps, между клипами 1 пустой кадр, вся шкала 0…882 (36,75 с).

| Клип | Кадры | Цикл | Откуда |
|---|---|---|---|
| `idle`, `idle_2`, `idle_headlow` | 0–80, 82–162, 164–260 | да | пак (`Idle`, `Idle_2`, `Idle_2_HeadLow`) |
| `walk`, `gallop` | 262–287, 289–302 | да | пак |
| `gallop_jump`, `jump_to_idle` | 304–326, 328–360 | нет | пак |
| `eat` | 362–422 | да | пак (`Eating`) |
| `attack`, `hit_left`, `hit_right`, `death` | 424–456, 458–474, 476–492, 494–519 | нет | пак |
| `sit_in` → `sit` → `sit_out` | 521–535, 537–609, 611–623 | нет / да / нет | **poses.json** |
| `lie_in` → `lie` → `lie_out` | 625–644, 646–718, 720–737 | нет / да / нет | **poses.json** |
| `sleep_in` → `sleep` → `sleep_out` | 739–763, 765–861, 863–882 | нет / да / нет | **poses.json** (из `lie`) |

Формат: `{"fps":24,"animation":"Clips","duration":36.75,"clips":{"sit":{"start":22.375,"end":25.375,"frames":[537,609],"loop":true,"source":"pose:sit"}, …}}`. Секунды точные, кадры для отладки. Порядок клипов и их кадры меняются при каждой правке `poses.json`, поэтому **в коде только имена клипов, никаких чисел**.

Для геймплея пригодятся ещё `happy` (виляние хвостом), `beg`, `scratch` и `drink`. Их можно добавить в `poses.json` так же, циклами с «дыханием» по любой кости (`breath`).

## Как сделаны позы без Blender на ПК

- `poses.json`: углы поворота костей в **мировых осях модели** (+X = нос вниз, +Y = поворот влево, +Z = крен вправо), `Кость.*` означает обе стороны (правая зеркально). Есть `offset` (сдвиг тела) и `from` (поза поверх другой позы).
- Тело само ставится на пол: самая низкая точка меша = как в `idle`. IK-кости ног следуют за голенями, поэтому лапы не отрываются.
- Переходы `*_in/_out` идут плавно (smoothstep). Если одна поза построена из другой (lie → sleep), интерполируются сами повороты. Это IK-безопасно.
- Проверка: `preview.py` рисует программный рендер в PNG (numpy, без GPU). В CI получаются `preview_side.png` (сбоку: sit/lie/sleep) и `preview_3q.png`.
- Локально, если нужно, достаточно python + numpy:
  ```
  python -B tools/assets/build_clips.py tools/assets/source/shiba.glb --poses tools/assets/poses.json --style tools/assets/style_a.json --out-glb build/shiba_clips.glb --out-json build/clips.json
  python -B tools/assets/preview.py build/shiba_clips.glb --clips build/clips.json --only sit --only sleep --yaw 90 --out build/p.png
  ```
- Если позы потом сделает человек в Blender (у кого он есть), формат не меняется: он добавит в GLB анимации `Sit`, `Sleep` и т. д., а в `build_clips.py` в карту `RENAME` допишется строка.
- Запасной вариант прямо в RealityKit: `FromToByAnimation<JointTransforms>` с `bindTarget: .jointTransforms` (поза = массив `Transform` по `jointNames`). Работает, но позы окажутся в Swift, и проверять их можно будет только на телефоне. Беру CI-путь.

## Стиль A в ассете

`style_a.json`: `Main` #E9A15B (рыжий), `Main_Light` #FFF1DE (кремовые грудь и морда, в исходнике там серый), `Black` #4B3A36, глаза #FFFFFF / #3B2A22 / #231B1E. Metallic 0, roughness 1, specular 0, без бликов PBR. Вариант `eyes_closed` красит `Eyes_*` в цвет `Main`.

Шерсть: UV у модели нет. Варианты: (а) `CustomMaterial` с триплан-шумом по позиции в пространстве модели (позже, в шейдере); (б) добавить в `blender_export.py` `smart_project` и печь текстуру. Для первой версии хватит flat-цвета с мягким светом.

## Сборка в облаке: `.github/workflows/assets.yml`

- Запуск: `workflow_dispatch` (вход `blender`, по умолчанию 5.2.2, и `commit`), а также push в `tools/assets/**`. Раннер ubuntu-latest. Mac-минуты не тратятся.
- Шаги: pip `numpy usd-core` → `build_clips.py` → превью → apt-библиотеки для Blender без экрана → кэш tar (~383 МБ) → скачивание с проверкой sha256 → `blender -b --factory-startup --python-exit-code 1 --python blender_export.py` → `check_usdz.py --strict`, сводка в Summary → артефакт `shiba-usdz` (usdz, clips.json, превью, отчёт, склеенный GLB) на 30 дней.
- Экспорт: `convert_orientation`, forward −Z / up Y, метры, `root_prim_path=/root`, triangulate, UsdPreviewSurface, все кости. Параметры фильтруются по версии Blender, так что подойдёт и 4.5 LTS.
- `check_usdz.py` проверяет: upAxis Y, fps 24, шкала 0…882, ровно один Skeleton с одной SkelAnimation, морда к +Z, число треугольников. ARKit compliance идёт предупреждением (жёстко только с `--strict-compliance`).

**Артефакт или коммит.** По умолчанию только артефакт: смотрим превью, качаем, проверяем. Когда превью устраивает, запускаем вручную с `commit=true`. Второй job (`contents: write`) кладёт `app/Resources/Pets/shiba.usdz` и `shiba.clips.json` и коммитит от github-actions[bot]. Почему так: сборке приложения (`app.yml`, Mac) файл нужен в репо, а тянуть артефакт из другого workflow хрупко (артефакты истекают). Коммит на каждый push засорил бы историю бинарниками. Коммит от бота не перезапускает workflow (ограничение `GITHUB_TOKEN`), цикла не будет. Папку `Resources/Pets` нужно добавить в `project.yml` приложения.

## Swift: загрузка и клипы (скетч под iOS 26 / Swift 6, проверить в Xcode)

```swift
import RealityKit
import Foundation

struct PetClips: Decodable, Sendable {
    struct Clip: Decodable, Sendable { let start: Double; let end: Double; let loop: Bool }
    let fps: Double
    let clips: [String: Clip]
}

@MainActor
final class PetRig {
    let root: Entity
    private let animated: Entity
    private let source: AnimationResource
    private let clips: PetClips
    private var cache: [String: AnimationResource] = [:]

    init() async throws {
        root = try await Entity(named: "shiba")                       // shiba.usdz в бандле
        let url = Bundle.main.url(forResource: "shiba.clips", withExtension: "json")!
        clips = try JSONDecoder().decode(PetClips.self, from: Data(contentsOf: url))
        guard let a = Self.findAnimated(root), let anim = a.availableAnimations.first else {
            throw CocoaError(.fileReadCorruptFile)
        }
        animated = a; source = anim
        let b = root.visualBounds(relativeTo: nil)                    // подгон под ~0.3 м по длине
        root.scale = .init(repeating: 0.3 / max(b.extents.z, 0.001))
    }

    func play(_ name: String, blend: TimeInterval = 0.2) {
        guard let c = clips.clips[name] else { return }
        if cache[name] == nil {
            let view = AnimationView(source: source.definition, name: name,
                                     repeatMode: c.loop ? .repeat : .none,
                                     trimStart: c.start, trimEnd: c.end)
            cache[name] = try? AnimationResource.generate(with: view)
        }
        if let r = cache[name] { animated.playAnimation(r, transitionDuration: blend) }
    }

    private static func findAnimated(_ e: Entity) -> Entity? {
        if !e.availableAnimations.isEmpty { return e }
        for c in e.children { if let f = findAnimated(c) { return f } }
        return nil
    }
}
```

Материалы: из USD приходят `PhysicallyBasedMaterial` с roughness 1 и metallic 0. Если на телефоне всё же видны блики, проходим по `ModelComponent.materials` и ставим `roughness = 1`, `metallic = 0`, `specular = 0`. Закрытые глаза: у материалов глаз заменить `baseColor.tint` на цвет `Main`. Материал узнаём по исходному цвету из `style_a.json` (цвета уникальны). Порядок материалов на устройстве нужно проверить.

## Кадры для виджета (PNG в App Group)

Виджет не может рендерить RealityKit (лимит памяти около 30 МБ, нет GPU в фоне). Значит, рисует приложение, **пока оно на экране** (Metal в фоне запрещён):

1. При смене состояния питомца (сон, еда, настроение) и при уходе в фон (`scenePhase == .inactive`) рисуем 1–3 кадра нужной позы. Отдельный `RealityRenderer` (iOS 18+): своя камера, прозрачный фон, размер 512×512 (small-виджет @3x).
2. Пишем `widget/<state>_<n>.png` атомарно в `SharedStore.containerURL` (App Group, как в `probe/Shared/SharedStore.swift`), затем `WidgetCenter.shared.reloadAllTimelines()`.
3. Виджет делает `UIImage(contentsOfFile:)` и показывает PNG. Смена кадров идёт записями таймлайна (настоящей анимации в виджете нет).

```swift
import RealityKit
import Metal
import ImageIO
import UniformTypeIdentifiers

@MainActor
func renderPNG(_ pet: Entity, size: Int = 512, to url: URL) async throws {
    let r = try RealityRenderer()
    let cam = PerspectiveCamera()
    cam.look(at: [0, 0.12, 0], from: [0.35, 0.22, 0.55], relativeTo: nil)
    r.entities.append(contentsOf: [pet, cam])
    r.activeCamera = cam
    r.cameraSettings.colorBackground = .color(.init(red: 0, green: 0, blue: 0, alpha: 0))

    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: size, height: size, mipmapped: false)
    d.usage = [.renderTarget, .shaderRead]; d.storageMode = .shared
    guard let tex = MTLCreateSystemDefaultDevice()?.makeTexture(descriptor: d) else { return }
    let out = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: tex))
    await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
        do { try r.updateAndRender(deltaTime: 1.0 / 24, cameraOutput: out, onComplete: { _ in k.resume() }) }
        catch { k.resume() }
    }
    var px = [UInt8](repeating: 0, count: size * size * 4)
    tex.getBytes(&px, bytesPerRow: size * 4, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
    let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    guard let ctx = CGContext(data: &px, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info.rawValue),
          let img = ctx.makeImage(),
          let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dst, img, nil)
    CGImageDestinationFinalize(dst)
}
```

Позу для кадра задаём заранее: `play("sleep")`, затем пара вызовов `updateAndRender` с `deltaTime`, чтобы анимация дошла до нужного момента. Entity при этом берём **клон** (`pet.clone(recursive: true)`), чтобы не трогать сцену на экране. Ретро-постэффект (`PostProcessEffect`) в `RealityRenderer` не обязателен: пиксельность можно сделать, рисуя в 128 px и масштабируя без сглаживания.

## Риски

- Экспорт скелета и анимации из Blender 5.2 в USD здесь не прогонялся (Blender на ПК нет). Первый запуск workflow и есть проверка: `check_usdz.py` упадёт с понятной причиной. Запасной путь: 4.5 LTS через вход `blender`.
- Соответствие `startTimeCode = 0` и `t = 0` в RealityKit (`trimStart`) проверяется только на устройстве. Если шкала сдвинута, проблема видна сразу: клип начнётся с чужой позы.
- Позы sit/lie/sleep подобраны руками по превью. Возможны мелкие проникновения лап в тело под другими углами камеры.
- ARKit compliance может ругаться (например, на материалы без текстур). Это предупреждение, RealityKit такое грузит.
- UV нет, поэтому текстура шерсти позже потребует триплан-шейдера или развёртки в CI.
