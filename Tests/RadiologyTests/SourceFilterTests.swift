import Foundation
import Testing
@testable import Radiology

/// Path classification, tree pruning, and the two options' independence,
/// persistence, and synchronization with the browsed repository.
@MainActor
struct SourceFilterTests {
    @Test func testPathsAreRecognizedByComponentsAndNamesNeverBySubstring() {
        let tests = [
            "engine/rust/tests/snapshot.rs", "app/src/test/kotlin/inc/AppTest.kt", "app/src/androidTest/X.kt",
            "lib/src/jvmTest/kotlin/A.kt", "lib/src/commonTest/A.kt", "lib/src/androidUnitTest/A.kt",
            "lib/src/testFixtures/kotlin/F.kt", "web/__tests__/a.ts", "web/__mocks__/fs.ts", "web/__fixtures__/x.json",
            "pkg/testdata/golden.txt", "tools/tk-apps/test-support/developer.ts", "Tests/RadiologyTests/A.swift",
            "scripts/home-design-inspect.test.ts", "ui/View.spec.tsx", "scripts/build-tree-state.test.py",
            "types/api.test-d.ts", "server/handler_test.go", "src/catalog/tests.rs", "src/app/bundle_tests.rs",
            "src/snapshot_profiles_test.rs", "scripts/test_pr_local.py", "pkg/util_test.py", "app/tests.py",
            "conftest.py", "native/codec_unittest.cc", "native/codec_test.cpp",
        ]
        for path in tests { #expect(TestPathClassifier.isTestPath(path), "\(path) is test code") }
        let production = [
            "src/contest.rs", "src/latest.ts", "src/attestation.py", "pkg/testing/helpers.go", "spec/openapi.yaml",
            "e2e/run.ts", "fixtures/seed.json", "src/main/kotlin/inc/SpeedTest.kt", "src/test.rs", "src/testable.ts",
            "scripts/pr-local.py", "scripts/home-design-inspect.ts", "src/main/kotlin/tested/Thing.kt",
            "docs/testing.md", "src/protest.go", "README.test.md", "lib/src/Test/A.kt", "lib/src/main/kotlin/jvmTest/A.kt",
        ]
        for path in production { #expect(!TestPathClassifier.isTestPath(path), "\(path) is not test code") }
    }

    @Test func sourceFilesExcludeArtifactsDependenciesGeneratedDocsAndManifests() {
        let source = [
            "modules/agent/ffi/src/app.rs", "fonts/src/main/kotlin/inc/tk/os/fonts/FontFiles.kt", "scripts/pr-local.py",
            "web/App.tsx", "include/codec.h", "native/codec.hpp", "native/codec.cc", "ios/Bridge.m", "ios/Bridge.mm",
            "Sources/Radiology/AppModel.swift", "java/Main.java", "tools/run.sh", "db/schema.sql", "api/service.proto",
            "build.rs", "src/bin/cli.rs", "lib/src/test/kotlin/X.kt", "types/global.d.ts", "src/contest.rs",
            "web/src/main.mjs", "scripts/release.kts",
        ]
        for path in source { #expect(SourceFileClassifier.isSourceFile(path), "\(path) is source") }
        let other = [
            "target/debug/build/foo/out/bindings.rs", "crate/target/release/x.rs", "node_modules/react/index.js",
            "web/node_modules/a/b.ts", "app/build/generated/source/R.kt", "dist/bundle.js", "out/main.js",
            "vendor/github.com/x/y.go", ".venv/lib/python3.12/site-packages/x.py", "pkg/__pycache__/m.py",
            ".gradle/caches/x.kt", ".next/server/page.js", "coverage/lcov-report/a.js", "Pods/AFNetworking/A.m",
            "proto/generated/a.pb.go", "api/a.pb.go", "api/a_pb2.py", "web/vendor.min.js", "tools/tk-apps/home/bricks.generated.ts",
            "README.md", "docs/guide.md", "notes.txt", "Cargo.toml", "Cargo.lock", "package.json", "tsconfig.json",
            "Package.swift", "app/build.gradle.kts", "settings.gradle.kts", "setup.py", "vite.config.ts",
            "jest.config.cjs", ".eslintrc.js", "Makefile", "Dockerfile", "web/index.html", "web/site.css",
            "assets/logo.png", ".github/workflows/ci.yml",
        ]
        for path in other { #expect(!SourceFileClassifier.isSourceFile(path), "\(path) is not source") }
    }

    @Test func treeIsPrunedOrderedAndBothOptionsCombineIndependently() {
        let files = [
            "README.md", "Cargo.toml", "docs/guide.md", "src/app.rs", "src/contest.rs", "src/app/bundle_tests.rs",
            "src/main/kotlin/A.kt", "src/test/kotlin/ATest.kt", "tests/fixtures/data.json", "tests/integration.rs",
            "web/App.tsx", "web/App.test.tsx", "web/package.json",
        ].map(RepositoryFile.init(path:))
        func paths(_ filters: SourceFilters) -> [String] {
            func walk(_ nodes: [FileNode]) -> [String] { nodes.flatMap { [$0.path] + walk($0.children ?? []) } }
            return walk(FileNode.tree(files: files.filter { filters.includes($0.path) }))
        }
        #expect(paths(SourceFilters()) == walk(FileNode.tree(files: files)))
        #expect(paths(SourceFilters(hidesTests: true)) == [
            "docs", "docs/guide.md", "src", "src/main", "src/main/kotlin", "src/main/kotlin/A.kt",
            "src/app.rs", "src/contest.rs", "web", "web/App.tsx", "web/package.json", "Cargo.toml", "README.md",
        ])
        #expect(paths(SourceFilters(sourceFilesOnly: true)) == [
            "src", "src/app", "src/app/bundle_tests.rs", "src/main", "src/main/kotlin", "src/main/kotlin/A.kt",
            "src/test", "src/test/kotlin", "src/test/kotlin/ATest.kt", "src/app.rs", "src/contest.rs",
            "tests", "tests/integration.rs", "web", "web/App.test.tsx", "web/App.tsx",
        ])
        #expect(paths(SourceFilters(hidesTests: true, sourceFilesOnly: true)) == [
            "src", "src/main", "src/main/kotlin", "src/main/kotlin/A.kt", "src/app.rs", "src/contest.rs",
            "web", "web/App.tsx",
        ], "empty directories (src/app, docs, tests) are pruned")

        func walk(_ nodes: [FileNode]) -> [String] { nodes.flatMap { [$0.path] + walk($0.children ?? []) } }
    }

    private static func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(condition(), "Async model operation timed out")
    }

    @Test func modelFiltersTheTreeOnlyAndKeepsReaderStateAndPreferences() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = ["README.md": "# Notes\n", "src/app.rs": "fn main() {}\n", "src/contest.rs": "fn contest() {}\n",
                     "tests/integration.rs": "#[test]\nfn t() {}\n", "docs/guide.md": "guide\n"]
        for (path, text) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        let suite = "RadiologyTests." + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = AppModel(preferences: preferences)
        model.openRepository(root)
        try await Self.waitUntil { !model.isOpening && model.repository != nil }
        #expect(model.visibleFileCount == 5 && model.fileTree.map(\.path) == ["docs", "src", "tests", "README.md"])
        model.fileTreeExpansion.setExpanded(true, path: "src")

        model.openFile("README.md")
        try await Self.waitUntil { model.source?.path == "README.md" && !model.isLoadingSource }
        let entries = model.history.entries
        model.sourceFilters.sourceFilesOnly = true
        #expect(model.fileTree.map(\.path) == ["src", "tests"])
        #expect(model.visibleFileCount == 3)
        #expect(model.source?.path == "README.md" && model.selectedPath == "README.md", "the open file stays open")
        #expect(model.isOpenFileFilteredOut)
        #expect(model.history.entries == entries)
        #expect(model.repository?.files.count == 5, "the repository model keeps every file")

        model.sourceFilters.hidesTests = true
        #expect(model.fileTree.map(\.path) == ["src"] && model.visibleFileCount == 2)
        model.fileQuery = "rs"
        model.filterFiles()
        #expect(model.filteredFiles.map(\.path) == ["src/app.rs", "src/contest.rs"])
        model.sourceFilters.sourceFilesOnly = false
        #expect(model.filteredFiles.map(\.path) == ["src/app.rs", "src/contest.rs"], "the field list follows the options")
        #expect(model.fileTree.map(\.path) == ["docs", "src", "README.md"], "Hide Tests alone still hides tests/")
        #expect(model.fileTreeExpansion.isExpanded("src"), "filtering keeps directory expansion")

        // Persisted app-wide; a fresh model starts with the same options.
        let restored = AppModel(preferences: preferences)
        #expect(restored.sourceFilters == SourceFilters(hidesTests: true, sourceFilesOnly: false))
        model.clearSourceFilters()
        #expect(AppModel(preferences: preferences).sourceFilters == SourceFilters())
        #expect(model.visibleFileCount == 5)

        // Reload recomputes the tree from the refreshed listing.
        model.sourceFilters.sourceFilesOnly = true
        try Data("fn added() {}\n".utf8).write(to: root.appending(path: "src/added.rs"))
        model.refresh()
        try await Self.waitUntil { !model.isOpening && model.repository?.files.count == 6 }
        #expect(model.visibleFileCount == 4)
        #expect(model.fileTreeExpansion.isExpanded("src"))
    }
}
