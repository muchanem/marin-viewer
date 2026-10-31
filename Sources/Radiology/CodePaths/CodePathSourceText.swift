import Foundation

enum CodePathSourceText {
    /// Mask comments and string/character literals with spaces while preserving
    /// every original byte coordinate and newline. This is not preprocessing.
    static func masked(_ data: Data) -> [UInt8] {
        let bytes = Array(data)
        var result = bytes
        var index = 0
        var block = false
        var line = false
        var quote: UInt8?
        func blank(_ index: Int) -> UInt8 { [10, 13].contains(bytes[index]) ? bytes[index] : 32 }
        while index < bytes.count {
            let byte = bytes[index]
            let next = index + 1 < bytes.count ? bytes[index + 1] : 0
            if line {
                result[index] = blank(index)
                if byte == 10 { line = false }
            } else if block {
                result[index] = blank(index)
                if byte == 42, next == 47 { result[index + 1] = 32; index += 1; block = false }
            } else if let delimiter = quote {
                result[index] = blank(index)
                if byte == 92, index + 1 < bytes.count {
                    result[index + 1] = blank(index + 1); index += 1
                } else if byte == delimiter { quote = nil }
            } else if byte == 47, next == 47 {
                result[index] = 32; result[index + 1] = 32; index += 1; line = true
            } else if byte == 47, next == 42 {
                result[index] = 32; result[index + 1] = 32; index += 1; block = true
            } else if byte == 34 || byte == 39 {
                result[index] = 32; quote = byte
            }
            index += 1
        }
        return result
    }

    /// Each declaration must live in an opposing branch of a shared #if group.
    /// Ordinary overloads and repeated declarations remain ambiguous.
    static func areConditionalAlternatives(_ positions: [Int], in buffer: SourceBuffer) -> Bool {
        guard positions.count > 1 else { return false }
        let bytes = masked(buffer.data)
        var contexts: [[Int: Int]] = []
        for position in positions {
            var stack: [(start: Int, branch: Int)] = []
            for (index, start) in buffer.lineStarts.enumerated() where start <= position {
                let end = index + 1 < buffer.lineCount ? buffer.lineStarts[index + 1] : bytes.count
                let line = String(decoding: bytes[start..<end], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                guard line.hasPrefix("#") else { continue }
                let directive = line.dropFirst().trimmingCharacters(in: .whitespaces).prefix(while: \.isLetter)
                switch directive {
                case "if", "ifdef", "ifndef": stack.append((start, 0))
                case "elif", "else": if !stack.isEmpty { stack[stack.count - 1].branch += 1 }
                case "endif": if !stack.isEmpty { stack.removeLast() }
                default: break
                }
            }
            contexts.append(Dictionary(uniqueKeysWithValues: stack.map { ($0.start, $0.branch) }))
        }
        for left in contexts.indices {
            for right in contexts.indices where right > left {
                guard contexts[left].contains(where: { start, branch in
                    contexts[right][start].map { $0 != branch } ?? false
                }) else { return false }
            }
        }
        return true
    }
}
