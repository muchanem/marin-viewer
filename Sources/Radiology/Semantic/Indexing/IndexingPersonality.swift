import Foundation

enum IndexingPersonality: String, CaseIterable, Codable, Sendable, Identifiable {
    case `default`, sel4
    var id: String { rawValue }
    var name: String { self == .default ? "Default" : "seL4" }
    var summary: String {
        self == .default ? "Detect projects and use their available build settings."
            : "Index kernel and user APIs across architectures and configurations."
    }
}
