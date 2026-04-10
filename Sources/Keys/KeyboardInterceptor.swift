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
    private var internalKeyboardTypes = Set<Int64>()
    private var mediaKeyMonitor: IOHIDManager?
    fileprivate var lastMediaKeyIsInternal: Bool?
    var keystrokeOverlay: KeystrokeOverlay?
    var onPermissionLost: (() -> Void)?

    func start() -> Bool {
        startMediaKeyMonitoring()
        guard eventTap == nil else { return true }
        remapEngine.reset()
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
            let isCapsLock: Bool
            if case .single(let combo) = rule.input {
                isCapsLock = combo.keyCode == 0x39 && combo.modifiers.isEmpty
            } else {
                isCapsLock = false
            }

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

    // MARK: - Media key device tracking

    /// Monitor consumer control HID devices to determine which keyboard generates media key events.
    /// NX_SYSDEFINED events don't carry keyboard type, so we track it via IOHIDManager callbacks
    /// which fire before the CGEventTap sees the corresponding NX_SYSDEFINED event.
    private func startMediaKeyMonitoring() {
        guard mediaKeyMonitor == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, [
            "DeviceUsagePage": 0x0C, // Consumer
            "DeviceUsage": 1,        // Consumer Control
        ] as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, mediaKeyHIDCallback, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        _ = IOHIDManagerOpen(manager, 0)
        mediaKeyMonitor = manager
    }

    // MARK: - Event handling

    fileprivate func handleEvent(
        proxy: CGEventTapProxy, type: CGEventType, event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Tear down immediately — never re-enable a potentially revoked tap.
            // Re-enabling a tap without permission freezes all input system-wide.
            // The permission polling timer will restart the tap if permission is OK.
            tearDown()
            DispatchQueue.main.async { self.onPermissionLost?() }
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
            // NX_SYSDEFINED events don't carry keyboard type — use IOHIDManager-tracked device info
            return dispatch(remapEngine.handleMediaKey(keyType: keyType, isDown: isDown, isInternal: lastMediaKeyIsInternal), pass: pass)
        }

        if event.getIntegerValueField(.eventSourceUserData) == EventEmitter.marker {
            return pass
        }

        if let overlay = keystrokeOverlay, overlay.isOverlayEnabled {
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let characters = (type == .keyDown) ? NSEvent(cgEvent: event)?.characters : nil
            let flags = event.flags
            DispatchQueue.main.async {
                overlay.handleEvent(keyCode: keyCode, type: type, flags: flags, characters: characters)
            }
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
        case .action(let output):
            DispatchQueue.main.async {
                switch output {
                case .showPicker:
                    self.snippetPicker?.show(snippets: self.snippets)
                case .toggleInput:
                    InputSourceManager.toggle()
                case .openApp(let name):
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    process.arguments = ["-a", name]
                    do { try process.run() } catch { self.onWarning?("open(\(name)): \(error.localizedDescription)") }
                case .bash(let cmd):
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/bash")
                    process.arguments = ["-c", cmd]
                    do { try process.run() } catch { self.onWarning?("bash: \(error.localizedDescription)") }
                case .paste(let text):
                    EventEmitter.pasteText(text)
                case .key, .ignore:
                    break
                }
            }
            return nil
        case .passThrough:
            return pass
        }
    }
}

private func mediaKeyHIDCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    value: IOHIDValue
) {
    guard let context, let sender else { return }
    let interceptor = Unmanaged<KeyboardInterceptor>.fromOpaque(context).takeUnretainedValue()
    let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
    let builtIn = IOHIDDeviceGetProperty(device, "Built-In" as CFString)
    interceptor.lastMediaKeyIsInternal = (builtIn as? NSNumber)?.boolValue ?? false
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
