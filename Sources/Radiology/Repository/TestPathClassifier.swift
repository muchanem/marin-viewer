import Foundation

/// Whole test files and test directories, by exact path components and file
/// name patterns. Never by substring: `contest.rs`, `latest.ts`,
/// `attestation.py`, and `testing/` are not tests. See plans/source-filters.md.
enum TestPathClassifier {
    static let testDirectories: Set<String> = [
        "test", "tests", "Tests", "__tests__", "__mocks__", "__fixtures__", "testdata",
        "test-support", "test_support", "testsupport", "test-utils", "test_utils", "testutils",
        "androidTest", "testFixtures",
    ]
    static let sourceExtensions: Set<String> = [
        "js", "jsx", "mjs", "cjs", "ts", "tsx", "mts", "cts", "py", "rs", "go", "kt", "kts", "java",
        "swift", "rb", "c", "cc", "cpp", "cxx", "m", "mm", "scala", "dart",
    ]

    static func isTestPath(_ path: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        guard let name = components.last else { return false }
        let directories = components.dropLast()
        if directories.contains(where: testDirectories.contains) { return true }
        // Gradle/Kotlin source sets: src/jvmTest, src/commonTest, src/androidUnitTest, …
        for (index, directory) in directories.enumerated() where index > 0 && directories[directories.startIndex + index - 1] == "src" {
            if directory.count > 4, directory.hasSuffix("Test"), directory.first?.isLowercase == true { return true }
        }
        return isTestFileName(name)
    }

    static func isTestFileName(_ name: String) -> Bool {
        let url = URL(filePath: name)
        let fileExtension = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        guard sourceExtensions.contains(fileExtension.lowercased()) else { return false }
        // a.test.ts, a.spec.tsx, build.test.py, a.test-d.ts
        if stem.hasSuffix(".test") || stem.hasSuffix(".spec") || stem.hasSuffix(".test-d") { return true }
        switch fileExtension {
        case "go":
            return stem.hasSuffix("_test")
        case "rs":
            return stem == "tests" || stem.hasSuffix("_test") || stem.hasSuffix("_tests")
        case "py":
            return stem.hasPrefix("test_") || stem.hasSuffix("_test") || stem == "tests" || stem == "conftest"
        case "c", "cc", "cpp", "cxx":
            return stem.hasSuffix("_test") || stem.hasSuffix("_unittest")
        default:
            return false
        }
    }
}
