import Foundation

/// Conservative, deterministic knowledge about what runtime packages and
/// FFI bindings look like. Keyed by SCIP scheme and package ownership, never
/// by identifier spelling. Only the rust-analyzer scheme is verified against
/// a real index (tkos, 2026-10-04); other schemes have no profile and leave
/// non-repository symbols `unknown`.
enum CriticalityProfiles {
    static let verifiedScheme = "rust-analyzer"

    /// Packages whose contents are language/runtime plumbing unless a
    /// system-facing profile says otherwise.
    static let runtimePackages: Set<String> = ["core", "alloc", "std"]

    /// Packages known to be bindings to native libraries or platform ABIs.
    /// This is an explicit identity list: a `-sys` suffix alone is a naming
    /// convention, not proof of ownership, so an unlisted `-sys` crate stays
    /// neutral until it is added here or marked by the reader.
    static let ffiPackages: Set<String> = [
        "libc", "jni", "jni-sys", "windows-sys", "winapi", "ndk-sys", "core-foundation-sys", "objc", "objc2", "block2",
        "libsqlite3-sys", "openssl-sys", "libz-sys", "bzip2-sys", "zstd-sys", "lzma-sys", "curl-sys", "libgit2-sys",
        "libssh2-sys", "ffmpeg-sys-next", "v8", "deno_core",
    ]

    /// Descriptor prefixes inside runtime packages that reach the system:
    /// files, sockets, processes, environment, OS handles, threads, I/O
    /// handles, and clocks. Error and buffer plumbing types are excluded.
    /// Raw-pointer and `mem` helpers are deliberately absent: they are
    /// language facilities, not platform boundaries, and get no promotion
    /// without boundary evidence.
    static let systemDescriptorPrefixes: [String: [String]] = [
        "std": ["fs/", "net/", "process/", "env/", "os/", "thread/", "io/", "time/SystemTime", "time/Instant"],
        "tokio": ["fs/", "net/", "process/", "signal/"],
    ]

    /// rust-analyzer descriptors follow the standard library's module files
    /// (`io/error/impl#[Error]last_os_error().`, `io/error/ErrorKind#`,
    /// `io/buffered/…`, `io/cursor/…`, `io/util/…`), verified on the tkos
    /// index. Those modules are error, buffer, and adapter plumbing.
    static let systemDescriptorExclusions: [String: [String]] = [
        "std": ["io/error/", "io/cursor/", "io/buffered/", "io/util/", "io/impls/"],
    ]

    /// Descriptor prefixes that are FFI even inside the standard library.
    static let ffiDescriptorPrefixes: [String: [String]] = [
        "core": ["ffi/"],
        "std": ["ffi/", "os/"],
    ]

    static func isFFIPackage(_ name: String) -> Bool { ffiPackages.contains(name) }

    static func isFFIDescriptor(package: String, descriptors: Substring) -> Bool {
        (ffiDescriptorPrefixes[package] ?? []).contains { descriptors.hasPrefix($0) }
    }

    static func isSystemAPI(package: String, descriptors: Substring) -> Bool {
        guard (systemDescriptorPrefixes[package] ?? []).contains(where: { descriptors.hasPrefix($0) }) else { return false }
        return !(systemDescriptorExclusions[package] ?? []).contains { descriptors.hasPrefix($0) }
    }
}
