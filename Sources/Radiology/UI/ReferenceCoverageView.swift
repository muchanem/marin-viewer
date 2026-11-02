import SwiftUI

/// Shown only when there is something to say beyond the header's count: no
/// references at all, or stale/unreadable occurrences. One line each.
struct ReferenceCoverageView: View {
    let results: ReferenceResults

    var body: some View {
        if results.referenceCount == 0 {
            ContextStatusLine(text: "No references", detail: "The index records no references to \(results.displayName).")
        }
        if let caveat {
            ContextStatusLine(text: caveat.short, detail: caveat.full, systemImage: "exclamationmark.triangle")
        }
    }

    private var caveat: (short: String, full: String)? {
        var short: [String] = []
        var full: [String] = []
        if results.unmappedCount > 0 {
            short.append("\(results.unmappedCount) stale")
            full.append("\(results.unmappedCount) indexed occurrences no longer match the files on disk. Reindex to refresh.")
        }
        if !results.unreadablePaths.isEmpty {
            short.append("\(results.unreadablePaths.count) unreadable")
            full.append("These indexed files could not be read: " + results.unreadablePaths.joined(separator: ", "))
        }
        return short.isEmpty ? nil : (short.joined(separator: " · "), full.joined(separator: " "))
    }
}
