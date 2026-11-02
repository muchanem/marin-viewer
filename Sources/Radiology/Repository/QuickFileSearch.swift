import Foundation

struct QuickFileSearchResponse: Sendable, Equatable {
    let files: [RepositoryFile]
    let totalCount: Int

    var isLimited: Bool { totalCount > files.count }
}

/// A repository-only file ranker. It deliberately has no dependency on SCIP
/// or ripgrep, and keeps only the best visible candidates instead of sorting
/// every match after each keystroke.
enum QuickFileSearch {
    static let visibleLimit = 100

    private struct Candidate: Comparable {
        let file: RepositoryFile
        let tier: Int
        let boundaryMisses: Int
        let gaps: Int
        let pathLength: Int

        static func < (lhs: Candidate, rhs: Candidate) -> Bool {
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            if lhs.boundaryMisses != rhs.boundaryMisses { return lhs.boundaryMisses < rhs.boundaryMisses }
            if lhs.gaps != rhs.gaps { return lhs.gaps < rhs.gaps }
            if lhs.pathLength != rhs.pathLength { return lhs.pathLength < rhs.pathLength }
            return lhs.file.path.localizedStandardCompare(rhs.file.path) == .orderedAscending
        }
    }

    private struct SearchText {
        let characters: [Character]
        let boundaries: Set<Int>
    }

    static func search(_ query: String, in files: [RepositoryFile], limit: Int = visibleLimit) async -> QuickFileSearchResponse {
        let limit = max(0, limit)
        let normalizedQuery = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        if normalizedQuery.isEmpty {
            return QuickFileSearchResponse(files: Array(files.prefix(limit)), totalCount: files.count)
        }

        var best: [Candidate] = []
        best.reserveCapacity(limit)
        var total = 0
        for (offset, file) in files.enumerated() {
            if offset.isMultiple(of: 128) {
                guard !Task.isCancelled else { return QuickFileSearchResponse(files: [], totalCount: 0) }
                await Task.yield()
            }
            guard let candidate = candidate(for: file, query: normalizedQuery) else { continue }
            total += 1
            guard limit > 0 else { continue }
            let insertion = best.partitioningIndex { candidate < $0 }
            if insertion < limit {
                best.insert(candidate, at: insertion)
                if best.count > limit { best.removeLast() }
            } else if best.count < limit {
                best.append(candidate)
            }
        }
        return QuickFileSearchResponse(files: best.map(\.file), totalCount: total)
    }

    private static func candidate(for file: RepositoryFile, query: [Character]) -> Candidate? {
        let name = searchText(file.name)
        let path = searchText(file.path)
        if name.characters == query {
            return Candidate(file: file, tier: 0, boundaryMisses: 0, gaps: 0, pathLength: path.characters.count)
        }
        if name.characters.starts(with: query) {
            return Candidate(file: file, tier: 1, boundaryMisses: 0, gaps: name.characters.count - query.count, pathLength: path.characters.count)
        }
        if let start = contiguousStart(of: query, in: name.characters) {
            return Candidate(file: file, tier: 2, boundaryMisses: name.boundaries.contains(start) ? 0 : 1,
                             gaps: name.characters.count - query.count, pathLength: path.characters.count)
        }
        if let score = subsequenceScore(query, in: name) {
            return Candidate(file: file, tier: 3, boundaryMisses: score.boundaryMisses,
                             gaps: score.gaps, pathLength: path.characters.count)
        }
        if let score = subsequenceScore(query, in: path) {
            return Candidate(file: file, tier: 4, boundaryMisses: score.boundaryMisses,
                             gaps: score.gaps, pathLength: path.characters.count)
        }
        return nil
    }

    private static func normalize(_ value: String) -> [Character] {
        Array(value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")))
    }

    /// Keeps boundary positions alongside case/diacritic-folded characters.
    /// Camel-case transitions count alongside path and punctuation separators.
    private static func searchText(_ value: String) -> SearchText {
        var characters: [Character] = []
        var boundaries = Set<Int>()
        var previousWasLowercaseOrDigit = false
        for original in value {
            let start = characters.count
            let scalar = original.unicodeScalars.first
            let uppercase = scalar?.properties.isUppercase == true
            let separator = "_-. /\\".contains(original)
            if start == 0 || separator || (uppercase && previousWasLowercaseOrDigit) { boundaries.insert(start) }
            characters.append(contentsOf: normalize(String(original)))
            previousWasLowercaseOrDigit = scalar?.properties.isLowercase == true || scalar?.properties.numericType != nil
            if separator { boundaries.insert(characters.count) }
        }
        return SearchText(characters: characters, boundaries: boundaries)
    }

    private static func contiguousStart(of needle: [Character], in haystack: [Character]) -> Int? {
        guard needle.count <= haystack.count else { return nil }
        for start in 0...(haystack.count - needle.count) where Array(haystack[start..<(start + needle.count)]) == needle {
            return start
        }
        return nil
    }

    private static func subsequenceScore(_ needle: [Character], in haystack: SearchText) -> (gaps: Int, boundaryMisses: Int)? {
        var matched: [Int] = []
        matched.reserveCapacity(needle.count)
        var cursor = 0
        for character in needle {
            guard cursor < haystack.characters.count,
                  let index = haystack.characters[cursor...].firstIndex(of: character) else { return nil }
            matched.append(index)
            cursor = index + 1
        }
        let span = (matched.last ?? 0) - (matched.first ?? 0) + 1
        let boundaryMisses = matched.reduce(into: 0) { count, index in
            if !haystack.boundaries.contains(index) { count += 1 }
        }
        return (span - needle.count, boundaryMisses)
    }
}

private extension Array {
    func partitioningIndex(where belongsBefore: (Element) -> Bool) -> Int {
        var lower = 0
        var upper = count
        while lower < upper {
            let middle = (lower + upper) / 2
            if belongsBefore(self[middle]) { upper = middle } else { lower = middle + 1 }
        }
        return lower
    }
}

struct QuickFileSelection: Equatable {
    var path: String?

    mutating func reset(for files: [RepositoryFile]) {
        path = files.first?.path
    }

    mutating func move(_ delta: Int, in files: [RepositoryFile]) {
        guard !files.isEmpty else { path = nil; return }
        let current = path.flatMap { selected in files.firstIndex { $0.path == selected } } ?? 0
        path = files[min(max(current + delta, 0), files.count - 1)].path
    }
}
