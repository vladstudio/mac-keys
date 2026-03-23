import CoreGraphics

enum KeyboardTarget: Hashable {
    case all, `internal`, external

    func matches(isInternal: Bool) -> Bool {
        switch self {
        case .all: return true
        case .internal: return isInternal
        case .external: return !isInternal
        }
    }
}

struct KeyCombo {
    let keyCode: UInt16
    let modifiers: CGEventFlags

    static let modifierMask: CGEventFlags = [
        .maskShift, .maskControl, .maskAlternate, .maskCommand, .maskAlphaShift,
    ]
}

enum RemapOutput {
    case key(KeyCombo)
    case showPicker
    case toggleInput
    case openApp(String)
    case bash(String)
    case paste(String)
    case ignore
}

struct RemapRule {
    enum Input {
        case single(KeyCombo)
        case sequence([KeyCombo])
        case mediaKey(Int32)
    }
    let input: Input
    let output: RemapOutput
    var keyboard: KeyboardTarget = .all
}

struct Snippet {
    let text: String
    let keyword: String?
}

struct Config {
    var remaps: [RemapRule] = []
    var snippets: [Snippet] = []
}
