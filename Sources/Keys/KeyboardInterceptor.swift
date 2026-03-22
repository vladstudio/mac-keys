import CoreGraphics
import Foundation

class KeyboardInterceptor {
    let remapEngine = RemapEngine()
    var isEnabled = true
    var snippetPicker: SnippetPicker?
    private(set) var snippets: [String] = []

    private var eventTap: CFMachPort?

    func start() -> Bool {
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

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
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }

    func update(config: Config) {
        remapEngine.update(rules: config.remaps)
        snippets = config.snippets
    }

    // MARK: - Event handling

    fileprivate func handleEvent(
        proxy: CGEventTapProxy, type: CGEventType, event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return pass
        }

        if event.getIntegerValueField(.eventSourceUserData) == EventEmitter.marker {
            return pass
        }

        guard isEnabled else { return pass }

        switch remapEngine.handleEvent(event: event, type: type) {
        case .consumed:
            return nil
        case .showPicker:
            DispatchQueue.main.async { self.snippetPicker?.show(snippets: self.snippets) }
            return nil
        case .passThrough:
            break
        }

        return pass
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
