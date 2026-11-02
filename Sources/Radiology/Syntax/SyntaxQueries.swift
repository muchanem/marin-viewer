import Foundation
import SwiftTreeSitter

/// The query roles Radiology asks of every grammar. `calls` is optional: a
/// grammar without it simply reports no call sites (and Critical Lens
/// summaries say so), it never guesses.
enum SyntaxQueryRole: String, CaseIterable, Sendable {
    case highlights, folds, symbols, scopes, calls
}

/// Compiled queries for one language. A role is `nil` when the grammar ships
/// no file for it, which is legitimate; a malformed file is an error instead.
struct SyntaxQuerySet: Sendable {
    let highlights: Query?
    let folds: Query?
    let symbols: Query?
    let scopes: Query?
    let calls: Query?

    func query(for role: SyntaxQueryRole) -> Query? {
        switch role {
        case .highlights: highlights
        case .folds: folds
        case .symbols: symbols
        case .scopes: scopes
        case .calls: calls
        }
    }
}

/// Reads `.scm` files out of the module resource bundle and compiles them.
///
/// Every failure names the language, the role, and the reason, so a packaging
/// or query mistake stays diagnosable while the source itself stays readable.
enum SyntaxQueryLoader {
    static func compile(_ language: SourceLanguage) throws -> SyntaxQuerySet {
        let tsLanguage = language.treeSitterLanguage
        var compiled: [SyntaxQueryRole: Query] = [:]
        for role in SyntaxQueryRole.allCases {
            guard let data = try source(for: language, role: role) else { continue }
            do {
                compiled[role] = try Query(language: tsLanguage, data: data)
            } catch {
                throw BrowserError.message(
                    "The \(language.displayName) \(role.rawValue) query is invalid (\(error)). "
                    + "Source is shown without that structure.")
            }
        }
        guard compiled[.highlights] != nil else {
            throw BrowserError.message(
                "The \(language.displayName) highlights query is missing from the application bundle. "
                + "Source is shown as plain text.")
        }
        return SyntaxQuerySet(highlights: compiled[.highlights], folds: compiled[.folds],
                              symbols: compiled[.symbols], scopes: compiled[.scopes], calls: compiled[.calls])
    }

    /// Concatenates every present `<directory>/<role>.scm` in declaration order.
    static func source(for language: SourceLanguage, role: SyntaxQueryRole) throws -> Data? {
        var parts: [Data] = []
        for directory in language.queryDirectories {
            guard let url = resourceURL(directory: directory, role: role) else { continue }
            do {
                parts.append(try Data(contentsOf: url))
            } catch {
                throw BrowserError.message(
                    "Could not read the \(language.displayName) \(role.rawValue) query at \(url.path).")
            }
        }
        guard !parts.isEmpty else { return nil }
        return parts.reduce(into: Data()) { combined, part in
            combined.append(part)
            combined.append(0x0A)
        }
    }

    /// Resolves one query file inside the module resource bundle.
    static func resourceURL(directory: String, role: SyntaxQueryRole) -> URL? {
        Bundle.module.url(forResource: role.rawValue, withExtension: "scm",
                          subdirectory: "Queries/\(directory)")
    }
}
