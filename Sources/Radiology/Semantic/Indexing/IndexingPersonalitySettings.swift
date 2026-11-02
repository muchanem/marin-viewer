import Foundation
import CryptoKit

struct IndexingPersonalitySettings: Sendable {
    let personality: IndexingPersonality
    let url: URL
    let data: Data
    let digest: String
    let name: String
    let summary: String
    let engine: String
    let indexerIDs: [String]
    let projectLimit: Int
    let clangJobs: Int
    let bootstrapPython: [String]

    init(personality: IndexingPersonality, url: URL, data: Data, implementation: Data = Data()) throws {
        guard data.count <= 2 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else {
            throw BrowserError.message("Personality settings must be UTF-8 TOML under 2 MiB.")
        }
        let values = try PersonalityTOML.rootValues(text)
        let allowed: Set<String> = ["schema_version", "id", "name", "summary", "engine", "indexers", "project_limit", "clang_jobs", "bootstrap_python"]
        guard Set(values.keys).isSubset(of: allowed), values["schema_version"] == "1",
              try PersonalityTOML.string(values["id"]) == personality.rawValue else {
            throw BrowserError.message("Invalid personality identity, schema version, or unknown root setting in \(url.lastPathComponent).")
        }
        let engine = try PersonalityTOML.string(values["engine"])
        guard engine == (personality == .default ? "automatic" : "sel4"),
              let limit = values["project_limit"].flatMap(Int.init), (1...256).contains(limit),
              let jobs = values["clang_jobs"].flatMap(Int.init), (1...64).contains(jobs) else {
            throw BrowserError.message("Invalid engine, project_limit (1–256), or clang_jobs (1–64) in personality settings.")
        }
        self.personality = personality; self.url = url; self.data = data
        self.engine = engine; projectLimit = limit; clangJobs = jobs
        name = try PersonalityTOML.string(values["name"])
        summary = try PersonalityTOML.string(values["summary"])
        indexerIDs = try PersonalityTOML.strings(values["indexers"])
        if personality == .sel4, indexerIDs != ["scip-sel4"] {
            throw BrowserError.message("The seL4 personality requires the scip-sel4 configuration-union indexer.")
        }
        bootstrapPython = try values["bootstrap_python"].map { try PersonalityTOML.strings($0) }
            ?? ["python3.11", "python3.12", "python3.13", "python3.14", "python3"]
        var hash = SHA256(); hash.update(data: data); hash.update(data: implementation)
        digest = hash.finalize().map { IndexCache.hexByte($0) }.joined()
    }
}
