import AppKit

class KeystrokeOverlay: NSPanel {
    enum Position: Int { case left, right }

    var isOverlayEnabled = false {
        didSet {
            if !isOverlayEnabled {
                heldModifiers.removeAll()
                removeAll(where: { _ in true })
                orderOut(nil)
            }
        }
    }
    var position: Position = .right

    private var trackedKeys: [TrackedKey] = []
    private var heldModifiers = Set<UInt16>()
    private static let gap: CGFloat = 4
    private static let slideDistance: CGFloat = 32
    private static let fadeDelay: TimeInterval = 0.8
    private static let fadeDuration: TimeInterval = 0.3
    private static let slideDuration: TimeInterval = 0.2
    private static let fontSize: CGFloat = 48
    private static let pillPadding: CGFloat = 20

    /// Slide direction: pills enter from this side and exit toward it.
    private var slideSign: CGFloat { position == .left ? -1 : 1 }

    private struct TrackedKey {
        let id = UUID()
        var baseLabel: String
        var repeatCount: Int = 1
        let pill: NSView
        let textField: NSTextField
        var fadeTimer: DispatchWorkItem?
        var isModifier: Bool
        var keyCode: UInt16

        var displayString: NSAttributedString {
            let font = NSFont.systemFont(ofSize: KeystrokeOverlay.fontSize, weight: .medium)
            let base = NSMutableAttributedString(string: baseLabel, attributes: [
                .foregroundColor: NSColor.white, .font: font,
            ])
            if repeatCount > 1 {
                base.append(NSAttributedString(string: " \u{00d7}\(repeatCount)", attributes: [
                    .foregroundColor: NSColor.white.withAlphaComponent(0.5), .font: font,
                ]))
            }
            return base
        }
    }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }

    // MARK: - Event handling

    func handleEvent(keyCode: UInt16, type: CGEventType, flags: CGEventFlags, characters: String?) {
        guard isOverlayEnabled else { return }

        switch type {
        case .flagsChanged:
            handleModifier(keyCode: keyCode, flags: flags)
        case .keyDown:
            handleKeyDown(keyCode: keyCode, flags: flags, characters: characters)
        case .keyUp:
            handleKeyUp(keyCode: keyCode)
        default:
            break
        }
    }

    private func handleModifier(keyCode: UInt16, flags: CGEventFlags) {
        guard KeyCodes.modifierKeyCodes.contains(keyCode) else { return }
        let isPress = KeyCodes.isModifierPress(keyCode: keyCode, flags: flags)

        if isPress {
            heldModifiers.insert(keyCode)
            guard let symbol = KeyCodes.keyCodeToDisplayLabel[keyCode] else { return }
            addPill(label: symbol, keyCode: keyCode, isModifier: true)
        } else {
            heldModifiers.remove(keyCode)
            for (idx, key) in trackedKeys.enumerated() where key.keyCode == keyCode && key.isModifier && key.fadeTimer == nil {
                scheduleFade(at: idx)
            }
        }
    }

    private func handleKeyDown(keyCode: UInt16, flags: CGEventFlags, characters: String?) {
        let isShortcut = flags.contains(.maskCommand) || flags.contains(.maskControl)

        let label: String
        if !isShortcut, let ch = characters, isPrintable(ch) {
            label = ch
        } else {
            var parts: [String] = []
            for (keyCodes, symbol) in KeyCodes.modifierDisplayOrder {
                if !heldModifiers.isDisjoint(with: keyCodes) {
                    parts.append(symbol)
                }
            }
            if let name = KeyCodes.keyCodeToDisplayLabel[keyCode] {
                parts.append(name)
            }
            guard !parts.isEmpty else { return }
            label = parts.joined()
        }

        // Reuse existing modifier pill if present (e.g. ⌘ → ⌘c)
        if let idx = trackedKeys.firstIndex(where: { $0.isModifier }) {
            let keep = trackedKeys[idx].id
            removeAll(where: { $0.isModifier && $0.id != keep })
            if let idx = trackedKeys.firstIndex(where: { $0.id == keep }) {
                updatePillText(at: idx, label: label, keyCode: keyCode, isModifier: false)
            }
            return
        }

        // Repeat: if last pill has same label, increment count (cancel any pending fade)
        if let last = trackedKeys.last, !last.isModifier, last.baseLabel == label {
            let idx = trackedKeys.count - 1
            trackedKeys[idx].fadeTimer?.cancel()
            trackedKeys[idx].fadeTimer = nil
            trackedKeys[idx].repeatCount += 1
            trackedKeys[idx].pill.alphaValue = 1
            updatePillDisplay(at: idx)
            return
        }

        addPill(label: label, keyCode: keyCode, isModifier: false)
    }

    private func isPrintable(_ str: String) -> Bool {
        guard !str.isEmpty else { return false }
        return str.unicodeScalars.allSatisfy {
            $0.value >= 0x20 && $0.value != 0x7F && !($0.value >= 0xF700 && $0.value <= 0xF8FF)
        }
    }

    private func handleKeyUp(keyCode: UInt16) {
        for (idx, key) in trackedKeys.enumerated() where key.keyCode == keyCode && !key.isModifier && key.fadeTimer == nil {
            scheduleFade(at: idx)
        }
    }

    // MARK: - Pill management

    private func addPill(label: String, keyCode: UInt16, isModifier: Bool) {
        let (pill, tf) = makePill(label)
        contentView!.addSubview(pill)

        trackedKeys.append(TrackedKey(
            baseLabel: label, pill: pill, textField: tf, fadeTimer: nil,
            isModifier: isModifier, keyCode: keyCode
        ))

        // Position at final spot offset by slideDistance, then animate in
        layoutPills(animated: true)
        let offset = Self.slideDistance * slideSign
        pill.alphaValue = 0
        pill.frame.origin.x += offset
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.slideDuration
            ctx.allowsImplicitAnimation = true
            pill.animator().alphaValue = 1
            pill.animator().frame.origin.x -= offset
        }
    }

    private func updatePillText(at index: Int, label: String, keyCode: UInt16, isModifier: Bool) {
        trackedKeys[index].baseLabel = label
        trackedKeys[index].repeatCount = 1
        trackedKeys[index].keyCode = keyCode
        trackedKeys[index].isModifier = isModifier
        trackedKeys[index].fadeTimer?.cancel()
        trackedKeys[index].fadeTimer = nil
        updatePillDisplay(at: index)
    }

    /// Refresh the pill's text and size from the current TrackedKey state.
    private func updatePillDisplay(at index: Int) {
        let tf = trackedKeys[index].textField
        let pill = trackedKeys[index].pill
        tf.attributedStringValue = trackedKeys[index].displayString
        tf.sizeToFit()
        let padding = Self.pillPadding
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.slideDuration
            ctx.allowsImplicitAnimation = true
            pill.animator().frame.size = NSSize(width: tf.frame.width + padding * 2, height: tf.frame.height + padding * 2)
        }
        layoutPills(animated: true)
    }

    private func scheduleFade(at index: Int) {
        guard index < trackedKeys.count else { return }
        trackedKeys[index].fadeTimer?.cancel()

        let id = trackedKeys[index].id
        let work = DispatchWorkItem { [weak self] in
            guard let self, let idx = self.trackedKeys.firstIndex(where: { $0.id == id }) else { return }
            let pill = self.trackedKeys[idx].pill
            let offset = Self.slideDistance * self.slideSign

            // Remove from tracking and relayout immediately so remaining pills start moving
            self.trackedKeys.remove(at: idx)
            self.layoutPills(animated: true)

            // Fade out the detached pill (still a subview, just not tracked)
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = Self.fadeDuration
                ctx.allowsImplicitAnimation = true
                pill.animator().alphaValue = 0
                pill.animator().frame.origin.x -= offset
            }, completionHandler: {
                pill.removeFromSuperview()
            })
        }
        trackedKeys[index].fadeTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeDelay, execute: work)
    }

    private func removeAll(where predicate: (TrackedKey) -> Bool) {
        for key in trackedKeys where predicate(key) {
            key.pill.removeFromSuperview()
            key.fadeTimer?.cancel()
        }
        trackedKeys.removeAll(where: predicate)
    }

    // MARK: - Layout

    private func layoutPills(animated: Bool) {
        guard !trackedKeys.isEmpty else {
            orderOut(nil)
            return
        }

        let pad = Self.slideDistance

        var x: CGFloat = pad
        var targets: [(NSView, CGPoint)] = []
        for key in trackedKeys {
            targets.append((key.pill, CGPoint(x: x, y: 0)))
            x += key.pill.frame.width + Self.gap
        }
        let contentWidth = x - Self.gap - pad
        let totalWidth = contentWidth + pad * 2
        let totalHeight = trackedKeys[0].pill.frame.height

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let vis = screen.visibleFrame
        let panelX: CGFloat
        switch position {
        case .left:  panelX = vis.minX + 32 - pad
        case .right: panelX = vis.maxX - contentWidth - 32 - pad
        }
        let newFrame = NSRect(x: panelX, y: vis.minY + 32, width: totalWidth, height: totalHeight)

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Self.slideDuration
                ctx.allowsImplicitAnimation = true
                self.animator().setFrame(newFrame, display: true)
                for (pill, origin) in targets {
                    pill.animator().frame.origin = origin
                }
            }
        } else {
            setFrame(newFrame, display: true)
            for (pill, origin) in targets {
                pill.frame.origin = origin
            }
        }

        if !isVisible { orderFrontRegardless() }
    }

    func relayout() { layoutPills(animated: false) }

    // MARK: - Pill view factory

    private func makePill(_ text: String) -> (NSView, NSTextField) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: Self.fontSize, weight: .medium)
        label.textColor = .white
        label.sizeToFit()

        let padding = Self.pillPadding
        let pill = NSView(frame: NSRect(
            x: 0, y: 0,
            width: label.frame.width + padding * 2,
            height: label.frame.height + padding * 2
        ))
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor(white: 0.067, alpha: 0.8).cgColor
        pill.layer?.cornerRadius = 12

        label.frame.origin = CGPoint(x: padding, y: padding)
        pill.addSubview(label)
        return (pill, label)
    }
}
