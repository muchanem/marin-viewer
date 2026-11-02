import Foundation

struct SearchOptions: Sendable, Equatable {
    var query = ""
    var isRegex = false
    var caseSensitive = false
    var includeGlob = ""
    var excludeGlob = ""

    var arguments: [String] {
        var args = ["--json", "--line-number", "--column", "--hidden", "--glob", "!.git/**", "--glob", "!.build/**", "--glob", "!build/**", "--glob", "!dist/**", "--glob", "!node_modules/**", "--glob", "!vendor/**", "--glob", "!target/**", "--glob", "!DerivedData/**"]
        if !isRegex { args.append("--fixed-strings") }
        args.append(caseSensitive ? "--case-sensitive" : "--ignore-case")
        if !includeGlob.isEmpty { args += ["--glob", includeGlob] }
        if !excludeGlob.isEmpty { args += ["--glob", "!" + excludeGlob] }
        return args + ["--", query, "."]
    }
}
