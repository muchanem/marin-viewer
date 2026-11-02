import Foundation
import ViewerCore

/// Reading Marin outside PR review (DESIGN.md §2): the strip shows the open file's subsystem
/// page, with its description, its place among the other packages and its own map.
extension ViewerStore {
    /// Reads the subsystem pages, once, off the main actor.
    func loadSystemPages() async {
        guard systemPages.isEmpty else { return }
        let wordbase = paths.wordbase
        let pages = await Task.detached { SystemPage.readAll(wordbase: wordbase) }.value
        guard systemPages.isEmpty else { return }
        systemPages = pages
        if let readingPath { follow(path: readingPath) }
    }

    /// The main reader opened `path` in the repository at `root`. A file of the Marin clone that
    /// a page covers makes that page the strip's; any other file leaves the strip as it is, so
    /// stepping into `experiments/` does not make it jump.
    func followOpenFile(_ path: String?, root: URL?) {
        guard let path, let root, Self.sameDirectory(root, paths.marin) else {
            readingPath = nil
            return
        }
        readingPath = path
        follow(path: path)
    }

    private func follow(path: String) {
        guard let page = SystemPage.covering(path, in: systemPages), page.name != readingSystem?.name else { return }
        showSystem(page)
    }

    /// Shows `name`'s page in the strip, as a click on its box or chip does.
    func showSystem(named name: String) {
        guard let page = systemPage(named: name) else {
            showToast("No subsystem page describes \(name) yet.")
            return
        }
        showSystem(page)
    }

    func systemPage(named name: String) -> SystemPage? {
        systemPages.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func showSystem(_ page: SystemPage) {
        readingSystem = page
        systemDescriptionLevel = 1
        if systemLayouts[page.name] == nil, page.diagram != nil {
            Task { await layoutSystem(page) }
        }
    }

    /// Asks the sidecar to lay out `page`'s map, with box sizes measured in the app's fonts.
    func layoutSystem(_ page: SystemPage) async {
        guard let diagram = page.diagram else { return }
        systemLayouts[page.name] = .loading
        do {
            let result = try await sidecar.request([
                "type": "layout",
                "diagram": try JSONValue.encoding(diagram),
                "sizes": DiagramMetrics.sizes(for: diagram, key: .system),
                "edge_labels": DiagramMetrics.edgeLabels(for: diagram),
            ])
            systemLayouts[page.name] = .ready(try result.decode(DiagramLayoutResult.self))
        } catch {
            systemLayouts[page.name] = .failed(error.localizedDescription)
        }
    }

    static func sameDirectory(_ a: URL, _ b: URL) -> Bool {
        a.standardizedFileURL.resolvingSymlinksInPath().path == b.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
