import AppKit
import Foundation
import SwiftUI
import Testing
import ViewerCore
@testable import Radiology

/// Opt-in exercise of the shell against the real #10640 wordbase, the Marin clone and the built
/// sidecar: `MARIN_VIEWER_PROBE=1 swift test --filter ViewerRealDataProbe`.
///
/// - `layoutScales` lays out every fixture diagram with box sizes measured in the app's fonts
///   and prints the scale table.
/// - `snapshots` renders the PR window in four states, then the stock reader after Close PR, to
///   `MARIN_VIEWER_SNAPSHOTS` (PNG), and prints the split views' pane widths.
/// - `liveTurn` (also needs `MARIN_VIEWER_LIVE=1`) asks one chip question through the panel's
///   sidecar client on the `claude` login. It never posts a review.
///
/// `MARIN_VIEWER_PROBE_WORDBASE` and `MARIN_VIEWER_PROBE_STATE` point at scratch copies, since
/// a session's notes.keep commits to the wordbase. Git runs only in Radiology's review cache.
@Suite(.serialized) @MainActor
struct ViewerRealDataProbe {
    static let environment = ProcessInfo.processInfo.environment
    static var enabled: Bool { environment["MARIN_VIEWER_PROBE"] == "1" }

    static var paths: ViewerPaths {
        let worktree = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return ViewerPaths(root: ViewerPaths.defaultRoot,
                           wordbase: environment["MARIN_VIEWER_PROBE_WORDBASE"].map { URL(filePath: $0, directoryHint: .isDirectory) },
                           state: environment["MARIN_VIEWER_PROBE_STATE"].map { URL(filePath: $0, directoryHint: .isDirectory) },
                           prompts: worktree.appending(path: "prompts", directoryHint: .isDirectory),
                           sidecar: worktree.appending(path: "sidecar", directoryHint: .isDirectory))
    }

    private func openStore() async throws -> ViewerStore {
        let store = ViewerStore(paths: Self.paths)
        await store.openPR(10640)
        if let error = store.loadError { Issue.record("open failed: \(error)") }
        _ = await eventuallyLong { store.layouts.values.allSatisfy { $0 != .loading } && store.layouts.count >= 6 }
        return store
    }

    @Test func layoutScales() async throws {
        guard Self.enabled else { return print("viewer probe skipped (set MARIN_VIEWER_PROBE=1)") }
        let store = try await openStore()
        let pr = try #require(store.pr)
        print("probe: #\(pr.number) \(pr.changes.count) changed files, system \(pr.system?.name ?? "none"), \(pr.headFiles.count) head files under its root")
        let keys: [DiagramKey] = [.system, .pr] + pr.wordbase.diagrams.steps.keys.compactMap(Int.init).sorted().map(DiagramKey.step)
        print("| diagram | boxes | measured widths (min–max) | natural | extent | scale | minScale | overflow | warnings |")
        print("|---|---|---|---|---|---|---|---|---|")
        for key in keys {
            let diagram = try #require(store.diagram(key))
            let widths = diagram.nodes.map { DiagramMetrics.size(of: $0, code: DiagramMetrics.isCode($0, in: key)).width }
            switch store.layouts[key] {
            case .ready(let layout)?:
                print("| \(key) | \(layout.nodes.count) | \(Int(widths.min() ?? 0))–\(Int(widths.max() ?? 0)) | "
                      + "\(Int(layout.natural.width))×\(Int(layout.natural.height)) | \(Int(layout.width))×\(Int(layout.height)) | "
                      + "\(layout.scale) | \(layout.minScale) | \(layout.overflow) | \(layout.warnings.joined(separator: "; ")) |")
            case .failed(let message)?:
                Issue.record("\(key) failed: \(message)")
            default:
                Issue.record("\(key) has no layout")
            }
        }
        store.sidecar.stop()
    }

    @Test func snapshots() async throws {
        guard Self.enabled, let directory = Self.environment["MARIN_VIEWER_SNAPSHOTS"] else {
            return print("viewer snapshots skipped (set MARIN_VIEWER_PROBE=1 and MARIN_VIEWER_SNAPSHOTS=<dir>)")
        }
        let output = URL(filePath: directory, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let store = try await openStore()
        let reader = Self.reader()
        store.mainReader = reader
        await reader.openRepository(Self.paths.marin, selecting: nil)
        reader.mode = .steps
        store.focus(step: 6)
        let window = Self.window(store: store, reader: reader)
        defer { window.close() }

        try await capture(window, to: output.appending(path: "app-1-opened.png"))

        store.mainWindow.zoomedStep = 6
        try await capture(window, to: output.appending(path: "app-2-zoomed-step6.png"))
        store.mainWindow.zoomedStep = nil

        let session = try #require(store.mainSession)
        session.addChip(ChipFactory.step(try #require(store.pr?.step(3)), commit: store.pr?.head ?? ""))
        session.addChip(ChipFactory.file(ViewerFixture.src + "http_service.py", commit: store.pr?.head ?? "", shortener: store.shortener))
        session.draft = "If the handler hangs, what does the guest see?"
        try await capture(window, to: output.appending(path: "app-3-session-chips.png"))

        session.chips = []
        session.draft = ""
        session.sidecarID = "probe-session"
        session.phase = .memories
        session.memories = [
            ProposedMemory(target: "wordbase/lib/shellbox/src/shellbox/http_service.py.md · notes",
                           text: "The relay's failure behavior under a stuck model endpoint comes from three limits defined in `http_service_guest.py` and imported by the host: 16 pending requests, 4 MiB bodies and a 600 s timeout.",
                           commit: store.pr?.head ?? ""),
            ProposedMemory(target: "wordbase/systems/shellbox.md · notes",
                           text: "Relay throughput over cluster exec transports was the open design question in the #10640 review.",
                           commit: store.pr?.head ?? ""),
            ProposedMemory(target: "wordbase/reviewer.md · how you review",
                           text: "On Shellbox changes you start from cancellation, teardown and failure under load.",
                           commit: store.pr?.head ?? ""),
        ]
        try await capture(window, to: output.appending(path: "app-4-memories.png"))
        session.phase = .notStarted
        session.sidecarID = nil
        store.closePR()
        reader.mode = .files
        try await capture(window, to: output.appending(path: "app-5-stock-reader.png"))
        store.sidecar.stop()
    }

    @Test func liveTurn() async throws {
        guard Self.enabled, Self.environment["MARIN_VIEWER_LIVE"] == "1" else {
            return print("live turn skipped (set MARIN_VIEWER_PROBE=1 and MARIN_VIEWER_LIVE=1)")
        }
        let store = try await openStore()
        let session = try #require(store.mainSession)
        let pump = try #require(store.pr?.step(6))
        store.ask(ChipFactory.step(pump, commit: store.pr?.head ?? ""))
        store.ask(ChipFactory.code(path: ViewerFixture.src + "http_service.py", lines: 125...147, symbol: "_pump",
                                   commit: store.pr?.head ?? "", shortener: store.shortener))
        session.draft = Self.environment["MARIN_VIEWER_LIVE_QUESTION"]
            ?? "If the host handler hangs, what does the guest see, and does anything else stall? Answer in three sentences."
        let started = ContinuousClock.now
        await store.send(session)
        _ = await eventuallyLong(seconds: 300) { !session.isBusy }
        print("probe: live turn took \(started.duration(to: .now)), cost $\(session.costUSD), state \(session.stateLabel)")
        for line in store.sidecar.transcript where !line.contains("\"stream.delta\"") { print("probe wire: \(line.prefix(400))") }
        for entry in session.entries { print("probe entry: \(entry.kind)") }
        #expect(session.entries.contains { if case .agent = $0.kind { true } else { false } })
        store.sidecar.stop()
    }

    // MARK: - Helpers

    static func reader() -> AppModel {
        let root = FileManager.default.temporaryDirectory.appending(path: "viewer-probe-\(UUID().uuidString)", directoryHint: .isDirectory)
        let service = SemanticIndexService(indexers: [], cache: IndexCache(root: root.appending(path: "cache")),
                                           tools: ToolDirectory(url: root.appending(path: "tools")))
        let defaults = UserDefaults(suiteName: "viewer-probe-\(UUID().uuidString)")!
        return AppModel(preferences: defaults, semantics: SemanticModel(service: service))
    }

    static let size = CGSize(width: 1440, height: 900)

    static func window(store: ViewerStore, reader: AppModel) -> NSWindow {
        let root = RootView()
            .environment(reader)
            .environment(store)
            .environment(store.mainWindow)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        let controller = NSHostingController(rootView: root)
        controller.sizingOptions = []
        controller.view.frame = NSRect(origin: .zero, size: size)
        window.contentViewController = controller
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: 40, y: 40))
        window.orderFrontRegardless()
        return window
    }

    private func capture(_ window: NSWindow, to url: URL) async throws {
        for _ in 0..<6 {
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(120))
        }
        // The frame view includes the titlebar and the SwiftUI toolbar.
        let view = try #require(window.contentView?.superview ?? window.contentView)
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
        print("probe: wrote \(url.path)")
        if let content = window.contentView { print("probe panes: \(Self.splitPanes(in: content))") }
    }

    /// The widths of every split view's panes, outermost first.
    static func splitPanes(in view: NSView) -> String {
        var found: [String] = []
        func visit(_ view: NSView) {
            if let split = view as? NSSplitView {
                found.append(split.arrangedSubviews.map { String(Int($0.frame.width)) }.joined(separator: "|"))
            }
            view.subviews.forEach(visit)
        }
        visit(view)
        return found.joined(separator: " / ")
    }
}

@MainActor func eventuallyLong(seconds: Int = 60, _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(seconds)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return condition()
}
