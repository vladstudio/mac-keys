# Keys

macOS menu bar app for key remapping and snippet pasting. Swift/AppKit, no external dependencies.

## Build & Run

```
./build.sh        # release build → Keys.app
swift build        # debug build
open Keys.app      # run (needs Accessibility permission)
```

## Architecture

- `main.swift` — NSApplication entry point (.accessory policy, no dock icon)
- `AppDelegate.swift` — menu bar UI, wires config manager to keyboard interceptor
- `KeyboardInterceptor.swift` — CGEventTap callback, routes events through remap engine
- `RemapEngine.swift` — key remapping: single keys, modifier combos, modifier double-tap sequences
- `SnippetPicker.swift` — floating Raycast-style panel: filter snippets, paste via clipboard
- `EventEmitter.swift` — emits synthetic CGEvents (tagged to avoid re-interception) and clipboard paste
- `ConfigManager.swift` — loads/watches `~/.keys.csv`, delegates updates/errors
- `ConfigParser.swift` — config parser: `[section]` headers, CSV for remaps, RFC 4180 quoting for multi-line snippets
- `Config.swift` — data models: KeyCombo, RemapRule, Config
- `KeyCodes.swift` — key name ↔ CGKeyCode mappings, combo/sequence parsing

## Key design decisions

- No external dependencies — config parser is hand-written CSV with RFC 4180 quoting
- Events we emit are tagged via `.eventSourceUserData` field (magic value `0x4B455953`) so the tap callback skips them
- Modifier double-tap detection: track tap timestamps, fire on second press within 400ms
- Sequence rules take priority over single remap rules for the same key
- Snippet picker pastes via clipboard (Cmd+V) — saves and restores original clipboard
- Remap output `snippets` (keyCode 0xFFFF) is a virtual key that opens the snippet picker
- Config file watched via DispatchSource; falls back to 2-second polling if file is deleted

## Config format

`~/.keys.csv`. Two section types: `[remap]` and `[snippet]`. Remap rules are two comma-separated fields. Snippet lines are plain text (one per line), or RFC 4180 quoted for multi-line. See `example.keys.csv`.
