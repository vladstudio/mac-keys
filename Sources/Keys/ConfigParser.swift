import Foundation

enum ConfigParser {
    enum Error: Swift.Error, CustomStringConvertible {
        case invalidLine(Int, String)
        case unterminatedString(Int)
        case unknownSection(Int, String)
        case unknownKey(Int, String)
        case noSection(Int)

        var description: String {
            switch self {
            case .invalidLine(let n, let t):     return "Line \(n): invalid syntax '\(t)'"
            case .unterminatedString(let n):     return "Line \(n): unterminated multiline string"
            case .unknownSection(let n, let s):  return "Line \(n): unknown section '\(s)'"
            case .unknownKey(let n, let k):      return "Line \(n): unknown key '\(k)'"
            case .noSection(let n):              return "Line \(n): rule before any [[section]]"
            }
        }
    }

    static func parse(_ content: String) throws -> Config {
        var config = Config()
        var section: String?
        let lines = content.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                i += 1
                continue
            }

            // [[section]]
            if trimmed.hasPrefix("[[") && trimmed.hasSuffix("]]") {
                let name = String(trimmed.dropFirst(2).dropLast(2))
                    .trimmingCharacters(in: .whitespaces)
                guard name == "remap" || name == "snippet" else {
                    throw Error.unknownSection(i + 1, name)
                }
                section = name
                i += 1
                continue
            }

            guard let sec = section else {
                throw Error.noSection(i + 1)
            }

            // Parse the two values on this line
            let (first, rest) = try readValue(trimmed, line: i + 1)
            let (second, remainder) = try readValue(rest, line: i + 1)

            // Check for multiline """ as second value
            var value = second
            if second == "\"\"\"" {
                // Collect until closing """
                var parts: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces) == "\"\"\"" {
                        break
                    }
                    parts.append(lines[i])
                    i += 1
                }
                guard i < lines.count else { throw Error.unterminatedString(i) }
                value = parts.joined(separator: "\n")
            } else if !remainder.trimmingCharacters(in: .whitespaces).isEmpty {
                throw Error.invalidLine(i + 1, trimmed)
            }

            switch sec {
            case "remap":
                guard let input = KeyCodes.parseInput(first) else {
                    throw Error.unknownKey(i + 1, first)
                }
                guard let output = KeyCodes.parseCombo(value) else {
                    throw Error.unknownKey(i + 1, value)
                }
                config.remaps.append(RemapRule(input: input, output: output))
            case "snippet":
                config.snippets.append(SnippetRule(trigger: first, replacement: value))
            default:
                break
            }

            i += 1
        }

        return config
    }

    // MARK: - Private

    /// Reads one value from the start of a string. Returns (value, remaining).
    /// Handles quoted values (respecting spaces) and unquoted tokens.
    private static func readValue(_ s: String, line: Int) throws -> (String, String) {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw Error.invalidLine(line, s)
        }

        if trimmed.hasPrefix("\"\"\"") {
            // Multiline opener — return as-is, caller handles it
            return ("\"\"\"", String(trimmed.dropFirst(3)))
        }

        if trimmed.hasPrefix("\"") {
            // Quoted value — find closing quote
            var result = ""
            var it = trimmed[trimmed.index(after: trimmed.startIndex)...].makeIterator()
            var consumed = 1 // opening quote
            while let ch = it.next() {
                consumed += 1
                if ch == "\\" {
                    if let next = it.next() {
                        consumed += 1
                        switch next {
                        case "n":  result.append("\n")
                        case "t":  result.append("\t")
                        case "\\": result.append("\\")
                        case "\"": result.append("\"")
                        default:   result.append("\\"); result.append(next)
                        }
                    }
                } else if ch == "\"" {
                    return (result, String(trimmed.dropFirst(consumed)))
                } else {
                    result.append(ch)
                }
            }
            throw Error.invalidLine(line, s)
        }

        // Unquoted — read until whitespace
        if let spaceIdx = trimmed.firstIndex(where: { $0.isWhitespace }) {
            return (String(trimmed[..<spaceIdx]), String(trimmed[spaceIdx...]))
        }
        return (trimmed, "")
    }
}
