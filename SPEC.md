# Keys — Product Specification

## Overview

**Keys** is a macOS menu bar application that intercepts keyboard input globally and performs two functions:

1. **Key remapping** — replaces one keystroke (or key combination, or keystroke sequence) with another
2. **Text expansion** — replaces a typed trigger string with a longer replacement string

Configuration lives in a plain text file. No GUI configuration editor.

## How It Works

Keys installs a global event tap via the macOS Accessibility API (`CGEventTap`) to intercept keyboard events before they reach applications. It processes every keystroke against its loaded rules and either passes it through, modifies it, or suppresses/replaces it.

### Key Remapping

- A remap rule maps an **input** to an **output**
- Inputs can be:
  - A single key: `caps_lock`
  - A modifier + key combination: `option+shift+a`
  - A keystroke sequence: `option, option` (e.g., option pressed twice within the time window)
- Outputs can be:
  - A single key: `F20`
  - A modifier + key combination: `control+shift+f20`
- When the input is detected, Keys suppresses the original keystrokes and emits the output keystrokes
- Keystroke sequences use a hardcoded time window of **400ms** between consecutive keys

### Text Expansion

- A snippet rule maps a **trigger string** to a **replacement string**
- Keys maintains a rolling buffer of recently typed characters
- When the buffer ends with a trigger string, Keys:
  1. Emits backspace keystrokes to delete the trigger string
  2. Emits keystrokes to type the replacement string
  3. Clears the buffer (no recursive expansion — the replacement is not fed back into snippet matching)
- The trigger is matched immediately after the last character is typed (no delimiter required)
- The rolling buffer is cleared on:
  - Any non-character key press (arrow keys, escape, tab, etc.)
  - Mouse click (focus change)
  - A brief typing pause (hardcoded: **3 seconds**)

## Configuration

**File:** `~/.keys.toml`

**Format:** TOML

### Schema

```toml
# Key remapping rules
[[remap]]
input = "caps_lock"
output = "F20"

[[remap]]
input = "option+shift+a"
output = "control+b"

# Keystroke sequence: keys separated by ", "
[[remap]]
input = "option, option"
output = "control+space"

# Text expansion rules
[[snippet]]
trigger = ":hi"
replacement = "Hello world"

[[snippet]]
trigger = ":sig"
replacement = """
Best regards,
Vlad
"""
```

### Key Names

Standard key names used in `input` and `output` fields:

- **Letters:** `a` – `z`
- **Numbers:** `0` – `9`
- **Modifiers:** `shift`, `control`, `option`, `command`
- **Function keys:** `F1` – `F20`
- **Special keys:** `caps_lock`, `escape`, `return`, `tab`, `space`, `delete`, `forward_delete`
- **Arrow keys:** `up`, `down`, `left`, `right`
- **Punctuation:** `minus`, `equal`, `left_bracket`, `right_bracket`, `backslash`, `semicolon`, `quote`, `grave`, `comma`, `period`, `slash`

Modifier combinations use `+` as separator: `option+shift+a`.

Keystroke sequences use `, ` (comma-space) as separator: `option, option`.

### Config Errors

If the config file has errors:
- Keys shows a warning icon in the menu bar (e.g., a yellow dot on the icon)
- The menu shows the error message
- The last valid configuration remains active
- Keys continues to watch the file and reloads when it's fixed

## Menu Bar

### Icon

A small monochrome icon representing a key or keyboard. Standard macOS menu bar template image style.

### Menu Items

| Item | Action |
|---|---|
| **Keys is ON** / **Keys is OFF** | Toggle on/off. When off, all keystrokes pass through unmodified |
| --- | separator |
| **Reload Config** | Manually reload `~/.keys.toml` |
| **Edit Config** | Opens `~/.keys.toml` in the default text editor |
| --- | separator |
| **About Keys** | Opens `https://keys.vlad.studio` in the default browser |
| **Quit Keys** | Exits the application |

### States

- **Active:** Normal menu bar icon
- **Disabled:** Dimmed/crossed-out icon, all keystrokes pass through
- **Config error:** Icon with a warning indicator

## Technical Details

- **Language:** Swift
- **Framework:** AppKit (menu bar app, no main window)
- **Minimum macOS version:** 14.0 (Sonoma)
- **Event interception:** `CGEventTap` (requires Accessibility permissions)
- **Config parsing:** TOML parser (Swift package)
- **File watching:** `DispatchSource.makeFileSystemObjectSource` or `FSEvents` on `~/.keys.toml`
- **App lifecycle:** `LSUIElement = true` (no Dock icon)
- **Distribution:** Direct download from `keys.vlad.studio` (no Mac App Store — event taps are not allowed in sandboxed apps)

## Permissions

On first launch, Keys must prompt the user to grant Accessibility permissions in **System Settings → Privacy & Security → Accessibility**. If permission is not granted, Keys should show a clear message in the menu explaining what's needed and a menu item to open the relevant System Settings pane.

## Out of Scope

- GUI configuration editor
- Per-application overrides
- Sync across devices
- Auto-update mechanism (for v1)
- Conditional/contextual rules
- Regex-based triggers
