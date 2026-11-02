import Foundation

/// Ranks repository symbols for ⌘T: exact name, then prefix, then camel-case
/// or path-component initials, then subsequence fuzzy matches. Ties break on
/// shorter names and then alphabetically so results are stable.
enum SymbolSearch {
    struct Match: Sendable, Equatable, Identifiable {
        let entry: SymbolSearchEntry
        let tier: Int
        var id: SemanticSymbolID { entry.id }
    }

    static func rank(_ query: String, in entries: [SymbolSearchEntry], limit: Int = 200) -> [Match] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return Array(entries.prefix(limit).map { Match(entry: $0, tier: 4) })
        }
        let needle = trimmed.lowercased()
        var matches: [Match] = []
        for entry in entries {
            guard let tier = tier(of: entry.name, needle: needle, rawNeedle: trimmed) else { continue }
            matches.append(Match(entry: entry, tier: tier))
        }
        matches.sort { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            if lhs.entry.name.count != rhs.entry.name.count { return lhs.entry.name.count < rhs.entry.name.count }
            if lhs.entry.name != rhs.entry.name { return lhs.entry.name < rhs.entry.name }
            return lhs.entry.position.path < rhs.entry.position.path
        }
        return Array(matches.prefix(limit))
    }

    /// 0 exact, 1 prefix, 2 component initials, 3 fuzzy subsequence.
    static func tier(of name: String, needle: String, rawNeedle: String) -> Int? {
        let lowered = name.lowercased()
        if lowered == needle { return 0 }
        if lowered.hasPrefix(needle) { return 1 }
        if initials(of: name).hasPrefix(needle) || componentPrefixMatch(name, needle: needle) { return 2 }
        if isSubsequence(needle, of: lowered) { return 3 }
        return nil
    }

    /// First letters of camel-case humps and underscore/dash/dot components:
    /// `SnapshotBootstrapGlobals` → `sbg`, `total_area` → `ta`.
    static func initials(of name: String) -> String {
        var result = ""
        var previous: Character = "_"
        for character in name {
            if "_-./:".contains(character) { previous = character; continue }
            if "_-./:".contains(previous) || (character.isUppercase && !previous.isUppercase) || (character.isNumber && !previous.isNumber) {
                result.append(character.lowercased())
            }
            previous = character
        }
        return result
    }

    /// Every needle piece split by separators must prefix a name component in order.
    private static func componentPrefixMatch(_ name: String, needle: String) -> Bool {
        let components = name.split { "_-./:".contains($0) || $0.isUppercase }.map { $0.lowercased() }
        let humps = humpComponents(of: name)
        let pieces = needle.split { "_-./:".contains($0) }.map(String.init)
        guard pieces.count > 1 else { return false }
        for candidates in [components, humps] {
            var index = 0
            var matched = 0
            for piece in pieces {
                while index < candidates.count, !candidates[index].hasPrefix(piece) { index += 1 }
                guard index < candidates.count else { break }
                matched += 1
                index += 1
            }
            if matched == pieces.count { return true }
        }
        return false
    }

    private static func humpComponents(of name: String) -> [String] {
        var components: [String] = []
        var current = ""
        var previous: Character = "a"
        for character in name {
            if "_-./:".contains(character) {
                if !current.isEmpty { components.append(current.lowercased()) }
                current = ""
            } else if character.isUppercase, !previous.isUppercase, !current.isEmpty {
                components.append(current.lowercased())
                current = String(character)
            } else {
                current.append(character)
            }
            previous = character
        }
        if !current.isEmpty { components.append(current.lowercased()) }
        return components
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var iterator = haystack.makeIterator()
        for character in needle {
            var found = false
            while let candidate = iterator.next() {
                if candidate == character { found = true; break }
            }
            if !found { return false }
        }
        return true
    }
}
