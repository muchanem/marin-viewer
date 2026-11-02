import AppKit

/// Light mode only (DESIGN.md §5), and on quit the pending memories are kept before the sidecar
/// stops.
@MainActor
final class ViewerAppDelegate: NSObject, NSApplicationDelegate {
    weak var viewer: ViewerStore?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
    }

    /// `MARIN_VIEWER_SNAPSHOT=<file.png>`: once the PR has opened, writes the main window,
    /// toolbar included, to that file. A development aid for comparing the app with the demo
    /// where screen recording is not available.
    static func snapshotIfRequested() async {
        guard let path = ProcessInfo.processInfo.environment["MARIN_VIEWER_SNAPSHOT"] else { return }
        try? await Task.sleep(for: .seconds(4))
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let view = window.contentView?.superview ?? window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let viewer else { return .terminateNow }
        guard !viewer.sessionsWithPendingMemories.isEmpty || viewer.sidecar.isRunning else { return .terminateNow }
        Task {
            await viewer.prepareForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
