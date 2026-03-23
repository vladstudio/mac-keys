import CoreGraphics

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
}

struct Snippet {
    let text: String
    let keyword: String?
}

struct Config {
    var remaps: [RemapRule] = []
    var snippets: [Snippet] = []
}
