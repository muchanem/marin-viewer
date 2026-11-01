import SwiftUI

/// A code-only window (DESIGN.md §2): Radiology's reader on the PR head, without strip or
/// sidebar. Questions asked here go to the main window's session until Promote to Session forks
/// one for this window, which then gets its own panel.
struct CodeWindowView: View {
    static let sceneID = "code"
    /// Reader state for code windows lives in its own defaults suite, so they never overwrite
    /// the main window's restored session or recent repositories.
    static let defaultsSuite = "org.marin.viewer.code-windows"

    @Environment(ViewerStore.self) private var store
    let request: CodeWindowRequest
    @State private var reader = AppModel(preferences: UserDefaults(suiteName: CodeWindowView.defaultsSuite) ?? .standard)
    @State private var window = ViewerWindowModel(kind: .secondary)

    var body: some View {
        @Bindable var window = window
        ReaderDetail()
            .navigationTitle(URL(filePath: request.path).lastPathComponent)
            .navigationSubtitle(store.pr.map { "#\($0.number) at \($0.head.prefix(7))" } ?? "")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Ask About Selection", systemImage: "text.bubble") { ViewerAsk.ask(store: store, window: window) }
                        .help("Ask the PR session about the caret's function (⌘>)")
                    if window.ownSession == nil {
                        Button("Promote to Session", systemImage: "arrow.up.right.square") { store.promote(window) }
                            .disabled(!store.isReviewing)
                            .help("Fork the PR session for this window")
                    } else {
                        Button(window.isPanelPresented ? "Hide Session Panel" : "Show Session Panel", systemImage: "sidebar.right") {
                            window.isPanelPresented.toggle()
                        }
                    }
                }
            }
            .inspector(isPresented: Binding(get: { window.ownSession != nil && window.isPanelPresented },
                                            set: { window.isPanelPresented = $0 })) {
                ViewerPanel()
            }
            .environment(reader)
            .environment(window)
            .focusedSceneValue(\.viewerWindow, window)
            .focusedSceneValue(\.isContextPresented, $window.isPanelPresented)
            .frame(minWidth: 560, minHeight: 360)
            .task(id: request) { await open() }
            .onDisappear {
                if let session = window.ownSession, session.phase == .memories {
                    Task { await store.keepMemories(session, reason: "the window closed") }
                }
            }
    }

    private func open() async {
        window.reader = reader
        await reader.openRepository(URL(filePath: request.root, directoryHint: .isDirectory), selecting: request.path)
        if let line = request.line {
            reader.navigate(to: SourceLocation(path: request.path, byteOffset: 0), targetLine: line)
        }
    }
}
