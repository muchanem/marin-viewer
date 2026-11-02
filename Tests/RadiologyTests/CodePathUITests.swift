import SwiftUI
import Testing
@testable import Radiology

@Suite(.serialized) @MainActor
struct CodePathUITests {
    @Test func nativeSidebarAndImportSheetRenderAcrossWidthsAndAppearances() async throws {
        let domain = "Radiology.CodePathUI.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let model = AppModel(preferences: preferences)
        let root = URL(filePath: "/tmp/code-path-render")
        model.repository = RepositorySnapshot(root: root, files: [], tree: [], isGit: false)
        model.codePaths.activate(root)
        try model.codePaths.importText("Boot sequence — x86-64\narch/x86/start.S:_start:Establishes the initial stack and enters C startup.\nkernel/boot.cc:Kernel\\:\\:boot:Initializes memory: calls allocator setup before scheduling.\nkernel/scheduler.cc:start_scheduler:If SMP is enabled, wakes secondary processors before entering the first userspace thread.\n")
        try model.codePaths.importText("Incoming request\nserver/main.swift:serve:Registers the request callback.")
        model.codePaths.selectedPathID = model.codePaths.paths.first?.id
        let output = ProcessInfo.processInfo.environment["RADIOLOGY_CODE_PATH_RENDER_DIR"].map { URL(filePath: $0) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        for dark in [false, true] {
            for width in [220.0, 280.0, 420.0] {
                model.mode = .codePaths
                let view = RepositorySidebar().environment(model)
                try await render(view, width: width, height: 480, dark: dark,
                                 url: output?.appending(path: "\(dark ? "dark" : "light")-\(Int(width)).png"))
            }
            try await render(SidebarModeTabs(modes: BrowserMode.available(reviewing: true), selection: .constant(.codePaths))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top),
                             width: 220, height: 50, dark: dark, url: output?.appending(path: "\(dark ? "dark" : "light")-review-tabs-narrow.png"))
            try await render(SidebarModeTabs(modes: BrowserMode.available(reviewing: true), selection: .constant(.codePaths))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top),
                             width: 420, height: 50, dark: dark, url: output?.appending(path: "\(dark ? "dark" : "light")-review-tabs-wide.png"))
            try await render(CodePathImportSheet().environment(model), width: 620, height: 440, dark: dark,
                             url: output?.appending(path: "\(dark ? "dark" : "light")-import.png"))
            try await render(KeyboardShortcutsHelpView(), width: 640, height: 560, dark: dark,
                             url: output?.appending(path: "\(dark ? "dark" : "light")-keyboard-help.png"))
            model.showAllInspectorPanes()
            try await render(ContextInspectorView().environment(model), width: 280, height: 740, dark: dark,
                             url: output?.appending(path: "\(dark ? "dark" : "light")-all-panes.png"))
            let step = try #require(model.codePaths.selectedPath?.steps.first)
            model.codePaths.resolvedStepID = step.id
            model.codePaths.destinations = [
                CodePathDestination(location: SourceLocation(path: step.path, byteOffset: 10), line: 2),
                CodePathDestination(location: SourceLocation(path: step.path, byteOffset: 40), line: 5)
            ]
            try await render(CodePathsSidebar().environment(model), width: 280, height: 480, dark: dark,
                             url: output?.appending(path: "\(dark ? "dark" : "light")-variants.png"))
            model.codePaths.destinations = []
            model.codePaths.navigationError = "‘missing_function’ was not found in kernel/boot.c in this revision. Update the trace if the symbol was renamed or moved."
            try await render(CodePathsSidebar().environment(model), width: 220, height: 480, dark: dark,
                             url: output?.appending(path: "\(dark ? "dark" : "light")-error.png"))
            model.codePaths.navigationError = nil
        }
    }

    private func render<V: View>(_ view: V, width: Double, height: Double, dark: Bool, url: URL?) async throws {
        let host = NSHostingView(rootView: view.background(Color(nsColor: .textBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(45))
        host.layoutSubtreeIfNeeded()
        #expect(abs(host.frame.width - width) < 1)
        #expect(abs(host.frame.height - height) < 1)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if let url { try #require(bitmap.representation(using: .png, properties: [:])).write(to: url) }
    }
}
