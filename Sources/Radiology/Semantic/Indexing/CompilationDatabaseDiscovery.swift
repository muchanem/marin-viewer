import Foundation

/// The Files browser hides build outputs and Git-ignored files, but Clang
/// needs their compilation database. Probe conventional locations off-main;
/// never execute a build or invent flags for an unconfigured project.
enum CompilationDatabaseDiscovery {
    static func addingDatabases(to inspection: RepositoryInspection) -> RepositoryInspection {
        // PR snapshots may use only inputs with exact revision provenance.
        guard inspection.blobIDs == nil else { return inspection }
        let manifests = inspection.paths.filter { URL(filePath: $0).lastPathComponent == "CMakeLists.txt" }
        let directories = Set([""] + manifests.map { $0.split(separator: "/").dropLast().joined(separator: "/") })
        let locations = ["compile_commands.json", "build/compile_commands.json", "out/compile_commands.json",
                         "Debug/compile_commands.json", "Release/compile_commands.json",
                         "cmake-build-debug/compile_commands.json", "cmake-build-release/compile_commands.json"]
        var paths = Set(inspection.paths)
        for directory in directories.sorted().prefix(64) {
            for location in locations {
                let path = directory.isEmpty ? location : directory + "/" + location
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: inspection.root.appending(path: path).path, isDirectory: &isDirectory),
                   !isDirectory.boolValue { paths.insert(path) }
            }
        }
        return RepositoryInspection(root: inspection.root, paths: paths.sorted(), isGit: inspection.isGit)
    }
}
