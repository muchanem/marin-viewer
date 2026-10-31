import Foundation
import Testing
@testable import Radiology

struct SourceLanguageRegistryTests {
    @Test(arguments: [
        ("Sources/App/Scan.swift", "swift"), ("src/lib.rs", "rust"), ("cmd/main.go", "go"),
        ("scan.py", "python"), ("types.pyi", "python"),
        ("app.js", "javascript"), ("App.jsx", "javascript"),
        ("worker.mjs", "javascript"), ("legacy.cjs", "javascript"),
        ("model.ts", "typescript"), ("loader.mts", "typescript"), ("config.cts", "typescript"),
        ("View.tsx", "tsx"), ("Scan.kt", "kotlin"), ("build.gradle.kts", "kotlin"),
        ("scan.c", "c"), ("scan.C", "cpp"), ("scan.h", "cpp"), ("scan.cpp", "cpp"),
        ("scan.cc", "cpp"), ("scan.cxx", "cpp"), ("scan.c++", "cpp"), ("scan.hpp", "cpp"),
        ("scan.hh", "cpp"), ("scan.hxx", "cpp"), ("scan.h++", "cpp"),
        ("scan.ipp", "cpp"), ("scan.inl", "cpp"), ("scan.tpp", "cpp"), ("scan.tcc", "cpp"),
    ])
    func extensionsResolveToTheRightGrammar(path: String, id: String) {
        #expect(SourceLanguageRegistry.language(for: path)?.id == id)
    }

    @Test func pathExtensionMatchingIsCaseInsensitiveAndIgnoresDirectories() {
        #expect(SourceLanguageRegistry.language(for: "deep/Nested.Dir/Main.RS")?.id == "rust")
        #expect(SourceLanguageRegistry.language(for: "Scan.SWIFT")?.id == "swift")
    }

    @Test(arguments: ["README.md", "data.json", "Makefile", "image.png", "notes", "script.sh"])
    func unregisteredFilesHaveNoGrammar(path: String) {
        #expect(SourceLanguageRegistry.language(for: path) == nil)
    }

    @Test func everyLanguageHasAUniqueIdentifierAndDisjointExtensions() {
        let ids = SourceLanguageRegistry.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        var seen = Set<String>()
        for language in SourceLanguageRegistry.all {
            for fileExtension in language.extensions {
                #expect(seen.insert(fileExtension).inserted, "\(fileExtension) is claimed twice")
                #expect(fileExtension == fileExtension.lowercased())
            }
        }
        #expect(SourceLanguageRegistry.all.count == 10)
    }

    @Test func fileClassificationNamesParsedAndPlainLanguages() {
        #expect(RepositoryFile(path: "a/b/Scan.swift").language == "Swift")
        #expect(RepositoryFile(path: "main.rs").language == "Rust")
        #expect(RepositoryFile(path: "View.tsx").language == "TypeScript JSX")
        #expect(RepositoryFile(path: "build.gradle.kts").language == "Kotlin")
        #expect(RepositoryFile(path: "README.md").language == "Markdown")
        #expect(RepositoryFile(path: "unknown.xyz").language == "Plain text")
        #expect(RepositoryFile(path: "main.go").isParsed)
        #expect(!RepositoryFile(path: "README.md").isParsed)
    }
}
