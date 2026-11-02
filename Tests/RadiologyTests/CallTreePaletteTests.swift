import Testing
@testable import Radiology

struct CallTreePaletteTests {
    @Test func identityColorsStayStableAcrossLaunchesAndIncludeTheFile() {
        // Fixed portable color assignments guard against accidentally using
        // Swift's process-randomized Hasher or dropping one identity field.
        let identities: [(String, String, Int)] = [
            ("launch", "first.rs", 1),
            ("launch", "second.rs", 11),
            ("entry", "entry.rs", 8),
            ("launch", "modules/agent/ffi/src/engine.rs", 4),
            ("café", "src/uni.rs", 3),
            ("ab", "c", 11),
            ("a", "bc", 7),
        ]
        for (method, file, expected) in identities {
            #expect(CallTreePalette.slot(method: method, file: file) == expected)
        }
    }
}
