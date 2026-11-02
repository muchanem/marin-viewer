extension SnippetLine {
    /// Expands tabs to four spaces and removes the indentation every
    /// non-blank line shares, so a nested call site reads at the left edge.
    static func dedent(_ lines: [SnippetLine]) -> [SnippetLine] {
        let expanded = lines.map { SnippetLine(number: $0.number, text: $0.text.replacing("\t", with: "    ")) }
        let common = expanded.lazy.filter { !$0.text.allSatisfy(\.isWhitespace) }
            .map { $0.text.prefix { $0 == " " }.count }
            .min() ?? 0
        guard common > 0 else { return expanded }
        return expanded.map { SnippetLine(number: $0.number, text: String($0.text.dropFirst(min(common, $0.text.prefix { $0 == " " }.count)))) }
    }
}
