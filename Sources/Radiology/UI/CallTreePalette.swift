import SwiftUI

/// A coordinated identity palette. System colors adapt to appearance; the
/// same method/file pair keeps its hue across branches and app launches.
enum CallTreePalette {
    static let colors: [Color] = [
        .blue, .teal, .purple, .orange, .pink, .indigo,
        .green, .cyan, .brown, .mint, .red, .yellow,
    ]

    /// Swift's Hasher is randomized per process. FNV-1a over the UTF-8 name,
    /// a field separator, and the repository-relative path is deterministic.
    static func slot(method: String, file: String) -> Int {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in method.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        hash = (hash ^ 0) &* 1_099_511_628_211
        for byte in file.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return Int(hash % UInt64(colors.count))
    }
}
