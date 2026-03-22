import CoreGraphics

enum KeyCodes {
    static let nameToKeyCode: [String: UInt16] = [
        // Letters (ANSI layout)
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05,
        "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
        "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11, "u": 0x20,
        "i": 0x22, "o": 0x1F, "p": 0x23, "l": 0x25, "j": 0x26, "k": 0x28,
        "n": 0x2D, "m": 0x2E,
        // Numbers
        "0": 0x1D, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17,
        "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19,
        // Function keys
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60,
        "f6": 0x61, "f7": 0x62, "f8": 0x64, "f9": 0x65, "f10": 0x6D,
        "f11": 0x67, "f12": 0x6F, "f13": 0x69, "f14": 0x6B, "f15": 0x71,
        "f16": 0x6A, "f17": 0x40, "f18": 0x4F, "f19": 0x50, "f20": 0x5A,
        // Special
        "return": 0x24, "tab": 0x30, "space": 0x31, "delete": 0x33,
        "escape": 0x35, "caps_lock": 0x39, "forward_delete": 0x75,
        // Arrow keys
        "up": 0x7E, "down": 0x7D, "left": 0x7B, "right": 0x7C,
        // Punctuation
        "minus": 0x1B, "equal": 0x18, "left_bracket": 0x21, "right_bracket": 0x1E,
        "backslash": 0x2A, "semicolon": 0x29, "quote": 0x27, "grave": 0x32,
        "comma": 0x2B, "period": 0x2F, "slash": 0x2C,
        // Modifiers (as standalone keys)
        "shift": 0x38, "right_shift": 0x3C,
        "control": 0x3B, "right_control": 0x3E,
        "option": 0x3A, "right_option": 0x3D,
        "command": 0x37, "right_command": 0x36,
    ]

    static let modifierKeyCodes: Set<UInt16> = [
        0x38, 0x3C, // shift
        0x3B, 0x3E, // control
        0x3A, 0x3D, // option
        0x37, 0x36, // command
        0x39,       // caps_lock
    ]

    static let modifierFlags: [String: CGEventFlags] = [
        "shift": .maskShift,
        "control": .maskControl,
        "option": .maskAlternate,
        "command": .maskCommand,
    ]

    static let keyCodeToModifierFlag: [UInt16: CGEventFlags] = [
        0x38: .maskShift, 0x3C: .maskShift,
        0x3B: .maskControl, 0x3E: .maskControl,
        0x3A: .maskAlternate, 0x3D: .maskAlternate,
        0x37: .maskCommand, 0x36: .maskCommand,
        0x39: .maskAlphaShift,
    ]

    static func isModifierPress(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        if keyCode == 0x39 { return true } // caps_lock toggles; treat every event as press
        guard let flag = keyCodeToModifierFlag[keyCode] else { return false }
        return flags.contains(flag)
    }

    /// Parse "option+shift+a" or "caps_lock" into a KeyCombo.
    static func parseCombo(_ string: String) -> KeyCombo? {
        let parts = string.lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else { return nil }

        var flags = CGEventFlags()
        var keyCode: UInt16?

        for part in parts {
            if let flag = modifierFlags[part] {
                flags.insert(flag)
            } else if let code = nameToKeyCode[part] {
                keyCode = code
            } else {
                return nil
            }
        }

        // If every part was a modifier, treat the last one as the physical key
        if keyCode == nil {
            let last = parts.last!
            guard let code = nameToKeyCode[last] else { return nil }
            keyCode = code
            if let flag = modifierFlags[last] {
                flags.remove(flag)
            }
        }

        guard let code = keyCode else { return nil }
        return KeyCombo(keyCode: code, modifiers: flags)
    }

    /// Parse input string — detects sequences ("option, option") vs single combos.
    static func parseInput(_ string: String) -> RemapRule.Input? {
        if string.contains(", ") {
            let steps = string.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let combos = steps.compactMap { parseCombo($0) }
            guard combos.count == steps.count, combos.count >= 2 else { return nil }
            return .sequence(combos)
        }
        guard let combo = parseCombo(string) else { return nil }
        return .single(combo)
    }
}
