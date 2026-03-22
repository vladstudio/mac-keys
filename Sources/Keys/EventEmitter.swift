import CoreGraphics

enum EventEmitter {
    /// Magic value to tag events we emit, so we can skip them in the tap callback.
    static let marker: Int64 = 0x4B455953 // "KEYS"

    private static let eventSource = CGEventSource(stateID: .privateState)

    static func emit(keyCode: UInt16, flags: CGEventFlags = [], keyDown: Bool) {
        guard let event = CGEvent(keyboardEventSource: eventSource,
                                  virtualKey: keyCode, keyDown: keyDown) else { return }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cgAnnotatedSessionEventTap)
    }

    static func emitKeyPress(keyCode: UInt16, flags: CGEventFlags = []) {
        emit(keyCode: keyCode, flags: flags, keyDown: true)
        emit(keyCode: keyCode, flags: flags, keyDown: false)
    }

    static func emitBackspaces(_ count: Int) {
        for _ in 0..<count {
            emitKeyPress(keyCode: 0x33) // delete key
        }
    }

    static func emitText(_ text: String) {
        for char in text {
            var utf16 = Array(char.utf16)
            guard let down = CGEvent(keyboardEventSource: eventSource,
                                     virtualKey: 0, keyDown: true) else { continue }
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            down.setIntegerValueField(.eventSourceUserData, value: marker)
            down.post(tap: .cgAnnotatedSessionEventTap)

            guard let up = CGEvent(keyboardEventSource: eventSource,
                                   virtualKey: 0, keyDown: false) else { continue }
            up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            up.setIntegerValueField(.eventSourceUserData, value: marker)
            up.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
