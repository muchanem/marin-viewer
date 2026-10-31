import Foundation

/// Named destinations resolve in the checkout, or After in a PR review.
struct CodePath: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let title: String
    let steps: [CodePathStep]

    var isValid: Bool {
        !title.isEmpty && !steps.isEmpty && steps.allSatisfy(\.isValid)
            && Set(steps.map(\.id)).count == steps.count
    }

    var text: String {
        func escape(_ value: String) -> String {
            value.replacing("\\", with: "\\\\").replacing(":", with: "\\:")
        }
        return ([title] + steps.map {
            "\(escape($0.path)):\(escape($0.function)):\($0.description)"
        }).joined(separator: "\n")
    }
}
