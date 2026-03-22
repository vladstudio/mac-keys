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
        let lines = content.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                i += 1
                continue
            }

            // [section]
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") && !trimmed.hasPrefix("[[") {
                let name = String(trimmed.dropFirst(1).dropLast(1))
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

            switch sec {
            case "remap":
                let (first, second, linesConsumed) = try parseCSVLine(lines: lines, startIndex: i)
                guard let input = KeyCodes.parseInput(first) else {
                    throw Error.unknownKey(i + 1, first)
                }
                guard let output = KeyCodes.parseOutput(second) else {
                    throw Error.unknownKey(i + 1, second)
                }
                config.remaps.append(RemapRule(input: input, output: output))
                i += linesConsumed
                continue
            case "snippet":
                let remaining = lines[i...].joined(separator: "\n")
                let (text, afterText) = try readCSVField(remaining, from: remaining.startIndex, line: i + 1)
                var keyword: String?
                var endPos = afterText
                // Check for optional comma + keyword
                var pos = afterText
                while pos < remaining.endIndex && remaining[pos] == " " {
                    pos = remaining.index(after: pos)
                }
                if pos < remaining.endIndex && remaining[pos] == "," {
                    pos = remaining.index(after: pos)
                    let (kw, afterKw) = try readCSVField(remaining, from: pos, line: i + 1)
                    if !kw.isEmpty { keyword = kw }
                    endPos = afterKw
                }
                let linesConsumed = remaining[remaining.startIndex..<endPos].filter { $0 == "\n" }.count + 1
                config.snippets.append(Snippet(text: text, keyword: keyword))
                i += linesConsumed
                continue
            default:
                break
            }

            i += 1
        }

        return config
    }

    // MARK: - Private

    /// Parses a CSV row starting at `startIndex`, returning (field1, field2, linesConsumed).
    /// Supports RFC 4180 quoting: fields wrapped in double quotes can contain commas,
    /// newlines, and escaped double quotes (doubled: "").
    private static func parseCSVLine(lines: [String], startIndex: Int) throws -> (String, String, Int) {
        // Join from startIndex to handle multiline quoted fields
        let remaining = lines[startIndex...].joined(separator: "\n")
        var pos = remaining.startIndex

        // Skip leading whitespace
        while pos < remaining.endIndex && remaining[pos].isWhitespace && remaining[pos] != "\n" {
            pos = remaining.index(after: pos)
        }

        let (first, afterFirst) = try readCSVField(remaining, from: pos, line: startIndex + 1)

        // Expect comma separator
        pos = afterFirst
        while pos < remaining.endIndex && remaining[pos].isWhitespace && remaining[pos] != "\n" {
            pos = remaining.index(after: pos)
        }
        guard pos < remaining.endIndex && remaining[pos] == "," else {
            throw Error.invalidLine(startIndex + 1, String(lines[startIndex]))
        }
        pos = remaining.index(after: pos) // skip comma

        let (second, afterSecond) = try readCSVField(remaining, from: pos, line: startIndex + 1)

        // Count how many lines were consumed
        let consumed = remaining[remaining.startIndex..<afterSecond]
        let linesConsumed = consumed.filter { $0 == "\n" }.count + 1

        return (first, second, linesConsumed)
    }

    /// Reads one CSV field from position `from`. Returns (fieldValue, indexAfterField).
    private static func readCSVField(_ s: String, from start: String.Index, line: Int) throws -> (String, String.Index) {
        var pos = start

        // Skip leading whitespace (not newlines)
        while pos < s.endIndex && s[pos] == " " {
            pos = s.index(after: pos)
        }

        guard pos < s.endIndex else {
            throw Error.invalidLine(line, "")
        }

        if s[pos] == "\"" {
            // Quoted field — read until unescaped closing quote
            pos = s.index(after: pos) // skip opening quote
            var result = ""
            while pos < s.endIndex {
                if s[pos] == "\"" {
                    let next = s.index(after: pos)
                    if next < s.endIndex && s[next] == "\"" {
                        // Escaped double quote
                        result.append("\"")
                        pos = s.index(after: next)
                    } else {
                        // Closing quote
                        return (result, next)
                    }
                } else {
                    result.append(s[pos])
                    pos = s.index(after: pos)
                }
            }
            throw Error.unterminatedQuote(line)
        } else {
            // Unquoted field — read until comma or newline
            let fieldStart = pos
            while pos < s.endIndex && s[pos] != "," && s[pos] != "\n" {
                pos = s.index(after: pos)
            }
            let value = String(s[fieldStart..<pos]).trimmingCharacters(in: .init(charactersIn: " "))
            return (value, pos)
        }
    }
}
