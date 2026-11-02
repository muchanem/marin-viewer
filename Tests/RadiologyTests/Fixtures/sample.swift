// Swift scan reader — 放射線
import Foundation

let maxScans = 10

protocol Renderer {
    func render() -> String
}

struct Scan: Renderer {
    let title: String
    var count: Int

    init(title: String) {
        self.title = title
        self.count = 0
    }

    func render() -> String {
        var parts = [title, "胸部"]
        for index in 0..<count {
            parts.append("\(index)")
        }
        if parts.isEmpty {
            return ""
        }
        return parts.joined(separator: ",")
    }
}

typealias Titles = [String]

final class Registry {
    private var scans: [Scan] = []
    func add(_ scan: Scan) { scans.append(scan) }
    deinit { scans.removeAll() }
}
