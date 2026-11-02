import Foundation
import Testing
@testable import Radiology

/// Guards the packaging contract: every registered grammar must find its query
/// resources in the module bundle and compile them against its own node types.
struct SyntaxQueryTests {
    @Test(arguments: SourceLanguageRegistry.all.map(\.id))
    func everyRegisteredLanguageCompilesItsQueries(id: String) throws {
        let language = try #require(SourceLanguageRegistry.language(id: id))
        let queries = try SyntaxQueryLoader.compile(language)
        #expect(queries.highlights != nil, "\(language.displayName) has no highlights query")
        #expect(queries.symbols != nil, "\(language.displayName) has no symbols query")
        #expect(queries.folds != nil, "\(language.displayName) has no folds query")
        #expect(queries.scopes != nil, "\(language.displayName) has no scopes query")
    }

    /// An overlay language must actually receive the base patterns as well as
    /// its own, otherwise TSX would silently lose TypeScript highlighting.
    @Test func overlayLanguagesConcatenateEveryQueryDirectory() throws {
        let tsx = try #require(SourceLanguageRegistry.language(id: "tsx"))
        #expect(tsx.queryDirectories == ["ecmascript", "typescript", "jsx"])
        let combined = try #require(try SyntaxQueryLoader.source(for: tsx, role: .highlights))
        let text = String(decoding: combined, as: UTF8.self)
        #expect(text.contains("(template_string)"))     // ecmascript
        #expect(text.contains("(predefined_type)"))     // typescript
        #expect(text.contains("jsx_opening_element"))   // jsx
    }

    @Test(arguments: SourceLanguageRegistry.all.map(\.id))
    func queryResourcesAreReachableThroughTheModuleBundle(id: String) throws {
        let language = try #require(SourceLanguageRegistry.language(id: id))
        for directory in language.queryDirectories {
            #expect(SyntaxQueryLoader.resourceURL(directory: directory, role: .highlights) != nil,
                    "Queries/\(directory)/highlights.scm is missing from the Radiology resource bundle")
        }
    }

    /// A packaging failure has to name itself rather than crash or go silent.
    @Test func missingQueryResourcesReportADiagnosableError() throws {
        let swift = try #require(SourceLanguageRegistry.language(id: "swift"))
        let unpackaged = SourceLanguage(id: "unpackaged", displayName: "Unpackaged",
                                        extensions: ["zzz"], queryDirectories: ["not-shipped"],
                                        grammar: { swift.treeSitterLanguage.tsLanguage })
        let error = #expect(throws: BrowserError.self) {
            try SyntaxQueryLoader.compile(unpackaged)
        }
        let message = try #require(error).localizedDescription
        #expect(message.contains("Unpackaged"))
        #expect(message.contains("application bundle"))
    }

    /// The same check `Radiology --verify-resources` runs inside a packaged app.
    @Test func resourceVerificationReportsEveryGrammar() {
        let result = ResourceVerification.run()
        #expect(result.isComplete, "\(result.report)")
        for language in SourceLanguageRegistry.all {
            #expect(result.report.contains("ok   \(language.id):"), "\(result.report)")
        }
        #expect(!result.report.contains("FAIL"))
    }
}
