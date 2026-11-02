import Foundation

/// Development launch arguments: `--repository PATH` opens a folder, the
/// optional `--pull-request N` opens that pull request of it, and the
/// optional `--file RELATIVE_PATH` selects a file (in the review's After
/// revision when a pull request was given), which makes launching straight
/// into a given language or review reproducible.
/// `--verify-resources` is handled before any window is created.
struct LaunchArguments {
    let repository: String?
    let file: String?
    let pullRequest: Int?

    init(_ arguments: [String]) {
        repository = Self.value(of: "--repository", in: arguments)
        file = Self.value(of: "--file", in: arguments)
        pullRequest = Self.value(of: "--pull-request", in: arguments).flatMap(Int.init)
    }

    private static func value(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.count > index + 1 else { return nil }
        return arguments[index + 1]
    }
}
