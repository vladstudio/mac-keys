import AppKit
import CoreGraphics

enum EventEmitter {
    /// Magic value to tag events we emit, so we can skip them in the tap callback.
    static let marker: Int64 = 0x4B455953 // "KEYS"

    /// Delay between synthetic events in microseconds.
    private static let interEventDelay: useconds_t = 11_000 // 11 ms

    private static var savedClipboard: [[NSPasteboard.PasteboardType: Data]]?
    private static var restoreWorkItem: DispatchWorkItem?

    static func emit(keyCode: UInt16, flags: CGEventFlags = [], keyDown: Bool) {
        guard let event = CGEvent(keyboardEventSource: nil,
                                  virtualKey: keyCode, keyDown: keyDown) else { return }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cghidEventTap)
    }

    static func emitKeyPress(keyCode: UInt16, flags: CGEventFlags = []) {
        emit(keyCode: keyCode, flags: flags, keyDown: true)
        emit(keyCode: keyCode, flags: flags, keyDown: false)
    }

    /// Emit a snippet expansion: delete trigger characters with delays, then paste replacement.
    static func emitSnippet(deleteCount: Int, replacement: String) {
        DispatchQueue.main.async {
            // Delete trigger characters with delays between each
            for _ in 0..<deleteCount {
                emit(keyCode: 0x33, keyDown: true)
                usleep(interEventDelay)
                emit(keyCode: 0x33, keyDown: false)
                usleep(interEventDelay)
            }

            // Paste replacement via clipboard
            let pasteboard = NSPasteboard.general

            restoreWorkItem?.cancel()
            if savedClipboard == nil {
                savedClipboard = savePasteboard(pasteboard)
            }

            pasteboard.clearContents()
            pasteboard.setString(replacement, forType: .string)

            // Cmd+V
            emit(keyCode: 0x09, flags: .maskCommand, keyDown: true)
            usleep(interEventDelay)
            emit(keyCode: 0x09, flags: .maskCommand, keyDown: false)

            // Restore clipboard after paste is processed
            let workItem = DispatchWorkItem {
                if let saved = savedClipboard {
                    restorePasteboard(pasteboard, from: saved)
                    savedClipboard = nil
                }
            }
            restoreWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
        }
    }

    // MARK: - Private

    private static func savePasteboard(_ pb: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        pb.pasteboardItems?.map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            return dict
        } ?? []
    }

    private static func restorePasteboard(_ pb: NSPasteboard, from items: [[NSPasteboard.PasteboardType: Data]]) {
        pb.clearContents()
        let restored = items.map { itemDict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in itemDict {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restored.isEmpty {
            pb.writeObjects(restored)
        }
    }
}
