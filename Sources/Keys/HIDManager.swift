import Foundation

enum HIDManager {
    static func apply(mappings: [(src: UInt16, dst: UInt16)]) {
        let entries = mappings.compactMap { mapping -> String? in
            guard let srcHID = KeyCodes.keyCodeToHIDUsage[mapping.src],
                  let dstHID = KeyCodes.keyCodeToHIDUsage[mapping.dst] else { return nil }
            let src = 0x700000000 | UInt64(srcHID)
            let dst = 0x700000000 | UInt64(dstHID)
            return "{\"HIDKeyboardModifierMappingSrc\":\(src),\"HIDKeyboardModifierMappingDst\":\(dst)}"
        }
        run(json: "{\"UserKeyMapping\":[\(entries.joined(separator: ","))]}")
    }

    static func reset() {
        run(json: "{\"UserKeyMapping\":[]}")
    }

    private static func run(json: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--set", json]
        try? process.run()
        process.waitUntilExit()
    }
}
