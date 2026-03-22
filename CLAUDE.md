# Keys

macOS menu bar app for key remapping and text expansion. Swift/AppKit, no external dependencies.

## Build & Run

```
./build.sh        # release build → Keys.app
swift build        # debug build
open Keys.app      # run (needs Accessibility permission)
```

## Architecture

- `main.swift` — NSApplication entry point (.accessory policy, no dock icon)
- `AppDelegate.swift` — menu bar UI, wires config manager to keyboard interceptor
- `KeyboardInterceptor.swift` — CGEventTap callback, routes events through remap → snippet pipeline
- `RemapEngine.swift` — key remapping: single keys, modifier combos, modifier double-tap sequences
- `SnippetEngine.swift` — text expansion: rolling buffer, trigger match, backspace+emit replacement
- `EventEmitter.swift` — emits synthetic CGEvents tagged with a marker to avoid re-interception
- `ConfigManager.swift` — loads/watches `~/.keys`, delegates updates/errors
- `ConfigParser.swift` — custom config parser: `[[section]]` headers, `value value` lines, quoted strings, `"""`multiline
- `Config.swift` — data models: KeyCombo, RemapRule, SnippetRule, Config
- `KeyCodes.swift` — key name ↔ CGKeyCode mappings, combo/sequence parsing

## Key design decisions

- No external dependencies — config parser is hand-written for our custom format
- Events we emit are tagged via `.eventSourceUserData` field (magic value `0x4B455953`) so the tap callback skips them
- Modifier double-tap detection: track tap timestamps, fire on second press within 400ms
- Sequence rules take priority over single remap rules for the same key
- Snippet buffer is cleared on non-printable keyDown and 3-second idle timer
- Config file watched via DispatchSource; falls back to 2-second polling if file is deleted

## Config format

Custom format at `~/.keys`. Two section types: `[[remap]]` and `[[snippet]]`. One rule per line, two space-separated values. Quotes optional unless value has spaces. `"""` for multiline. See `example.keys`.
