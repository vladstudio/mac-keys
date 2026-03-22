import AppKit

enum EventEmitter {
    /// Magic value to tag events we emit, so we can skip them in the tap callback.
    static let marker: Int64 = 0x4B455953 // "KEYS"

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

    /// Paste text via clipboard Cmd+V, saving and restoring the original clipboard.
    static func pasteText(_ text: String) {
        let pasteboard = NSPasteboard.general
        restoreWorkItem?.cancel()
        if savedClipboard == nil { savedClipboard = savePasteboard(pasteboard) }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        emitKeyPress(keyCode: 0x09, flags: .maskCommand)
        let workItem = DispatchWorkItem {
            if let saved = savedClipboard {
                restorePasteboard(pasteboard, from: saved)
                savedClipboard = nil
            }
        }
        restoreWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
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
