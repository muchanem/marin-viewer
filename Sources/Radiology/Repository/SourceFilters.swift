import Foundation

/// The two independent Files/PR Changes sidebar options. Hide Tests also hides
/// inline test regions in the reader; Source Files Only filters sidebar rows. Neither
/// changes the repository model, search, indexing, or navigation.
struct SourceFilters: Equatable, Sendable, CustomStringConvertible {
    var hidesTests = false
    var sourceFilesOnly = false

    var isActive: Bool { hidesTests || sourceFilesOnly }

    func includes(_ path: String) -> Bool {
        if hidesTests && TestPathClassifier.isTestPath(path) { return false }
        if sourceFilesOnly && !SourceFileClassifier.isSourceFile(path) { return false }
        return true
    }

    var description: String { "hidesTests=\(hidesTests) sourceFilesOnly=\(sourceFilesOnly)" }

    static let hidesTestsKey = "hideTests"
    static let sourceFilesOnlyKey = "sourceFilesOnly"

    init(hidesTests: Bool = false, sourceFilesOnly: Bool = false) {
        self.hidesTests = hidesTests
        self.sourceFilesOnly = sourceFilesOnly
    }

    init(preferences: UserDefaults) {
        hidesTests = preferences.bool(forKey: Self.hidesTestsKey)
        sourceFilesOnly = preferences.bool(forKey: Self.sourceFilesOnlyKey)
    }

    func save(to preferences: UserDefaults) {
        preferences.set(hidesTests, forKey: Self.hidesTestsKey)
        preferences.set(sourceFilesOnly, forKey: Self.sourceFilesOnlyKey)
    }
}
