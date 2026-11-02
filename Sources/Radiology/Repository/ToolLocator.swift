import Foundation

enum ToolLocator {
    static func executable(_ name: String) -> URL? {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "RadiologyRipgrepPath") as? String,
           name == "rg", FileManager.default.isExecutableFile(atPath: configured) {
            return URL(filePath: configured)
        }
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", NSHomeDirectory() + "/.cargo/bin"]
        return paths.lazy.map { URL(filePath: $0).appending(path: name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
