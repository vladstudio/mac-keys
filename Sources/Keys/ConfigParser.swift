import Foundation

enum ConfigParser {
    enum Error: Swift.Error, CustomStringConvertible {
        case invalidLine(Int, String)
        case unterminatedQuote(Int)
        case unknownSection(Int, String)
        case unknownKey(Int, String)
        case noSection(Int)

        var description: String {
            switch self {
            case .invalidLine(let n, let t):     return "Line \(n): invalid syntax '\(t)'"
            case .unterminatedQuote(let n):      return "Line \(n): unterminated quoted field"
            case .unknownSection(let n, let s):  return "Line \(n): unknown section '\(s)'"
            case .unknownKey(let n, let k):      return "Line \(n): unknown key '\(k)'"
            case .noSection(let n):              return "Line \(n): rule before any [section]"
            }
        }
    }

    static func parse(_ content: String) throws -> Config {
        var config = Config()
        var section: String?
        var currentKeyboard: KeyboardTarget = .all
        let lines = content.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                i += 1
                continue
            }

            // [section]
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let raw = String(trimmed.dropFirst(1).dropLast(1))
                    .trimmingCharacters(in: .whitespaces)
                let name = raw.lowercased()
                switch name {
                case "remap":
                    section = "remap"; currentKeyboard = .all
                case "remap:internal":
                    section = "remap"; currentKeyboard = .internal
                case "remap:external":
                    section = "remap"; currentKeyboard = .external
                case "snippet":
                    section = "snippet"
                default:
                    throw Error.unknownSection(i + 1, raw)
                }
                i += 1
                continue
            }

            guard let sec = section else {
                throw Error.noSection(i + 1)
            }

            switch sec {
            case "remap":
                // input: output — split on first ":"
                guard let colonIdx = trimmed.firstIndex(of: ":") else {
                    throw Error.invalidLine(i + 1, String(lines[i]))
                }
                let inputStr = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let outputStr = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                guard !inputStr.isEmpty, !outputStr.isEmpty else {
                    throw Error.invalidLine(i + 1, String(lines[i]))
                }
                guard let input = KeyCodes.parseInput(inputStr) else {
                    throw Error.unknownKey(i + 1, inputStr)
                }
                guard let output = KeyCodes.parseOutput(outputStr) else {
                    throw Error.unknownKey(i + 1, outputStr)
                }
                if case .sequence(let combos) = input,
                   !(combos.count == 2 && combos[0].keyCode == combos[1].keyCode) {
                    throw Error.invalidLine(i + 1, "only double-tap sequences supported")
                }
                config.remaps.append(RemapRule(input: input, output: output, keyboard: currentKeyboard))
                i += 1

            case "snippet":
                if trimmed.hasPrefix("\"") {
                    // Quoted snippet (may contain colons, may span lines). No alias.
                    let remaining = lines[i...].joined(separator: "\n")
                    let (text, afterIdx) = try readQuoted(remaining, from: remaining.index(after: remaining.startIndex), line: i + 1)
                    let linesConsumed = remaining[remaining.startIndex..<afterIdx].filter { $0 == "\n" }.count + 1
                    config.snippets.append(Snippet(text: text, keyword: nil))
                    i += linesConsumed
                } else if let colonIdx = trimmed.firstIndex(of: ":") {
                    // alias: text
                    let alias = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                    let text = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                    guard !alias.isEmpty, !text.isEmpty else {
                        throw Error.invalidLine(i + 1, String(lines[i]))
                    }
                    config.snippets.append(Snippet(text: text, keyword: alias))
                    i += 1
                } else {
                    // Plain text, no alias
                    config.snippets.append(Snippet(text: trimmed, keyword: nil))
                    i += 1
                }

            default:
                i += 1
            }
        }

        return config
    }

    // MARK: - Private

    /// Read quoted string starting after the opening `"`. Returns (text, indexAfterClosingQuote).
    /// Supports multiline. `""` escapes a literal `"`.
    private static func readQuoted(_ s: String, from start: String.Index, line: Int) throws -> (String, String.Index) {
        var pos = start
        var result = ""
        while pos < s.endIndex {
            if s[pos] == "\"" {
                let next = s.index(after: pos)
                if next < s.endIndex && s[next] == "\"" {
                    result.append("\"")
                    pos = s.index(after: next)
                } else {
                    return (result, next)
                }
            } else {
                result.append(s[pos])
                pos = s.index(after: pos)
            }
        }
        throw Error.unterminatedQuote(line)
    }
}
