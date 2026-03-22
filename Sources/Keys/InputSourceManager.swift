import Carbon

enum InputSourceManager {
    static func toggle() {
        let filter = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource!,
            kTISPropertyInputSourceIsSelectCapable: true,
            kTISPropertyInputSourceIsEnabled: true,
        ] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
              list.count >= 2,
              let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        else { return }

        let sorted = list.sorted { (sourceID($0) ?? "") < (sourceID($1) ?? "") }
        let currentID = sourceID(current)
        let index = sorted.firstIndex { sourceID($0) == currentID } ?? 0
        TISSelectInputSource(sorted[(index + 1) % sorted.count])
    }

    private static func sourceID(_ source: TISInputSource) -> String? {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }
}
