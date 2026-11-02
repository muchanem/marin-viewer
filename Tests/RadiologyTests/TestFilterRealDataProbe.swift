import Foundation
import Testing
@testable import Radiology

/// Opt-in, read-only acceptance against the untouched tkos checkout:
/// `RADIOLOGY_REAL_TEST_FILTER_PROBE=1 swift test --filter TestFilterRealDataProbe`.
/// Reads files only; never writes to or runs anything in the repository.
struct TestFilterRealDataProbe {
    static let root = URL(filePath: "/Users/tqbf/codebase/tk/tkos")
    static var enabled: Bool { ProcessInfo.processInfo.environment["RADIOLOGY_REAL_TEST_FILTER_PROBE"] == "1" }

    private func regions(_ path: String) async throws -> (SyntaxSnapshot, [ClosedRange<Int>]) {
        let buffer = try SourceBuffer(path: path, data: Data(contentsOf: Self.root.appending(path: path)))
        let snapshot = try #require(try await SyntaxWorker().parse(buffer))
        let lines = snapshot.testRegions.map { region in
            buffer.line(atByte: region.byteRange.lowerBound)...buffer.line(atByte: max(region.byteRange.lowerBound, region.byteRange.upperBound - 1))
        }
        print("[test-filter probe] \(path): \(lines.map { "\($0.lowerBound)–\($0.upperBound)" }.joined(separator: ", ")) testOnly=\(snapshot.isTestOnlyDocument)")
        return (snapshot, lines)
    }

    @Test(.enabled(if: TestFilterRealDataProbe.enabled))
    func tkosInlineRegionsMatchAcceptanceAnchors() async throws {
        let (_, app) = try await regions("modules/agent/ffi/src/app.rs")
        #expect(app.contains(35...43))
        #expect(app.contains(803...833))
        #expect(app.contains { $0.lowerBound == 3424 })
        #expect(!app.contains { $0.contains(834) || $0.contains(44) })

        let (_, policy) = try await regions("engine/rust/src/snapshot_policy.rs")
        #expect(policy.first?.lowerBound == 16)
        #expect(!policy.contains { $0.contains(9) })

        let (_, kotlin) = try await regions("fonts/src/test/kotlin/inc/tk/os/fonts/FontFilesTest.kt")
        #expect(kotlin.contains { $0.contains(12) && $0.contains(27) && $0.contains(43) })
        let (_, production) = try await regions("fonts/src/main/kotlin/inc/tk/os/fonts/FontFiles.kt")
        #expect(production.isEmpty)

        let (_, python) = try await regions("scripts/test_pr_local.py")
        #expect(python.contains { $0.contains(22) && $0.contains(70) })
        let (_, pythonProduction) = try await regions("scripts/pr-local.py")
        #expect(pythonProduction.isEmpty)

        let (_, typescript) = try await regions("scripts/home-design-inspect.test.ts")
        #expect(typescript.contains { $0.contains(22) && $0.contains(31) })
        let (_, typescriptProduction) = try await regions("scripts/home-design-inspect.ts")
        #expect(typescriptProduction.isEmpty)
    }

    /// Every browsable file with test detection: no failures, and how much
    /// each language's detector finds outside recognized test files.
    @Test(.enabled(if: TestFilterRealDataProbe.enabled))
    func tkosWholeRepositoryDetectionSweep() async throws {
        let snapshot = try await RepositoryWorker().open(Self.root)
        let worker = SyntaxWorker()
        var counts: [String: (files: Int, withRegions: Int, regions: Int)] = [:]
        let started = ContinuousClock.now
        for file in snapshot.files {
            guard let language = SourceLanguageRegistry.language(for: file.path),
                  TestRegionDetector.supportedLanguageIDs.contains(language.id),
                  !TestPathClassifier.isTestPath(file.path),
                  let data = try? Data(contentsOf: Self.root.appending(path: file.path)),
                  let buffer = try? SourceBuffer(path: file.path, data: data) else { continue }
            let syntax = try #require(try await worker.parse(buffer))
            var entry = counts[language.id] ?? (0, 0, 0)
            entry.files += 1
            if !syntax.testRegions.isEmpty || syntax.isTestOnlyDocument { entry.withRegions += 1 }
            entry.regions += syntax.testRegions.count
            if language.id != "rust", !syntax.testRegions.isEmpty {
                let lines = syntax.testRegions.map { "\(buffer.line(atByte: $0.byteRange.lowerBound))–\(buffer.line(atByte: $0.byteRange.upperBound))" }
                print("[test-filter probe] sweep hit \(file.path): \(lines.joined(separator: ", ")) \(syntax.testRegions.map(\.evidence.rawValue))")
            }
            counts[language.id] = entry
        }
        for (language, entry) in counts.sorted(by: { $0.key < $1.key }) {
            print("[test-filter probe] sweep \(language): \(entry.files) non-test files, \(entry.withRegions) with test code, \(entry.regions) regions")
        }
        print("[test-filter probe] sweep took \(started.duration(to: .now))")
        #expect(counts["rust", default: (0, 0, 0)].withRegions > 0)
    }

    @Test(.enabled(if: TestFilterRealDataProbe.enabled))
    func tkosFileTreeFiltersKeepTheFullModel() async throws {
        let snapshot = try await RepositoryWorker().open(Self.root)
        for filters in [SourceFilters(hidesTests: true, sourceFilesOnly: false),
                        SourceFilters(hidesTests: false, sourceFilesOnly: true),
                        SourceFilters(hidesTests: true, sourceFilesOnly: true)] {
            let visible = snapshot.files.filter { filters.includes($0.path) }
            print("[test-filter probe] \(filters): \(visible.count) of \(snapshot.files.count) files")
            #expect(!visible.isEmpty && visible.count < snapshot.files.count)
        }
        let both = SourceFilters(hidesTests: true, sourceFilesOnly: true)
        #expect(both.includes("modules/agent/ffi/src/app.rs"))
        #expect(both.includes("fonts/src/main/kotlin/inc/tk/os/fonts/FontFiles.kt"))
        #expect(!both.includes("fonts/src/test/kotlin/inc/tk/os/fonts/FontFilesTest.kt"))
        #expect(!both.includes("scripts/test_pr_local.py"))
        #expect(!both.includes("scripts/home-design-inspect.test.ts"))
        #expect(!both.includes("modules/agent/ffi/src/app/bundle_tests.rs"))
    }
}
