import Foundation
import Observation

@Observable @MainActor
final class CodePathModel {
    private(set) var repositoryPath: String?
    private(set) var paths: [CodePath] = []
    var selectedPathID: UUID? {
        didSet { if selectedPathID != oldValue { selectedStepID = nil; navigationError = nil; destinations = []; resolvedStepID = nil } }
    }
    var selectedStepID: UUID?
    var navigationError: String?
    var destinations: [CodePathDestination] = []
    var resolvedStepID: UUID?
    private(set) var storageError: String?
    @ObservationIgnored private let store: CodePathStore

    init(preferences: UserDefaults) { store = CodePathStore(preferences: preferences) }

    var selectedPath: CodePath? { paths.first { $0.id == selectedPathID } }

    func activate(_ root: URL?) {
        let key = root?.standardizedFileURL.resolvingSymlinksInPath().path
        guard key != repositoryPath else { return }
        repositoryPath = key
        paths = []
        storageError = nil
        navigationError = nil
        destinations = []
        resolvedStepID = nil
        do { if let key { paths = try store.load(repositoryPath: key) } }
        catch { storageError = "Could not load code paths: \(error.localizedDescription)" }
        selectedPathID = paths.first?.id
        selectedStepID = nil
    }

    func importText(_ text: String) throws {
        guard let repositoryPath else { throw BrowserError.message("Open a repository before importing a code path.") }
        let path = try CodePathParser.parse(text)
        let updated = paths + [path]
        try store.save(updated, repositoryPath: repositoryPath)
        paths = updated
        selectedPathID = path.id
        storageError = nil
    }

    func removeSelectedPath() {
        guard let repositoryPath, let selectedPathID else { return }
        let updated = paths.filter { $0.id != selectedPathID }
        do {
            try store.save(updated, repositoryPath: repositoryPath)
            paths = updated
            self.selectedPathID = paths.first?.id
            storageError = nil
        } catch { storageError = "Could not save code paths: \(error.localizedDescription)" }
    }
}
