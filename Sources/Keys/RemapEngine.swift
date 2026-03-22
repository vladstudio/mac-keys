import CoreGraphics
import Foundation

class RemapEngine {
    private static let doubleTapWindow: TimeInterval = 0.4

    private var singleRules: [RemapRule] = []
    private var sequenceRules: [RemapRule] = []
    private var activeKeyRemaps: [UInt16: KeyCombo] = [:]
    private var suppressingModifier: UInt16?
    private var pendingModifierDown: (keyCode: UInt16, time: Date)?
    private var lastModifierTap: (keyCode: UInt16, time: Date)?

    enum Result {
        case passThrough
        case consumed
        case showPicker
        case toggleInput
        case openApp(String)
        case bash(String)
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

    private static func emitOrAction(_ output: RemapOutput) -> Result {
        switch output {
        case .key(let combo):
            EventEmitter.emitKeyPress(keyCode: combo.keyCode, flags: combo.modifiers)
            return .consumed
        case .showPicker: return .showPicker
        case .toggleInput: return .toggleInput
        case .openApp(let name): return .openApp(name)
        case .bash(let cmd): return .bash(cmd)
        }
    }

    // MARK: - Private

    private func handleKeyDown(keyCode: UInt16, flags: CGEventFlags) -> Result {
        for rule in singleRules {
            guard case .single(let combo) = rule.input else { continue }
            guard !KeyCodes.modifierKeyCodes.contains(combo.keyCode) else { continue }
            let relevant = flags.intersection(KeyCombo.modifierMask)
            if combo.keyCode == keyCode && combo.modifiers == relevant {
                guard case .key(let out) = rule.output else {
                    return Self.emitOrAction(rule.output)
                }
                activeKeyRemaps[keyCode] = out
                EventEmitter.emit(keyCode: out.keyCode, flags: out.modifiers, keyDown: true)
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

        let isPress = KeyCodes.isModifierPress(keyCode: keyCode, flags: flags)

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

        if let lastTap = lastModifierTap, lastTap.keyCode == keyCode,
           Date().timeIntervalSince(lastTap.time) < Self.doubleTapWindow
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
                    return Self.emitOrAction(rule.output)
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
                if combo.modifiers.isEmpty {
                    suppressingModifier = keyCode
                    return Self.emitOrAction(rule.output)
                }
            } else {
                let relevant = flags.intersection(KeyCombo.modifierMask)
                var expected = combo.modifiers
                if let flag = KeyCodes.keyCodeToModifierFlag[keyCode] {
                    expected.insert(flag)
                }
                if relevant == expected {
                    suppressingModifier = keyCode
                    return Self.emitOrAction(rule.output)
                }
            }
        }

        return .passThrough
    }
}
