import Foundation

actor IndexingPersonalityStore {
    static let shared = IndexingPersonalityStore()
    static let directory = URL.applicationSupportDirectory.appending(path: "Radiology/IndexingPersonalities", directoryHint: .isDirectory)
    static let scripts = ["sel4_pipeline.py", "sel4_prepare.py", "sel4_index.py", "sel4_sources.py", "sel4_scip_union.py"]
    let directory: URL

    init(directory: URL = IndexingPersonalityStore.directory) { self.directory = directory }

    static func template(_ personality: IndexingPersonality) throws -> URL {
        guard let url = Bundle.module.url(forResource: personality.rawValue, withExtension: "toml", subdirectory: "IndexingPersonalities") else {
            throw BrowserError.message("Missing bundled \(personality.name) indexing personality.")
        }
        return url
    }

    func load(_ personality: IndexingPersonality) throws -> IndexingPersonalitySettings {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: personality.rawValue + ".toml")
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.copyItem(at: Self.template(personality), to: url)
        }
        var implementation = Data()
        if personality == .sel4 {
            for script in Self.scripts {
                implementation.append(Data((script + "\u{0}").utf8))
                implementation.append(try Data(contentsOf: ScipKotlinIndexer.script(script)))
            }
        }
        return try IndexingPersonalitySettings(personality: personality, url: url, data: Data(contentsOf: url), implementation: implementation)
    }
}
