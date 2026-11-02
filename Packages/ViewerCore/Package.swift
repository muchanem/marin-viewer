// swift-tools-version:6.0
import PackageDescription

// SwiftUI-free logic for the Marin viewer: the diff row model, visible-row
// rules, blame, wordbase formats and review-note state. It builds on the
// Command Line Tools (Swift 6.1) as well as Xcode 26, so it can be tested
// before the app target itself builds; the app depends on it as a local
// package.
let package = Package(
    name: "ViewerCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ViewerCore", targets: ["ViewerCore"]),
    ],
    targets: [
        .target(name: "ViewerCore"),
        .testTarget(
            name: "ViewerCoreTests",
            dependencies: ["ViewerCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
