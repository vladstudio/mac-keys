import Foundation

enum TOMLParser {
    enum Error: Swift.Error, CustomStringConvertible {
        case invalidLine(Int, String)
        case unterminatedString(Int)
        case missingField(String, String)
        case unknownKey(String, String)

        var description: String {
            switch self {
            case .invalidLine(let n, let t):       return "Line \(n): invalid syntax '\(t)'"
            case .unterminatedString(let n):       return "Line \(n): unterminated multiline string"
            case .missingField(let s, let f):      return "[[\(s)]] missing required field '\(f)'"
            case .unknownKey(let f, let v):        return "Unknown key name '\(v)' in '\(f)'"
            }
        }
    }

    static func parse(_ content: String) throws -> Config {
        var remapEntries: [[String: String]] = []
        var snippetEntries: [[String: String]] = []
        var currentSection: String?
        var currentFields: [String: String] = [:]
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
                if let sec = currentSection, !currentFields.isEmpty {
                    saveEntry(sec, currentFields, &remapEntries, &snippetEntries)
                }
                currentSection = String(trimmed.dropFirst(2).dropLast(2))
                    .trimmingCharacters(in: .whitespaces)
                currentFields = [:]
                i += 1
                continue
            }

            // key = value
            guard let eq = trimmed.firstIndex(of: "=") else {
                throw Error.invalidLine(i + 1, trimmed)
            }
            let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
            let raw = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)

            if raw.hasPrefix("\"\"\"") {
                var body = String(raw.dropFirst(3))
                if body.hasSuffix("\"\"\"") {
                    body = String(body.dropLast(3))
                } else {
                    var parts: [String] = body.isEmpty ? [] : [body]
                    i += 1
                    while i < lines.count {
                        if let r = lines[i].range(of: "\"\"\"") {
                            parts.append(String(lines[i][..<r.lowerBound]))
                            break
                        }
                        parts.append(lines[i])
                        i += 1
                    }
                    guard i < lines.count else { throw Error.unterminatedString(i) }
                    body = parts.joined(separator: "\n")
                }
                currentFields[key] = unescape(body)
            } else if raw.hasPrefix("\"") && raw.hasSuffix("\"") && raw.count >= 2 {
                currentFields[key] = unescape(String(raw.dropFirst().dropLast()))
            } else {
                throw Error.invalidLine(i + 1, trimmed)
            }
            i += 1
        }

        if let sec = currentSection, !currentFields.isEmpty {
            saveEntry(sec, currentFields, &remapEntries, &snippetEntries)
        }

        return try buildConfig(remapEntries: remapEntries, snippetEntries: snippetEntries)
    }

    // MARK: - Private helpers

    private static func saveEntry(
        _ section: String,
        _ fields: [String: String],
        _ remaps: inout [[String: String]],
        _ snippets: inout [[String: String]]
    ) {
        switch section {
        case "remap":   remaps.append(fields)
        case "snippet": snippets.append(fields)
        default: break
        }
    }

    private static func unescape(_ s: String) -> String {
        var result = ""
        var it = s.makeIterator()
        while let ch = it.next() {
            if ch == "\\" {
                switch it.next() {
                case "n":  result.append("\n")
                case "t":  result.append("\t")
                case "\\": result.append("\\")
                case "\"": result.append("\"")
                case let c?: result.append("\\"); result.append(c)
                case nil:  result.append("\\")
                }
            } else {
                result.append(ch)
            }
        }
        return result
    }

    private static func buildConfig(
        remapEntries: [[String: String]],
        snippetEntries: [[String: String]]
    ) throws -> Config {
        var config = Config()

        for entry in remapEntries {
            guard let inputStr = entry["input"] else {
                throw Error.missingField("remap", "input")
            }
            guard let outputStr = entry["output"] else {
                throw Error.missingField("remap", "output")
            }
            guard let input = KeyCodes.parseInput(inputStr) else {
                throw Error.unknownKey("input", inputStr)
            }
            guard let output = KeyCodes.parseCombo(outputStr) else {
                throw Error.unknownKey("output", outputStr)
            }
            config.remaps.append(RemapRule(input: input, output: output))
        }

        for entry in snippetEntries {
            guard let trigger = entry["trigger"] else {
                throw Error.missingField("snippet", "trigger")
            }
            guard let replacement = entry["replacement"] else {
                throw Error.missingField("snippet", "replacement")
            }
            config.snippets.append(SnippetRule(trigger: trigger, replacement: replacement))
        }

        return config
    }
}
