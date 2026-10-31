import Foundation

struct CodePathStep: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let path: String
    let function: String
    let description: String

    var isValid: Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\0")
            && !path.split(separator: "/").contains("..")
            && !function.isEmpty && !description.isEmpty
    }
}
