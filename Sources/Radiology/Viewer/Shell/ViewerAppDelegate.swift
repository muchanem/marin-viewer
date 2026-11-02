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
    ///
    /// `MARIN_VIEWER_SNAPSHOT_DIR=<dir>` instead walks the window through the states the
    /// verification compares with the demo and writes each one twice: `live-N-name.png` from
    /// `screencapture -l` (needs Screen Recording) and `cache-N-name.png` drawn offscreen.
    static func snapshotIfRequested(store: ViewerStore) async {
        let environment = ProcessInfo.processInfo.environment
        if let directory = environment["MARIN_VIEWER_SNAPSHOT_DIR"] {
            await snapshotStates(store: store, directory: URL(filePath: directory, directoryHint: .isDirectory))
            return
        }
        guard let path = environment["MARIN_VIEWER_SNAPSHOT"] else { return }
        try? await Task.sleep(for: .seconds(4))
        guard let window = mainWindow() else { return }
        writeCached(window, to: URL(filePath: path))
    }

    private static func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.contentView != nil && $0.contentViewController != nil }
    }

    private static func snapshotStates(store: ViewerStore, directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var log: [String] = []
        for _ in 0..<600 where store.diffReader == nil && store.documentError == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        for _ in 0..<200 where store.layouts.values.contains(.loading) { try? await Task.sleep(for: .milliseconds(50)) }
        guard let window = mainWindow(), let reader = store.diffReader else {
            log.append("no reader: \(store.documentError ?? "no window")")
            try? log.joined(separator: "\n").write(to: directory.appending(path: "snapshots.log"), atomically: true, encoding: .utf8)
            return
        }
        window.setContentSize(NSSize(width: 1440, height: 900))
        try? await Task.sleep(for: .seconds(2))
        func shoot(_ name: String) async {
            try? await Task.sleep(for: .milliseconds(1200))
            writeCached(window, to: directory.appending(path: "cache-\(name).png"))
            let live = directory.appending(path: "live-\(name).png")
            let process = Process()
            process.executableURL = URL(filePath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-o", "-l\(window.windowNumber)", live.path]
            let error = Pipe()
            process.standardError = error
            do {
                try process.run()
                process.waitUntilExit()
                let message = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                log.append("\(name): screencapture exit \(process.terminationStatus) \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
            } catch {
                log.append("\(name): screencapture did not run: \(error.localizedDescription)")
            }
            let panes = splitPanes(in: window.contentView)
            log.append("\(name): mode \(reader.mode) step \(reader.stepID) note \(reader.expandedNoteID ?? "-") blame \(reader.showBlame) panes \(panes)")
        }

        store.focus(step: store.stepOrder.first ?? 1)
        await shoot("1-opened-step1")

        store.openStepDiagram(6, in: store.mainWindow)
        await shoot("2-step6-zoomed")
        store.mainWindow.zoomOut()

        let http = "lib/shellbox/src/shellbox/http_service.py"
        store.open(path: http)
        store.blame = true
        try? await Task.sleep(for: .seconds(3))
        await shoot("3-byfile-http-blame")
        store.blame = false
        try? await Task.sleep(for: .seconds(1))

        store.focus(note: "f1")
        await shoot("4-note-f1")
        store.focus(note: "f1")

        store.focus(step: 6)
        try? await Task.sleep(for: .milliseconds(800))
        if let text = textViews(in: window.contentView).first(where: { $0.content?.card.path == http }) {
            let string = text.string as NSString
            let start = string.range(of: "def _pump")
            if start.location != NSNotFound {
                let line = string.lineRange(for: start)
                let end = string.lineRange(for: NSRange(location: min(string.length - 1, line.upperBound + 200), length: 0))
                window.makeFirstResponder(text)
                text.setSelectedRange(NSRange(location: line.location, length: end.upperBound - line.location))
                // What ⌘> runs in the text view.
                text.askFromKeyboard()
                store.mainSession?.draft = "If the handler hangs, what does the guest see?"
                log.append("selection: \(reader.selection.map { "\($0.path) \(String(describing: $0.lines))" } ?? "none")")
            } else {
                log.append("selection: no `def _pump` in the http_service card")
            }
        } else {
            log.append("selection: no http_service card at step 6")
        }
        await shoot("5-ask-selection")
        try? log.joined(separator: "\n").write(to: directory.appending(path: "snapshots.log"), atomically: true, encoding: .utf8)
    }

    private static func writeCached(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView?.superview ?? window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func textViews(in view: NSView?) -> [DiffCodeTextView] {
        guard let view else { return [] }
        return (view as? DiffCodeTextView).map { [$0] } ?? view.subviews.flatMap(textViews)
    }

    private static func splitPanes(in view: NSView?) -> String {
        guard let view else { return "" }
        var found: [String] = []
        if let split = view as? NSSplitView { found.append(split.arrangedSubviews.map { String(Int($0.frame.width)) }.joined(separator: "|")) }
        found += view.subviews.map { splitPanes(in: $0) }.filter { !$0.isEmpty }
        return found.joined(separator: " / ")
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
