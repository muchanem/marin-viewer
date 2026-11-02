import Foundation

/// A span of ordinary source that is compiled or collected only for tests,
/// found from parsed node shapes (never from spelling alone). Half-open
/// canonical UTF-8 bytes, already expanded to whole lines where the code
/// owns its lines. Presentation hides it; the source itself never changes.
struct TestRegion: Equatable, Sendable, Identifiable {
    /// The syntactic evidence that made the region test-only.
    enum Evidence: String, Sendable {
        /// Rust `#[cfg(...)]` that is false in every non-test build.
        case cfgTest
        /// Rust `#[test]`-style attribute.
        case testAttribute
        /// Kotlin/JUnit test annotation on a function.
        case testAnnotation
        /// Kotlin test class/object or Python `TestCase` subclass.
        case testClass
        /// pytest function, class, or fixture in a module that imports pytest.
        case pytest
        /// JavaScript/TypeScript test-framework call (`describe`, `it`, `test`, …).
        case testCall
        /// Vitest in-source `if (import.meta.vitest)` block.
        case inSourceTests
    }

    let byteRange: Range<Int>
    let evidence: Evidence
    var id: Int { byteRange.lowerBound }
}
