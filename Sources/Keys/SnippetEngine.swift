import CoreGraphics
import Foundation

class SnippetEngine {
    private var rules: [SnippetRule] = []
    private var buffer: String = ""
    private var maxTriggerLen: Int = 0
    private var idleTimer: DispatchSourceTimer?
    private let idleTimeout: TimeInterval = 3.0

    func update(rules: [SnippetRule]) {
        self.rules = rules
        maxTriggerLen = rules.map(\.trigger.count).max() ?? 0
        buffer = ""
    }

    /// Returns `true` if the event should be suppressed (snippet matched).
    func handleKeyDown(event: CGEvent) -> Bool {
        guard !rules.isEmpty else { return false }

        guard let char = character(from: event) else {
            clearBuffer()
            return false
        }

        buffer.append(char)
        resetIdleTimer()

        for rule in rules {
            if buffer.hasSuffix(rule.trigger) {
                let deleteCount = rule.trigger.count - 1 // current keystroke is suppressed
                EventEmitter.emitBackspaces(deleteCount)
                EventEmitter.emitText(rule.replacement)
                buffer = ""
                return true
            }
        }

        // Keep buffer bounded
        if buffer.count > maxTriggerLen {
            buffer = String(buffer.suffix(maxTriggerLen))
        }

        return false
    }

    func clearBuffer() {
        buffer = ""
        idleTimer?.cancel()
        idleTimer = nil
    }

    // MARK: - Private

    private func resetIdleTimer() {
        idleTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + idleTimeout)
        timer.setEventHandler { [weak self] in
            self?.clearBuffer()
        }
        idleTimer = timer
        timer.resume()
    }

    private func character(from event: CGEvent) -> Character? {
        // Skip command / control combos — they're shortcuts, not text input
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            return nil
        }

        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(
            maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return nil }
        guard let scalar = UnicodeScalar(chars[0]), scalar.value >= 32 else { return nil }
        return Character(scalar)
    }
}
