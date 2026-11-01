import AppKit

/// Light mode only (DESIGN.md §5), and on quit the pending memories are kept before the sidecar
/// stops.
@MainActor
final class ViewerAppDelegate: NSObject, NSApplicationDelegate {
    weak var viewer: ViewerStore?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
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
