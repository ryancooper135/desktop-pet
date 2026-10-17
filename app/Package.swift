// swift-tools-version:6.0
// Логика приложения без экрана — для Linux CI (.github/workflows/logic.yml), чтобы не тратить минуты macOS.
// У себя то же самое: wsl -e bash /mnt/c/Users/ryanc/desktop-pet/tools/wsl-test.sh (Swift 6.2 в WSL).
// Приложение собирается через XcodeGen (project.yml), этот файл его не касается.
// Лежит в app/, потому что SwiftPM не пускает пути целей за пределы папки пакета.
// Новый файл в Shared без SwiftUI/UIKit/WidgetKit/ActivityKit — допиши его в список ниже.

import PackageDescription

let package = Package(
    name: "PetLogic",
    // Synchronization.Atomic (Synth.swift) — с iOS 18 / macOS 15; приложение и так на iOS 26, на Linux не важно.
    platforms: [.iOS(.v18), .macOS(.v15)],
    dependencies: [
        .package(path: "../core/swift"),
    ],
    targets: [
        // Имя «Pet», как у цели приложения: тесты пишут `@testable import Pet` и там, и тут.
        .target(
            name: "Pet",
            // Пакет по пути получает имя папки («swift»), поэтому продукт с явным пакетом:
            // голое "PetCore" SwiftPM 5.2+ не примет.
            dependencies: [.product(name: "PetCore", package: "swift")],
            path: "Shared",
            sources: [
                "AppGroup.swift",
                "Backup.swift",
                "Capsule.swift",
                "Catalog.swift",
                "Clock.swift",
                "Coat.swift",
                "Economy.swift",
                "Finds.swift",
                "Guides.swift",
                "ForecastTools.swift",
                "IslandPlan.swift",
                "LineRotation.swift",
                "Lines.swift",
                "NotificationPlanner.swift",
                "Paths.swift",
                "PetAction.swift",
                "PetRunner.swift",
                "PetStore.swift",
                "Postcards.swift",
                "Presenter.swift",
                "SaveFile.swift",
                "SoundRecipes.swift",
                "StableHash.swift",
                "Synth.swift",
                "Tastes.swift",
            ]
        ),
        .testTarget(
            name: "PetTests",
            dependencies: ["Pet", .product(name: "PetCore", package: "swift")],
            path: "Tests",
            sources: [
                "PetLogicTests.swift",
                "StoreTests.swift",
                "LineRotationTests.swift",
                "SoundTests.swift",
                "WalkTests.swift",
                "TastesTests.swift",
                "EconomyTests.swift",
                "CoatTests.swift",
                "PostcardsTests.swift",
                "Wave5SeamTests.swift",
                "PetRunnerCoverageTests.swift",
                "SaveFileCoverageTests.swift",
                "PetStoreRecoveryTests.swift",
                "NotificationPlannerCoverageTests.swift",
                "PresenterCoverageTests.swift",
                "CatalogHashTests.swift",
                "TimelineTests.swift",
                "GuideTests.swift",
                "SnapshotCatalog.swift",  // отсюда нужен только StoreHooks, вью закрыты #if canImport(UIKit)
            ]
        ),
    ]
)
