import Foundation

/// Compiles every registered grammar's queries out of the running bundle.
///
/// `Radiology --verify-resources` runs this and exits, which proves a packaged
/// `.app` carries and can load all of its parser and query resources under a
/// Finder-style launch, where the working directory and `PATH` are not the
/// developer's shell. It is also the unit under `SyntaxQueryTests`.
enum ResourceVerification {
    struct Result: Sendable {
        let report: String
        let isComplete: Bool
    }

    static func run() -> Result {
        var lines: [String] = []
        var isComplete = true
        for language in SourceLanguageRegistry.all {
            do {
                let queries = try SyntaxQueryLoader.compile(language)
                let roles = SyntaxQueryRole.allCases.filter { queries.query(for: $0) != nil }
                let grammarVersion = language.treeSitterLanguage.ABIVersion
                lines.append("ok   \(language.id): ABI \(grammarVersion), "
                             + "\(roles.map(\.rawValue).joined(separator: "+")), "
                             + "queries from \(language.queryDirectories.joined(separator: "+"))")
            } catch {
                isComplete = false
                lines.append("FAIL \(language.id): \(error.localizedDescription)")
            }
        }
        for name in ["kotlin-index.sh", "kotlin-index.gradle", "install-kotlin-indexer.sh", "install-clang-indexer.sh"] + IndexingPersonalityStore.scripts {
            if FileManager.default.isReadableFile(atPath: ScipKotlinIndexer.script(name).path) {
                lines.append("ok   indexing script: \(name)")
            } else {
                isComplete = false
                lines.append("FAIL indexing script: \(name)")
            }
        }
        for personality in IndexingPersonality.allCases {
            do {
                let url = try IndexingPersonalityStore.template(personality)
                _ = try IndexingPersonalitySettings(personality: personality, url: url, data: Data(contentsOf: url))
                lines.append("ok   indexing personality: \(personality.rawValue).toml")
            } catch {
                isComplete = false
                lines.append("FAIL indexing personality: \(error.localizedDescription)")
            }
        }
        lines.append(isComplete
                     ? "All \(SourceLanguageRegistry.all.count) grammars loaded their queries."
                     : "Some grammars could not load their queries.")
        return Result(report: lines.joined(separator: "\n"), isComplete: isComplete)
    }
}
