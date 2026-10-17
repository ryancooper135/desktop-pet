// ВРЕМЕННЫЙ ЗОНД аудита (уберётся следующим коммитом): тип модуля с именем импортного типа его затеняет.
// Так enum Capsule из Capsule.swift затеняет SwiftUI.Capsule в целях Pet и PetWidgets (там Shared в том же модуле).
import Foundation

enum DateInterval {}

enum ShadowProbe {
    static func make() -> Any { DateInterval(start: Date(), duration: 1) }
}
