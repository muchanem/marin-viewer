// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Radiology",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.9.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter", .upToNextMinor(from: "0.25.0")),
        // Upstream publishes generated C sources on dedicated tags for native consumers.
        .package(url: "https://github.com/alex-pinkus/tree-sitter-swift", revision: "0.7.3-with-generated-files"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-rust", exact: "0.24.2"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-go", exact: "0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-python", exact: "0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-javascript", exact: "0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript", exact: "0.23.2"),
        .package(url: "https://github.com/fwcd/tree-sitter-kotlin", exact: "0.3.8"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-c", exact: "0.24.2"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-cpp", exact: "0.23.4"),
    ],
    targets: [
        // Upstream tree-sitter-javascript and tree-sitter-python publish SwiftPM
        // manifests that probe for `src/scanner.c` with a relative path, so the
        // external scanners never compile. Their sources are vendored here at the
        // pinned grammar versions; see Sources/GrammarScanners/PROVENANCE.md.
        .target(
            name: "GrammarScanners",
            cSettings: [
                .headerSearchPath("vendor"),
                // The vendored sources are kept byte-identical to upstream, which
                // builds them without this warning; silencing it here keeps
                // Radiology's own build clean without editing vendored code.
                .unsafeFlags(["-Wno-shorten-64-to-32"]),
            ]
        ),
        .executableTarget(
            name: "Radiology",
            dependencies: [
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitter", package: "tree-sitter"),
                .product(name: "TreeSitterSwift", package: "tree-sitter-swift"),
                .product(name: "TreeSitterRust", package: "tree-sitter-rust"),
                .product(name: "TreeSitterGo", package: "tree-sitter-go"),
                .product(name: "TreeSitterPython", package: "tree-sitter-python"),
                .product(name: "TreeSitterJavaScript", package: "tree-sitter-javascript"),
                .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
                .product(name: "TreeSitterKotlin", package: "tree-sitter-kotlin"),
                .product(name: "TreeSitterC", package: "tree-sitter-c"),
                .product(name: "TreeSitterCPP", package: "tree-sitter-cpp"),
                "GrammarScanners",
            ],
            resources: [.copy("Queries"), .copy("IndexingScripts"), .copy("IndexingPersonalities"), .copy("Help")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(name: "RadiologyTests", dependencies: ["Radiology"], resources: [.copy("Fixtures")]),
    ]
)
