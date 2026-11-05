// Волна 64: ручки и проба для замера покоя (PerfDiagUITests). Читает PET_PERF_KNOB через Env — в Release для
// друзей окружение пустое (DevGate), так что в ipa ни одна ручка не включается и проба не строится.
// Ручки выключают по куску сцены, чтобы видеть, что из покоя чьё: наш код или сам RealityKit.

import ObjectiveC
import QuartzCore
import RealityKit
import SwiftUI
import UIKit

enum PerfKnob {
    static let all: Set<String> = Set((Env.value("PET_PERF_KNOB") ?? "").split(separator: ",").map(String.init))
    /// Без проб UI-тестов (EyeProbeLabel раз в 0,2 с, EyeProbe на каждый кадр).
    static let noProbe = all.contains("noprobe")
    /// Комната и пёс выключены (isEnabled = false), RealityView остаётся.
    static let stageOff = all.contains("off")
    /// Без RealityView совсем: только SwiftUI-оболочка главной.
    static let noStage = all.contains("nostage")
    /// Без теней от ключевого света.
    static let noShadow = all.contains("noshadow")
    /// Наши системы ECS (сок, режиссёр, хореография/лицо, свет, погода) не работают.
    static let noSystems = all.contains("nosys")
    /// Плюс к nosys: клипы скелета остановлены — кадр без анимации.
    static let freeze = all.contains("freeze")
    /// Попробовать 30 кадров в секунду через свойства вида RealityKit (если найдутся).
    static let fps30 = all.contains("fps30")
    /// Подпись perf.probe: кадры в секунду, тела главной, классы вида сцены.
    static let probe = all.contains("probe")
}

/// Счётчики пробы. Пишутся только при PerfKnob.probe.
@MainActor
enum PerfProbe {
    static var frames = 0
    static var homeBodies = 0
    static var entities = 0
    static var models = 0
    static var lights = 0
    static var text = "probe: ждём"
    private static var started = false
    private static var notes: [String] = []

    static func bumpHome() { if PerfKnob.probe { homeBodies += 1 } }

    static func countScene(_ roots: [Entity]) {
        var e = 0, m = 0, l = 0
        func walk(_ x: Entity) {
            e += 1
            if x.components.has(ModelComponent.self) { m += 1 }
            if x.components.has(DirectionalLightComponent.self) || x.components.has(PointLightComponent.self)
                || x.components.has(SpotLightComponent.self) { l += 1 }
            for c in x.children { walk(c) }
        }
        roots.forEach(walk)
        entities = e; models = m; lights = l
    }

    /// Запуск один раз: через 3 с — разбор вида (и попытка 30 к/с), через 8 и 18 с — частота кадров.
    static func start() {
        guard (PerfKnob.probe || PerfKnob.fps30), !started else { return }
        started = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            notes.append(scan())
            var f0 = frames, b0 = homeBodies, t0 = CACurrentMediaTime()
            for _ in 0..<4 {
                try? await Task.sleep(for: .seconds(5))
                let t = CACurrentMediaTime(), dt = t - t0
                let fps = Double(frames - f0) / dt, bodies = Double(homeBodies - b0) / dt
                text = String(format: "fps=%.1f home/s=%.2f ent=%d models=%d lights=%d | ", fps, bodies,
                              entities, models, lights) + notes.joined(separator: " | ")
                f0 = frames; b0 = homeBodies; t0 = t
            }
        }
    }

    /// Виды, похожие на хост сцены RealityKit: классы, цепочка, слой, селекторы про частоту кадров.
    private static func scan() -> String {
        var out: [String] = []
        var found: [UIView] = []
        func walk(_ v: UIView, depth: Int) {
            let name = NSStringFromClass(type(of: v))
            if name.contains("Reality") || name.contains("ARView") || name.contains("RE") && name.contains("View")
                || v.layer is CAMetalLayer {
                found.append(v)
            }
            if depth < 60 { v.subviews.forEach { walk($0, depth: depth + 1) } }
        }
        for scene in UIApplication.shared.connectedScenes {
            for w in (scene as? UIWindowScene)?.windows ?? [] { walk(w, depth: 0) }
        }
        for v in found.prefix(4) {
            var chain: [String] = []
            var c: AnyClass? = type(of: v)
            var sels: [String] = []
            while let k = c, chain.count < 8 {
                chain.append(NSStringFromClass(k))
                if k == UIView.self { break }
                var n: UInt32 = 0
                if let list = class_copyMethodList(k, &n) {
                    for i in 0..<Int(n) {
                        let s = NSStringFromSelector(method_getName(list[i]))
                        let low = s.lowercased()
                        if low.contains("framerate") || low.contains("framespersecond") || low.contains("fps")
                            || low.contains("displaylink") || low.contains("renderoption") || low.contains("paused") {
                            sels.append(s)
                        }
                    }
                    free(list)
                }
                c = class_getSuperclass(k)
            }
            let layer = NSStringFromClass(type(of: v.layer))
            var line = "view " + chain.joined(separator: ">") + " layer=" + layer
                + String(format: " scale=%.1f", v.contentScaleFactor)
            if !sels.isEmpty { line += " sel=" + sels.prefix(24).joined(separator: ",") }
            if PerfKnob.fps30 { line += " set30=" + setFrameRate(v, sels) }
            out.append(line)
        }
        if found.isEmpty { out.append("view: хост сцены не найден") }
        return out.joined(separator: " | ")
    }

    /// Попытка 30 к/с: сеттеры с «FrameRate»/«FramesPerSecond» и одним числовым аргументом.
    private static func setFrameRate(_ v: UIView, _ sels: [String]) -> String {
        var done: [String] = []
        for s in sels where s.hasPrefix("set") && s.hasSuffix(":") && s.filter({ $0 == ":" }).count == 1 {
            let sel = NSSelectorFromString(s)
            guard let m = class_getInstanceMethod(type(of: v), sel),
                  let enc = method_copyArgumentType(m, 2) else { continue }
            let t = String(cString: enc)
            free(enc)
            let imp = method_getImplementation(m)
            switch t.first {
            case "q", "l", "Q", "L":
                typealias F = @convention(c) (AnyObject, Selector, Int) -> Void
                unsafeBitCast(imp, to: F.self)(v, sel, 30); done.append(s + t)
            case "i", "I":
                typealias F = @convention(c) (AnyObject, Selector, Int32) -> Void
                unsafeBitCast(imp, to: F.self)(v, sel, 30); done.append(s + t)
            case "d":
                typealias F = @convention(c) (AnyObject, Selector, Double) -> Void
                unsafeBitCast(imp, to: F.self)(v, sel, 30); done.append(s + t)
            case "f":
                typealias F = @convention(c) (AnyObject, Selector, Float) -> Void
                unsafeBitCast(imp, to: F.self)(v, sel, 30); done.append(s + t)
            case "{" where t.contains("fff"):
                typealias F = @convention(c) (AnyObject, Selector, CAFrameRateRange) -> Void
                unsafeBitCast(imp, to: F.self)(v, sel, CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30))
                done.append(s + "range")
            default:
                continue
            }
        }
        return done.isEmpty ? "нет" : done.joined(separator: ",")
    }
}

/// Подпись пробы для теста: раз в 5 с, не видна и не ловит касания.
struct PerfProbeLabel: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { _ in
            Text(PerfProbe.text)
                .font(.system(size: 2))
                .opacity(0.02)
                .accessibilityIdentifier("perf.probe")
        }
        .allowsHitTesting(false)
        .onAppear { PerfProbe.start() }
    }
}
