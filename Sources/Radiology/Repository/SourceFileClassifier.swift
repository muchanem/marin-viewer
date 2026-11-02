import Foundation

/// What Source Files Only keeps: handwritten code and headers, outside build
/// outputs, dependency trees, caches, and generated files; not
/// documentation, data, manifests, or configuration. See plans/source-filters.md.
enum SourceFileClassifier {
    static let sourceExtensions: Set<String> = [
        "swift", "rs", "go", "py", "pyi", "js", "jsx", "mjs", "cjs", "ts", "tsx", "mts", "cts",
        "kt", "kts", "java", "scala", "sc", "groovy", "c", "h", "cc", "cpp", "cxx", "c++", "hh", "hpp", "hxx",
        "h++", "inl", "ipp", "tpp", "tcc", "m", "mm", "cs", "fs", "fsi", "fsx", "rb", "php", "lua", "zig", "nim", "dart",
        "ex", "exs", "erl", "hrl", "hs", "lhs", "ml", "mli", "clj", "cljs", "cljc", "elm", "jl", "r",
        "pl", "pm", "sh", "bash", "zsh", "fish", "sql", "proto", "thrift", "graphql", "gql", "vue", "svelte",
        "astro", "s", "asm", "cu", "cuh", "metal", "glsl", "vert", "frag", "hlsl", "wgsl", "sv", "vhd",
        "vhdl", "ada", "adb", "ads", "f90", "f95", "pas", "cr", "gleam", "odin", "sol", "move", "cairo",
    ]
    /// Build outputs, dependency trees, and caches; any hidden directory too.
    static let excludedDirectories: Set<String> = [
        "target", "build", "dist", "out", "DerivedData", "node_modules", "vendor", "Pods", "Carthage",
        "bower_components", "jspm_packages", "coverage", "__pycache__", "venv", "site-packages",
        "generated", "__generated__",
    ]
    static let manifestNames: Set<String> = [
        "Package.swift", "build.gradle.kts", "settings.gradle.kts", "setup.py",
    ]
    static let generatedSuffixes = [
        ".min.js", ".min.css", ".bundle.js", ".g.dart", ".pb.go", "_pb2.py", "_pb2_grpc.py", ".pb.swift",
    ]
    static let configScriptExtensions: Set<String> = ["js", "ts", "mjs", "cjs", "mts", "cts"]

    static func isSourceFile(_ path: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        guard let name = components.last, !name.hasPrefix(".") else { return false }
        for directory in components.dropLast() where directory.hasPrefix(".") || excludedDirectories.contains(directory) {
            return false
        }
        let url = URL(filePath: name)
        let fileExtension = url.pathExtension.lowercased()
        guard sourceExtensions.contains(fileExtension) else { return false }
        if manifestNames.contains(name) { return false }
        if generatedSuffixes.contains(where: name.hasSuffix) || name.contains(".generated.") { return false }
        // webpack.config.js, vite.config.ts, jest.config.cjs, …
        if configScriptExtensions.contains(fileExtension),
           url.deletingPathExtension().lastPathComponent.hasSuffix(".config") { return false }
        return true
    }
}
