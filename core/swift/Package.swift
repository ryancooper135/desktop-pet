// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PetCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "PetCore", targets: ["PetCore"])],
    targets: [
        .target(name: "PetCore"),
        .testTarget(name: "PetCoreTests", dependencies: ["PetCore"]),
    ]
)
