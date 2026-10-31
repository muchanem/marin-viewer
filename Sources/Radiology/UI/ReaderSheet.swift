 enum ReaderSheet: String, Identifiable {
    case files, line, symbols, pullRequest, codePath, keyboardHelp
    var id: Self { self }
}
