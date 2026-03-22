import CoreGraphics

struct KeyCombo {
    let keyCode: UInt16
    let modifiers: CGEventFlags

    static let modifierMask: CGEventFlags = [
        .maskShift, .maskControl, .maskAlternate, .maskCommand, .maskAlphaShift,
    ]
}

struct RemapRule {
    enum Input {
        case single(KeyCombo)
        case sequence([KeyCombo])
    }
    let input: Input
    let output: KeyCombo
}

struct Snippet {
    let text: String
    let keyword: String?
}

struct Config {
    var remaps: [RemapRule] = []
    var snippets: [Snippet] = []
}
