/// ViewThatFits needs unique identities across its entire list of alternatives.
/// Prefer the complete declaration chain, then the nearest path components.
struct SourceBreadcrumbVariant: Identifiable {
    let symbolCount: Int
    let omittedDirectories: Int
    let showsRoot: Bool

    var id: String { "\(symbolCount)/\(omittedDirectories)/\(showsRoot)" }

    static func options(directoryCount: Int, symbolCount: Int) -> [Self] {
        var options: [Self] = []
        for visibleSymbols in stride(from: max(1, symbolCount), through: 1, by: -1) {
            for omittedDirectories in 0...directoryCount {
                options.append(Self(symbolCount: visibleSymbols, omittedDirectories: omittedDirectories, showsRoot: true))
                options.append(Self(symbolCount: visibleSymbols, omittedDirectories: omittedDirectories, showsRoot: false))
            }
        }
        return options
    }
}
