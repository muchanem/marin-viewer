import SwiftUI
import ViewerCore

extension FocusedValues {
    /// The viewer window with keyboard focus, for ⌘> and Promote to Session.
    @Entry var viewerWindow: ViewerWindowModel?
}

/// The viewer's menu items: File > Open PR…, ⌘> to ask, the main view's switches, and
/// Promote to Session for code windows.
struct ViewerCommands: Commands {
    let store: ViewerStore
    @FocusedValue(\.viewerWindow) private var window

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()
            Button("Open PR…") { store.mainWindow.isOpenPRPresented = true }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Close PR", action: store.closePR).disabled(!store.isReviewing)
        }
        CommandMenu("Session") {
            Button("Ask About Selection") { ViewerAsk.ask(store: store, window: window ?? store.mainWindow) }
                .keyboardShortcut(">", modifiers: .command)
                .disabled(!store.isReviewing)
            Button("Promote to Session") { if let window { store.promote(window) } }
                .disabled(window?.kind != .secondary || window?.ownSession != nil || !store.isReviewing)
            Divider()
            Button("By Step") { store.mode = .byStep }
                .keyboardShortcut("3", modifiers: [.command, .option]).disabled(!store.isReviewing)
            Button("By File") { store.mode = .byFile }
                .keyboardShortcut("4", modifiers: [.command, .option]).disabled(!store.isReviewing)
        }
    }
}

/// ⌘> from the menu: a chip from the reader's selection or caret in a code window, else the
/// file, step, box or note last clicked or the diff reader's code selection, whichever came
/// later, else the step on screen. In the diff reader itself, the text view answers ⌘> first.
enum ViewerAsk {
    @MainActor static func ask(store: ViewerStore, window: ViewerWindowModel) {
        if let chip = chip(store: store, window: window) {
            store.ask(chip, from: window)
        } else {
            store.showToast("Select code or click a file, step, box or note first.")
        }
    }

    @MainActor static func chip(store: ViewerStore, window: ViewerWindowModel) -> Chip? {
        if window.kind == .secondary, let reader = window.reader, let chip = readerChip(reader, store: store) { return chip }
        // A click on a file, step, box or note clears with each new code selection, so the newer
        // of the two wins.
        if let target = window.lastAskTarget { return target }
        if window.kind == .main, let chip = store.diffReader?.selectionAskChip { return chip }
        if store.mode == .byStep, let step = store.focusedStep { return ChipFactory.step(step, commit: store.pr?.head ?? "") }
        return nil
    }

    /// The enclosing symbol at the caret, else the caret's line.
    @MainActor static func readerChip(_ reader: AppModel, store: ViewerStore) -> Chip? {
        guard let source = reader.source else { return nil }
        let commit = store.pr?.head ?? ""
        if let symbol = reader.activeSymbol {
            let first = source.line(atByte: symbol.byteRange.lowerBound)
            let last = source.line(atByte: max(symbol.byteRange.lowerBound, symbol.byteRange.upperBound - 1))
            return ChipFactory.code(path: source.path, lines: first...last, symbol: symbol.name, commit: commit, shortener: store.shortener)
        }
        return ChipFactory.code(path: source.path, lines: reader.currentLine...reader.currentLine, symbol: nil, commit: commit,
                                shortener: store.shortener)
    }
}
