import AppKit
import CoreGraphics
import Foundation
import IOKit.hid

class KeyboardInterceptor {
    private let remapEngine = RemapEngine()
    var isEnabled = true
    var snippetPicker: SnippetPicker?
    private(set) var snippets: [Snippet] = []

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var disableCount = 0
    private var firstDisableTime: Date?
    private var internalKeyboardTypes = Set<Int64>()
    var onPermissionLost: (() -> Void)?

    func start() -> Bool {
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << 14) // NX_SYSDEFINED (media keys)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: tapCallback,
            userInfo: userInfo
        ) else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        tearDown()
    }

    /// Fully tear down the event tap so it no longer sits in the run loop.
    /// A broken active tap that can't process events will block all input.
    private func tearDown() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        eventTap = nil
    }

    var onWarning: ((String) -> Void)?

    func update(config: Config) {
        internalKeyboardTypes = Self.detectInternalKeyboardTypes()

        var hidMappings: [(src: UInt16, dst: UInt16)] = []
        var tapRules: [RemapRule] = []
        var capsLockKeyboards = Set<KeyboardTarget>()

        for rule in config.remaps {
            let isCapsLock = {
                if case .single(let combo) = rule.input {
                    return combo.keyCode == 0x39 && combo.modifiers.isEmpty
                }
                return false
            }()

            if isCapsLock && capsLockKeyboards.contains(rule.keyboard) {
                onWarning?("Multiple caps_lock rules for same keyboard; using first, ignoring rest")
                continue
            }
            if isCapsLock { capsLockKeyboards.insert(rule.keyboard) }

            // Caps lock → real key can use hidutil, but only for "all keyboards"
            // (hidutil is system-wide; per-keyboard rules must go through CGEventTap)
            if isCapsLock,
               case .key(let combo) = rule.output,
               combo.modifiers.isEmpty,
               rule.keyboard == .all
            {
                hidMappings.append((0x39, combo.keyCode))
            } else {
                tapRules.append(rule)
            }
        }

        remapEngine.update(rules: tapRules)
        snippets = config.snippets
        HIDManager.apply(mappings: hidMappings)
    }

    // MARK: - Event handling

    fileprivate func handleEvent(
        proxy: CGEventTapProxy, type: CGEventType, event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // AXIsProcessTrusted() can return stale cached values, so also
            // detect permission loss by rapid consecutive disables (3+ in 2s).
            let now = Date()
            if let first = firstDisableTime, now.timeIntervalSince(first) < 2 {
                disableCount += 1
            } else {
                firstDisableTime = now
                disableCount = 1
            }

            if !AXIsProcessTrusted() || disableCount >= 3 {
                disableCount = 0
                firstDisableTime = nil
                tearDown()
                DispatchQueue.main.async { self.onPermissionLost?() }
            } else if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return pass
        }

        let kbType = event.getIntegerValueField(.keyboardEventKeyboardType)
        let isInternal = !internalKeyboardTypes.isEmpty && internalKeyboardTypes.contains(kbType)

        // Media keys (NX_SYSDEFINED)
        if type.rawValue == 14 {
            guard isEnabled,
                  let nsEvent = NSEvent(cgEvent: event),
                  nsEvent.subtype.rawValue == 8 // NX_SUBTYPE_AUX_CONTROL_BUTTONS
            else { return pass }
            let data1 = nsEvent.data1
            let keyType = Int32((data1 >> 16) & 0xFFFF)
            let isDown = ((data1 >> 8) & 0xFF) == 0x0A
            return dispatch(remapEngine.handleMediaKey(keyType: keyType, isDown: isDown, isInternal: isInternal), pass: pass)
        }

        if event.getIntegerValueField(.eventSourceUserData) == EventEmitter.marker {
            return pass
        }

        guard isEnabled else { return pass }

        return dispatch(remapEngine.handleEvent(event: event, type: type, isInternal: isInternal), pass: pass)
    }

    /// Query IOKit for keyboard types belonging to built-in keyboards.
    private static func detectInternalKeyboardTypes() -> Set<Int64> {
        var result = Set<Int64>()
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        defer { _ = IOHIDManagerClose(manager, 0) }

        IOHIDManagerSetDeviceMatching(manager, [
            "DeviceUsagePage": 1, // Generic Desktop
            "DeviceUsage": 6,    // Keyboard
        ] as CFDictionary)
        _ = IOHIDManagerOpen(manager, 0)

        guard let devices = IOHIDManagerCopyDevices(manager) else { return result }
        for case let device as IOHIDDevice in (devices as NSSet) {
            let builtIn = IOHIDDeviceGetProperty(device, "Built-In" as CFString)
            guard (builtIn as? NSNumber)?.boolValue == true else { continue }
            guard let type = IOHIDDeviceGetProperty(device, "KeyboardType" as CFString) as? NSNumber else { continue }
            result.insert(type.int64Value)
        }
        return result
    }

    private func dispatch(_ result: RemapEngine.Result, pass: Unmanaged<CGEvent>) -> Unmanaged<CGEvent>? {
        switch result {
        case .consumed:
            return nil
        case .showPicker:
            DispatchQueue.main.async { self.snippetPicker?.show(snippets: self.snippets) }
            return nil
        case .toggleInput:
            DispatchQueue.main.async { InputSourceManager.toggle() }
            return nil
        case .openApp(let name):
            DispatchQueue.main.async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-a", name]
                try? process.run()
            }
            return nil
        case .bash(let cmd):
            DispatchQueue.main.async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", cmd]
                try? process.run()
            }
            return nil
        case .paste(let text):
            DispatchQueue.main.async { EventEmitter.pasteText(text) }
            return nil
        case .passThrough:
            return pass
        }
    }
}

private func tapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
    let interceptor = Unmanaged<KeyboardInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
    return interceptor.handleEvent(proxy: proxy, type: type, event: event)
}
