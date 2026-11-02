import Foundation

/// Compiler-resolved Kotlin/Java SCIP for the actual Gradle project, including
/// AGP 9's built-in Kotlin. Builds run only in an isolated input workspace.
struct ScipKotlinIndexer: SemanticIndexer {
    // This upstream revision contains Kotlin 2.4.20 compiler compatibility.
    // v0.13.1's embedded plugin targets Kotlin 2.2 and cannot justify tkos support.
    static let sourceCommit = "9f288dd339c7e9fc257a7b21714d9a402fd4d837"
    static let toolVersion = "0.13.1-radiology-9f288dd339c7"
    static let gradleVersion = "9.7.1"
    let id = "scip-kotlin"
    let displayName = "Kotlin SCIP (scip-java)"
    let defaultEncoding = ColumnEncoding.utf16
    let pinnedVersion: String? = Self.toolVersion
    let requiresIsolatedWorkspace = true
    let manualInstallation = "Install JDK 17 or newer, then use Install in the indexing status panel to build Marin Viewer's pinned Kotlin compiler indexer. A real Gradle build and its dependencies are required."

    func strategies(for inspection: RepositoryInspection) -> [IndexingStrategy] {
        let markers: Set<String> = ["settings.gradle", "settings.gradle.kts", "build.gradle", "build.gradle.kts"]
        let directories = Set(inspection.paths.filter { markers.contains(URL(filePath: $0).lastPathComponent) }
            .map { $0.split(separator: "/").dropLast().joined(separator: "/") })
            .sorted { ($0.count, $0) < ($1.count, $1) }
        var roots: [String] = []
        for directory in directories where !roots.contains(where: { $0.isEmpty || directory.hasPrefix($0 + "/") }) {
            roots.append(directory)
        }
        return roots.filter { inspection.contains(extension: "kt", under: $0) || inspection.contains(extension: "java", under: $0) }.map { directory in
            let evidence = inspection.paths.filter {
                let url = URL(filePath: $0)
                return markers.contains(url.lastPathComponent) && $0.split(separator: "/").dropLast().joined(separator: "/") == directory
            }.sorted()
            return IndexingStrategy(indexerID: id, projectDirectory: directory, evidence: evidence, languages: ["Kotlin", "Java"])
        }
    }

    static func toolRoot(in tools: ToolDirectory) -> URL { tools.url.appending(path: "kotlin-scip", directoryHint: .isDirectory) }

    func locate(in tools: ToolDirectory) -> URL? {
        tools.locate("scip-java", candidates: [Self.toolRoot(in: tools).appending(path: "distribution/bin/scip-java")])
    }

    static func script(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "IndexingScripts")
            ?? URL(filePath: "/missing-radiology-indexing-resource/\(name)")
    }

    static func gradle(in tools: ToolDirectory) -> URL? {
        let managed = toolRoot(in: tools).appending(path: "gradle-\(gradleVersion)/bin/gradle")
        let wrappers = URL(filePath: NSHomeDirectory()).appending(path: ".gradle/wrapper/dists/gradle-\(gradleVersion)-all")
        let children = (try? FileManager.default.contentsOfDirectory(at: wrappers, includingPropertiesForKeys: nil)) ?? []
        return tools.locate("gradle", candidates: [managed] + children.sorted { $0.path < $1.path }
            .map { $0.appending(path: "gradle-\(gradleVersion)/bin/gradle") })
    }

    func command(for strategy: IndexingStrategy, inspection: RepositoryInspection, executable: URL, output: URL, tools: ToolDirectory) -> IndexCommand {
        let distribution = Self.toolRoot(in: tools).appending(path: "distribution")
        var extra: [String: String] = [:]
        let sdk = URL(filePath: NSHomeDirectory()).appending(path: "Library/Android/sdk")
        if ProcessInfo.processInfo.environment["ANDROID_HOME"] == nil, FileManager.default.fileExists(atPath: sdk.path) {
            extra["ANDROID_HOME"] = sdk.path
        }
        return IndexCommand(executable: URL(filePath: "/bin/sh"),
                            arguments: [Self.script("kotlin-index.sh").path, executable.resolvingSymlinksInPath().path, output.path,
                                        Self.script("kotlin-index.gradle").path, distribution.appending(path: "scip-kotlinc.jar").path,
                                        distribution.appending(path: "scip-plugin.jar").path, Self.gradle(in: tools)?.path ?? ""],
                            directory: inspection.root.appending(path: strategy.projectDirectory, directoryHint: .isDirectory),
                            environment: ToolDirectory.childEnvironment(extra: extra))
    }

    func provisioning(in tools: ToolDirectory) -> ProvisioningPlan? {
        guard ToolLocator.executable("java") != nil else { return nil }
        return ProvisioningPlan(prerequisites: ["JDK 17 or newer"],
                                summary: "Build the pinned scip-java Kotlin compiler plugin in Marin Viewer's tools directory. The attached checkout is not built or modified.",
                                steps: [IndexCommand(executable: URL(filePath: "/bin/sh"),
                                                     arguments: [Self.script("install-kotlin-indexer.sh").path, Self.toolRoot(in: tools).path,
                                                                 Self.sourceCommit, Self.toolVersion, Self.gradle(in: tools)?.path ?? "", Self.gradleVersion],
                                                     directory: tools.url, environment: ToolDirectory.childEnvironment())])
    }
}
