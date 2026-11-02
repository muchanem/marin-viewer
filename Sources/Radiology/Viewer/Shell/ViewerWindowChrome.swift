import SwiftUI

/// What the main viewer window adds around Radiology's split view: the strip of cards above it
/// while a PR is open, the "Open PR session" edge while the panel is hidden, the toast, the
/// Open PR and enlarged-diagram sheets, Escape to zoom out, and the window's focused value.
/// Outside a viewer window it changes nothing.
struct ViewerWindowChrome: ViewModifier {
    @Environment(ViewerStore.self) private var store: ViewerStore?
    @Environment(ViewerWindowModel.self) private var window: ViewerWindowModel?
    @Environment(AppModel.self) private var model: AppModel?
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        if let store, let window {
            chrome(content, store: store, window: window)
        } else {
            content
        }
    }

    private func chrome(_ content: Content, store: ViewerStore, window: ViewerWindowModel) -> some View {
        @Bindable var window = window
        let reviewing = store.isReviewing && window.kind == .main
        let reading = !store.isReviewing && window.kind == .main && store.readingPath != nil ? store.readingSystem : nil
        return VStack(spacing: 0) {
            if reviewing {
                ViewerStrip()
            } else if let reading {
                ViewerReadingStrip(page: reading)
            }
            HStack(spacing: 0) {
                content
                if reviewing, !window.isPanelPresented { OpenSessionStrip() }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = store.toast { ViewerToastView(toast: toast).id(toast.id) }
        }
        .overlay {
            if let number = store.loadingPR {
                ProgressView(String("Opening #\(number)…"))
                    .padding(16).background(.regularMaterial, in: .rect(cornerRadius: 10))
            }
        }
        .animation(.easeOut(duration: 0.15), value: store.toast)
        .onKeyPress(.escape) {
            guard window.zoomedStep != nil else { return .ignored }
            window.zoomOut()
            return .handled
        }
        .sheet(isPresented: $window.isOpenPRPresented) { OpenPRSheet() }
        .sheet(item: $window.enlargedDiagram) { key in EnlargedDiagramSheet(key: key) }
        .alert("Could Not Open PR", isPresented: Binding(get: { store.loadError != nil }, set: { if !$0 { store.loadError = nil } }),
               presenting: store.loadError) { _ in
            Button("OK", role: .cancel) { store.loadError = nil }
        } message: { Text($0) }
        .focusedSceneValue(\.viewerWindow, window)
        .onAppear {
            guard window.kind == .main else { return }
            store.openCodeWindow = { request in openWindow(id: CodeWindowView.sceneID, value: request) }
        }
        .task {
            guard window.kind == .main else { return }
            await store.loadSystemPages()
        }
        .onChange(of: OpenFile(path: model?.source?.path, root: model?.attachedRoot), initial: true) { _, file in
            guard window.kind == .main else { return }
            store.followOpenFile(file.path, root: file.root)
        }
        .onDisappear {
            guard window.kind == .main else { return }
            Task { await store.keepAllPendingMemories(reason: "the window closed") }
        }
    }
}

/// The main reader's open file, which the reading strip follows.
private struct OpenFile: Equatable {
    var path: String?
    var root: URL?
}
