import CoreGraphics
import Foundation

class RemapEngine {
    private var singleRules: [RemapRule] = []
    private var sequenceRules: [RemapRule] = []

    // Active key-down remaps so we can match the corresponding key-up
    private var activeKeyRemaps: [UInt16: KeyCombo] = [:]
    // Modifier whose release should be suppressed after a remapped press
    private var suppressingModifier: UInt16?

    // Sequence (double-tap) detection state
    private var pendingModifierDown: (keyCode: UInt16, time: Date)?
    private var lastModifierTap: (keyCode: UInt16, time: Date)?

    enum Result {
        case passThrough
        case consumed
    }

    func update(rules: [RemapRule]) {
        singleRules = rules.filter { if case .single = $0.input { return true }; return false }
        sequenceRules = rules.filter { if case .sequence = $0.input { return true }; return false }
        reset()
    }

    func reset() {
        activeKeyRemaps.removeAll()
        suppressingModifier = nil
        pendingModifierDown = nil
        lastModifierTap = nil
    }

    func handleEvent(event: CGEvent, type: CGEventType) -> Result {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        switch type {
        case .keyDown:
            pendingModifierDown = nil
            lastModifierTap = nil
            return handleKeyDown(keyCode: keyCode, flags: flags)
        case .keyUp:
            return handleKeyUp(keyCode: keyCode)
        case .flagsChanged:
            return handleFlagsChanged(keyCode: keyCode, flags: flags)
        default:
            return .passThrough
        }
    }

    // MARK: - Private

    private func handleKeyDown(keyCode: UInt16, flags: CGEventFlags) -> Result {
        for rule in singleRules {
            guard case .single(let combo) = rule.input else { continue }
            guard !KeyCodes.modifierKeyCodes.contains(combo.keyCode) else { continue }
            let relevant = flags.intersection(KeyCombo.modifierMask)
            if combo.keyCode == keyCode && combo.modifiers == relevant {
                activeKeyRemaps[keyCode] = rule.output
                EventEmitter.emit(keyCode: rule.output.keyCode, flags: rule.output.modifiers, keyDown: true)
                return .consumed
            }
        }
        return .passThrough
    }

    private func handleKeyUp(keyCode: UInt16) -> Result {
        if let output = activeKeyRemaps.removeValue(forKey: keyCode) {
            EventEmitter.emit(keyCode: output.keyCode, flags: output.modifiers, keyDown: false)
            return .consumed
        }
        return .passThrough
    }

    private func handleFlagsChanged(keyCode: UInt16, flags: CGEventFlags) -> Result {
        guard KeyCodes.modifierKeyCodes.contains(keyCode) else { return .passThrough }

        let isPress: Bool
        if keyCode == 0x39 { // caps_lock — toggle, treat every event as press
            isPress = true
        } else if let flag = KeyCodes.keyCodeToModifierFlag[keyCode] {
            isPress = flags.contains(flag)
        } else {
            return .passThrough
        }

        // Suppress release after a remapped modifier press
        if !isPress {
            if suppressingModifier == keyCode {
                suppressingModifier = nil
                return .consumed
            }
            // Clean modifier tap completed
            if let pending = pendingModifierDown, pending.keyCode == keyCode {
                lastModifierTap = (keyCode, pending.time)
                pendingModifierDown = nil
            }
            return .passThrough
        }

        // --- isPress ---

        // Invalidate pending tap if a *different* modifier is pressed
        if let pending = pendingModifierDown, pending.keyCode != keyCode {
            pendingModifierDown = nil
            lastModifierTap = nil
        }

        // Check double-tap sequence completion
        if let lastTap = lastModifierTap, lastTap.keyCode == keyCode,
           Date().timeIntervalSince(lastTap.time) < 0.4
        {
            for rule in sequenceRules {
                guard case .sequence(let combos) = rule.input else { continue }
                if combos.count == 2
                    && combos[0].keyCode == keyCode
                    && combos[1].keyCode == keyCode
                {
                    lastModifierTap = nil
                    pendingModifierDown = nil
                    suppressingModifier = keyCode
                    EventEmitter.emitKeyPress(keyCode: rule.output.keyCode, flags: rule.output.modifiers)
                    return .consumed
                }
            }
        }

        // If this key starts a sequence, record it and let through (don't check single rules)
        let startsSequence = sequenceRules.contains { rule in
            guard case .sequence(let combos) = rule.input else { return false }
            return combos.first?.keyCode == keyCode
        }
        if startsSequence {
            pendingModifierDown = (keyCode, Date())
            return .passThrough
        }

        // Check single modifier remap rules
        for rule in singleRules {
            guard case .single(let combo) = rule.input else { continue }
            guard KeyCodes.modifierKeyCodes.contains(combo.keyCode) else { continue }
            guard combo.keyCode == keyCode else { continue }

            if keyCode == 0x39 {
                // Caps lock: match keyCode only, ignore toggle flag state
                if combo.modifiers.isEmpty {
                    suppressingModifier = keyCode
                    EventEmitter.emitKeyPress(keyCode: rule.output.keyCode, flags: rule.output.modifiers)
                    return .consumed
                }
            } else {
                // Regular modifier: the pressed modifier's own flag is in `flags`,
                // so add it to the expected set for comparison.
                let relevant = flags.intersection(KeyCombo.modifierMask)
                var expected = combo.modifiers
                if let flag = KeyCodes.keyCodeToModifierFlag[keyCode] {
                    expected.insert(flag)
                }
                if relevant == expected {
                    suppressingModifier = keyCode
                    EventEmitter.emitKeyPress(keyCode: rule.output.keyCode, flags: rule.output.modifiers)
                    return .consumed
                }
            }
        }

        return .passThrough
    }
}
