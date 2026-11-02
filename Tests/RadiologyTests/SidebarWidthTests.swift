import AppKit
import SwiftUI
import Testing
@testable import Radiology

/// The navigation sidebar opens at its declared width. With `.toolbar(removing:)` outside
/// `.navigationSplitViewColumnWidth`, the split view lost the width and opened the sidebar at
/// 144 points, below `Theme.sidebarMinWidth`.
@Suite(.serialized) @MainActor
struct SidebarWidthTests {
    @Test func theSidebarOpensAtItsIdealWidth() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "sidebar-width-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = SemanticIndexService(indexers: [], cache: IndexCache(root: root.appending(path: "cache")),
                                           tools: ToolDirectory(url: root.appending(path: "tools")))
        let defaults = try #require(UserDefaults(suiteName: "sidebar-width-\(UUID().uuidString)"))
        let model = AppModel(preferences: defaults, semantics: SemanticModel(service: service))

        let size = CGSize(width: 1180, height: 780)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let controller = NSHostingController(rootView: RootView().environment(model))
        controller.sizingOptions = []
        window.contentViewController = controller
        window.setContentSize(size)
        window.orderFrontRegardless()
        defer { window.close() }

        var sidebar: CGFloat = 0
        for _ in 0..<20 {
            window.contentView?.layoutSubtreeIfNeeded()
            sidebar = Self.sidebarWidth(in: try #require(window.contentView))
            if sidebar >= Theme.sidebarMinWidth { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(sidebar >= Theme.sidebarMinWidth && sidebar <= Theme.sidebarMaxWidth, "sidebar is \(sidebar) points wide")
    }

    /// The first pane of the innermost split view, which holds the sidebar and the detail.
    static func sidebarWidth(in view: NSView) -> CGFloat {
        var splits: [NSSplitView] = []
        func visit(_ view: NSView) {
            if let split = view as? NSSplitView { splits.append(split) }
            view.subviews.forEach(visit)
        }
        visit(view)
        let navigation = splits.first { $0.arrangedSubviews.count == 2 && $0.arrangedSubviews[0].frame.width < $0.arrangedSubviews[1].frame.width }
        return navigation?.arrangedSubviews.first?.frame.width ?? 0
    }
}
