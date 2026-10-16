// Правила из config/economy.json — порт core/ts/src/rules.ts.

import Foundation

public enum Need: String, CaseIterable, Codable, Sendable { case food, clean, energy, fun, love, walk, look }
public enum Distress: String, CaseIterable, Codable, Sendable { case starve, dirty, toska }
public enum HomeLine: String, CaseIterable, Codable, Sendable { case bath, bed, kitchen, kennel, play, yard }

public typealias Vals = [Need: Double]

/// Значение эффекта: число или флаг.
public enum EffectValue: Equatable { case number(Double), flag(Bool) }
public typealias Effect = [String: EffectValue]

public enum RulesError: Error { case badCondition(String), missing(String) }

/// Условие вида "food < 20" или "fun < 10 && love < 10".
public struct Cond {
    struct Part { let need: Need; let op: String; let x: Double }
    let parts: [Part]

    public init(_ expr: String) throws {
        let re = try NSRegularExpression(pattern: "^\\s*(\\w+)\\s*(<=|>=|==|<|>)\\s*(-?\\d+(?:\\.\\d+)?)\\s*$")
        parts = try expr.components(separatedBy: "&&").map { p in
            let ns = p as NSString
            guard let m = re.firstMatch(in: p, range: NSRange(location: 0, length: ns.length)),
                  let need = Need(rawValue: ns.substring(with: m.range(at: 1))),
                  let x = Double(ns.substring(with: m.range(at: 3))) else { throw RulesError.badCondition(expr) }
            return Part(need: need, op: ns.substring(with: m.range(at: 2)), x: x)
        }
    }

    public func callAsFunction(_ v: Vals) -> Bool {
        parts.allSatisfy { p in
            let a = v[p.need] ?? 0
            switch p.op {
            case "<": return a < p.x
            case "<=": return a <= p.x
            case ">": return a > p.x
            case ">=": return a >= p.x
            default: return a == p.x
            }
        }
    }
}

public struct DistressRule {
    public let cond: Cond
    public let graceH: Double
    public let hoursPerHeart: Double
}

public struct Rules {
    public let needs: [Need: [String: Double]]
    public let cross: [(cond: Cond, then: Effect)]
    public let distress: [Distress: DistressRule]
    public let heartsMax: Double, regenPerH: Double, regenNightX: Double, regenAllGe: Double
    public let lastChanceH: Double, noDeathAfterWakeH: Double
    public let bedMin: Int, wakeMin: Int, afterBedMin: Int, afterWakeMin: Int
    public let bathMinutes: [Double]
    public let petLove: Double, petCooldownMin: Double
    public let funGain: Double, energyCost: Double
    public let food: [String: Effect]
    public let items: [String: Effect]
    public let home: [HomeLine: [Effect]]
    public let warnLow: Double = 30

    public func need(_ n: Need, _ key: String) -> Double { needs[n]?[key] ?? 0 }

    public init(data: Data) throws {
        try self.init(json: JSONDecoder().decode(JSONValue.self, from: data))
    }

    public init(json cfg: JSONValue) throws {
        func num(_ v: JSONValue, _ what: String) throws -> Double {
            guard let d = v.double else { throw RulesError.missing(what) }
            return d
        }
        func effect(_ v: JSONValue) -> Effect {
            var out: Effect = [:]
            for (k, x) in v.object where !k.hasPrefix("_") {
                switch x {
                case .number(let n): out[k] = .number(n)
                case .bool(let b): out[k] = .flag(b)
                default: break
                }
            }
            return out
        }
        func hhmm(_ s: String?) -> Int {
            let p = (s ?? "0:0").split(separator: ":").map { Int($0) ?? 0 }
            return p[0] * 60 + (p.count > 1 ? p[1] : 0)
        }
        let care = cfg["care"], h = care["hearts"]

        var needs: [Need: [String: Double]] = [:]
        for n in Need.allCases {
            var m: [String: Double] = [:]
            for (k, v) in care["needs"][n.rawValue].object { if let d = v.double { m[k] = d } }
            needs[n] = m
        }
        self.needs = needs
        cross = try care["cross_effects"].array.map { (cond: try Cond($0["if"].string ?? ""), then: effect($0["then"])) }

        var distress: [Distress: DistressRule] = [:]
        for d in Distress.allCases {
            let x = h["distress"][d.rawValue]
            distress[d] = DistressRule(cond: try Cond(x["when"].string ?? ""),
                                       graceH: try num(x["grace_h_awake"], "grace_h_awake"),
                                       hoursPerHeart: try num(x["hours_per_heart"], "hours_per_heart"))
        }
        self.distress = distress

        heartsMax = try num(h["max"], "hearts.max")
        regenPerH = try num(h["regen_per_h_awake"], "regen_per_h_awake")
        regenNightX = try num(h["regen_night_x"], "regen_night_x")
        regenAllGe = try num(h["regen_requires_all_ge"], "regen_requires_all_ge")
        lastChanceH = try num(h["last_heart"]["timer_h_awake"], "timer_h_awake")
        noDeathAfterWakeH = try num(h["last_heart"]["no_death_first_h_after_wake"], "no_death_first_h_after_wake")

        let night = care["night"]
        bedMin = hhmm(night["default_bed"].string)
        wakeMin = hhmm(night["default_wake"].string)
        afterBedMin = Int(try num(night["pet_sleep_offset_min"]["after_bed"], "after_bed"))
        afterWakeMin = Int(try num(night["pet_sleep_offset_min"]["after_wake"], "after_wake"))

        bathMinutes = care["bath_minutes_by_level"].array.compactMap(\.double)
        petLove = try num(care["actions"]["pet"]["love"], "actions.pet.love")
        petCooldownMin = try num(care["cooldowns_min"]["pet"], "cooldowns_min.pet")
        funGain = try num(cfg["minigames"]["fun_gain"], "minigames.fun_gain")
        energyCost = try num(cfg["minigames"]["energy_cost"], "minigames.energy_cost")

        var food: [String: Effect] = [:]
        for f in cfg["shop"]["food"].array { if let id = f["id"].string { food[id] = effect(f) } }
        self.food = food
        var items: [String: Effect] = [:]
        for f in cfg["shop"]["consumables"].array { if let id = f["id"].string { items[id] = effect(f) } }
        self.items = items
        var home: [HomeLine: [Effect]] = [:]
        for l in HomeLine.allCases { home[l] = cfg["home_upgrades"][l.rawValue]["levels"].array.map { effect($0["buff"]) } }
        self.home = home
    }
}
