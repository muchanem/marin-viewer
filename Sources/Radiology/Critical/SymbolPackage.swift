import Foundation

/// The four header fields of a SCIP symbol string. Double spaces inside a
/// field are escapes and never split.
struct SCIPSymbolHeader: Sendable, Equatable {
    let scheme: String
    let manager: String
    let package: String
    let version: String

    /// Nil for `local N` symbols and malformed strings.
    init?(_ symbol: String) {
        guard !symbol.hasPrefix("local ") else { return nil }
        var fields: [String] = []
        var current = ""
        var index = symbol.startIndex
        while index < symbol.endIndex, fields.count < 4 {
            let character = symbol[index]
            if character == " " {
                let next = symbol.index(after: index)
                if next < symbol.endIndex, symbol[next] == " " {
                    current.append(" ")
                    index = symbol.index(after: next)
                    continue
                }
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index = symbol.index(after: index)
        }
        guard fields.count == 4 else { return nil }
        scheme = fields[0]
        manager = fields[1]
        package = fields[2]
        version = fields[3]
    }

    /// The package name alone: `.` is SCIP's placeholder for "no package".
    var packageName: String? { package.isEmpty || package == "." ? nil : package }

    /// `scheme manager name`, without the version: the key for package-level
    /// decisions. Qualifying by scheme and manager keeps equally named
    /// packages of different languages in one repository apart.
    var packageKey: String? { packageName.map { "\(scheme) \(manager) \($0)" } }
}

extension SCIPSymbolString {
    /// The package name without its version, so a decision about `libc`
    /// survives a version bump. Nil for locals and placeholder packages.
    static func packageName(of symbol: String) -> String? {
        SCIPSymbolHeader(symbol)?.packageName
    }

    static func packageKey(of symbol: String) -> String? {
        SCIPSymbolHeader(symbol)?.packageKey
    }
}
