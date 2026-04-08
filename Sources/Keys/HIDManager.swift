import Foundation

enum HIDManager {
    private static let dirtyKey = "HIDManagerDirty"

    /// Call on launch: if the previous run crashed with active mappings, clean them up.
    static func cleanUpIfNeeded() {
        if UserDefaults.standard.bool(forKey: dirtyKey) {
            reset()
        }
    }

    static func apply(mappings: [(src: UInt16, dst: UInt16)]) {
        let entries = mappings.compactMap { mapping -> String? in
            guard let srcHID = KeyCodes.keyCodeToHIDUsage[mapping.src],
                  let dstHID = KeyCodes.keyCodeToHIDUsage[mapping.dst] else { return nil }
            let src = 0x700000000 | UInt64(srcHID)
            let dst = 0x700000000 | UInt64(dstHID)
            return "{\"HIDKeyboardModifierMappingSrc\":\(src),\"HIDKeyboardModifierMappingDst\":\(dst)}"
        }
        UserDefaults.standard.set(true, forKey: dirtyKey)
        run(json: "{\"UserKeyMapping\":[\(entries.joined(separator: ","))]}")
    }

    static func reset() {
        run(json: "{\"UserKeyMapping\":[]}")
        UserDefaults.standard.removeObject(forKey: dirtyKey)
    }

    private static func run(json: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--set", json]
        do { try process.run() } catch { NSLog("Keys: hidutil failed: %@", "\(error)") }
    }
}
