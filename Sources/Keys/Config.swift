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

struct SnippetRule {
    let trigger: String
    let replacement: String
}

struct Config {
    var remaps: [RemapRule] = []
    var snippets: [SnippetRule] = []
}
