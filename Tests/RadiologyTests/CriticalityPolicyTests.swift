import Foundation
import Testing
@testable import Radiology

/// The deterministic precedence table in plans/critical-lens.md, exercised
/// on a hand-built index with one repository crate and external symbols.
struct CriticalityPolicyTests {
    static let repoFunction = "rust-analyzer cargo app 0.1.0 main/run()."
    static let inactiveRepoItem = "rust-analyzer cargo app 0.1.0 android/only()."
    static let unwrap = "rust-analyzer cargo core . option/Option#unwrap()."
    static let fsOpen = "rust-analyzer cargo std https://github.com/rust-lang/rust/library/std fs/OpenOptions#open()."
    static let ioError = "rust-analyzer cargo std https://github.com/rust-lang/rust/library/std io/error/impl#[Error]last_os_error()."
    static let ioKind = "rust-analyzer cargo std https://github.com/rust-lang/rust/library/std io/error/ErrorKind#WouldBlock#"
    static let bufReader = "rust-analyzer cargo std https://github.com/rust-lang/rust/library/std io/buffered/bufreader/BufReader#new()."
    static let stdout = "rust-analyzer cargo std https://github.com/rust-lang/rust/library/std io/stdio/stdout()."
    static let readTrait = "rust-analyzer cargo std https://github.com/rust-lang/rust/library/std io/Read#read()."
    static let asRawFd = "rust-analyzer cargo std https://github.com/rust-lang/rust/library/std os/fd/raw/impl#[`fs::File`][AsRawFd]as_raw_fd()."
    static let flock = "rust-analyzer cargo libc 0.2.189 flock()."
    static let sqlite = "rust-analyzer cargo libsqlite3-sys 0.35.0 sqlite3_open()."
    static let unknownSys = "rust-analyzer cargo mystery-sys 1.0.0 do_thing()."
    static let ptrRead = "rust-analyzer cargo core . ptr/read()."
    static let serde = "rust-analyzer cargo serde_json 1.0.151 value/Value#as_object()."
    static let tokioFile = "rust-analyzer cargo tokio 1.53.1 fs/File#open()."
    static let tokioSpawn = "rust-analyzer cargo tokio 1.53.1 task/spawn()."
    static let externFn = "rust-analyzer cargo app 0.1.0 ffi/v8__IsSandboxEnabled()."
    static let goStd = "scip-go gomod std go1.22 fmt/Println()."

    static func makeIndex() -> SemanticIndex {
        var document = SCIPDocument()
        document.relativePath = "src/main.rs"
        document.positionEncoding = 1
        var run = SCIPSymbolInformation(); run.symbol = repoFunction; run.kind = 17; run.displayName = "run"; run.signature = "fn run()"
        var ext = SCIPSymbolInformation(); ext.symbol = externFn; ext.kind = 17; ext.signature = "unsafe extern \"C\" fn v8__IsSandboxEnabled() -> bool"
        document.symbols = [run, ext]
        var definition = SCIPOccurrence(); definition.symbol = repoFunction; definition.symbolRoles = 1
        definition.range = SCIPRange(startLine: 0, startCharacter: 3, endLine: 0, endCharacter: 6)
        var externDefinition = SCIPOccurrence(); externDefinition.symbol = externFn; externDefinition.symbolRoles = 1
        externDefinition.range = SCIPRange(startLine: 1, startCharacter: 0, endLine: 1, endCharacter: 5)
        var reference = SCIPOccurrence(); reference.symbol = unwrap
        reference.range = SCIPRange(startLine: 2, startCharacter: 0, endLine: 2, endCharacter: 6)
        document.occurrences = [definition, externDefinition, reference]
        var index = SCIPIndex()
        index.metadata.toolName = "rust-analyzer"
        index.documents = [document]
        return SemanticIndex(indexes: [index])
    }

    static func id(_ symbol: String) -> SemanticSymbolID { SemanticSymbolID(symbol: symbol, document: "src/main.rs") }

    @Test func headerParsingHandlesPlaceholderAndURLVersions() {
        #expect(SCIPSymbolHeader(Self.unwrap)?.packageName == "core")
        #expect(SCIPSymbolHeader(Self.fsOpen)?.packageName == "std")
        #expect(SCIPSymbolHeader(Self.fsOpen)?.version.hasPrefix("https://") == true)
        #expect(SCIPSymbolHeader(Self.flock)?.packageKey == "rust-analyzer cargo libc")
        #expect(SCIPSymbolHeader("local 3") == nil)
        #expect(SCIPSymbolHeader("rust-analyzer cargo . . x/")?.packageName == nil)
        #expect(SCIPSymbolHeader("a b  c d e f/")?.manager == "b c", "double space is an escaped space inside a field")
        #expect(SCIPSymbolString.descriptorText(of: Self.fsOpen) == "fs/OpenOptions#open().")
    }

    @Test func builtInPrecedence() {
        let index = Self.makeIndex()
        let policy = CriticalityPolicy(repositoryPackages: CriticalityPolicy.repositoryPackages(in: index))
        #expect(policy.repositoryPackages == ["app"])
        func classify(_ symbol: String) -> CriticalityClassification { policy.classify(Self.id(symbol), in: index) }
        #expect(classify(Self.repoFunction) == .init(criticality: .critical, reason: .repositoryDefinition))
        #expect(classify(Self.inactiveRepoItem) == .init(criticality: .critical, reason: .repositoryDefinition), "a repository crate's cfg-inactive item has no definition but belongs to the repository")
        #expect(classify(Self.unwrap) == .init(criticality: .ordinary, reason: .runtimePlumbing))
        #expect(classify(Self.fsOpen) == .init(criticality: .critical, reason: .systemAPI))
        #expect(classify(Self.ioError) == .init(criticality: .ordinary, reason: .runtimePlumbing), "io::Error is excluded plumbing")
        #expect(classify(Self.ioKind) == .init(criticality: .ordinary, reason: .runtimePlumbing))
        #expect(classify(Self.bufReader) == .init(criticality: .ordinary, reason: .runtimePlumbing))
        #expect(classify(Self.stdout) == .init(criticality: .critical, reason: .systemAPI))
        #expect(classify(Self.readTrait) == .init(criticality: .critical, reason: .systemAPI))
        #expect(classify(Self.asRawFd) == .init(criticality: .critical, reason: .ffiPackage), "std os/ is an FFI descriptor")
        #expect(classify(Self.flock) == .init(criticality: .critical, reason: .ffiPackage))
        #expect(classify(Self.sqlite) == .init(criticality: .critical, reason: .ffiPackage))
        #expect(classify(Self.unknownSys) == .init(criticality: .unknown, reason: .external), "-sys is a naming convention, not evidence")
        #expect(classify(Self.ptrRead) == .init(criticality: .ordinary, reason: .runtimePlumbing), "raw pointer helpers are not promoted")
        #expect(classify(Self.serde) == .init(criticality: .unknown, reason: .external))
        #expect(classify(Self.tokioFile) == .init(criticality: .critical, reason: .systemAPI))
        #expect(classify(Self.tokioSpawn) == .init(criticality: .unknown, reason: .external))
        #expect(classify(Self.externFn) == .init(criticality: .critical, reason: .ffiSignature), "indexed extern signature outranks the repository reason")
        #expect(classify(Self.goStd) == .init(criticality: .unknown, reason: .external), "no profile for other schemes")
        #expect(classify("local 3") == .init(criticality: .unknown, reason: .local))
    }

    @Test func overridesWinAndSymbolBeatsPackage() {
        let index = Self.makeIndex()
        var overrides = CriticalityOverrides()
        overrides.setPackage("rust-analyzer cargo std", to: .ordinary)
        overrides.setSymbol(Self.fsOpen, to: .critical)
        overrides.setSymbol(Self.repoFunction, to: .ordinary)
        overrides.setSymbol("local 3", to: .critical)
        #expect(overrides.symbols["local 3"] == nil, "locals are never stored")
        let policy = CriticalityPolicy(repositoryPackages: ["app"], overrides: overrides)
        #expect(policy.classify(Self.id(Self.asRawFd), in: index) == .init(criticality: .ordinary, reason: .packageOverride))
        #expect(policy.classify(Self.id(Self.fsOpen), in: index) == .init(criticality: .critical, reason: .symbolOverride))
        #expect(policy.classify(Self.id(Self.repoFunction), in: index) == .init(criticality: .ordinary, reason: .symbolOverride))
        #expect(policy.builtInClassification(Self.id(Self.repoFunction), in: index).reason == .repositoryDefinition)
        #expect(policy.classify(Self.id("local 3"), in: index).reason == .local)
        // Reset returns to the built-in result.
        var reset = overrides
        reset.setSymbol(Self.fsOpen, to: nil)
        reset.setPackage("rust-analyzer cargo std", to: .unknown)
        let restored = CriticalityPolicy(repositoryPackages: ["app"], overrides: reset)
        #expect(restored.classify(Self.id(Self.fsOpen), in: index).reason == .systemAPI)
        #expect(restored.classify(Self.id(Self.asRawFd), in: index).reason == .ffiPackage)
    }
}
