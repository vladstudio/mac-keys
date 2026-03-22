# Keys

<img src="keys app icon.png" width="128" alt="Keys icon">

A macOS menu bar app that remaps keys and pastes text snippets.

- **Key remapping** — single keys, modifier combos, double-tap sequences
- **Input source toggle** — cycle keyboard languages with a single key (e.g. caps lock)
- **Snippet picker** — trigger a floating picker with a keystroke, filter and paste
- **Plain text config** — edit `~/.keys.csv`, changes apply automatically

## Requirements

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools

## Install

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/vladstudio/mac-keys/main/install.sh)"
```

- Downloads the latest release from GitHub
- Installs to `/Applications` (replaces existing version)
- Removes quarantine flag so the unsigned app can run
- Opens the app

On first launch, grant Accessibility access in System Settings.

## Configuration

Edit `~/.keys.csv`:

```
[remap]
caps_lock,toggle_input
option+shift+a,control+b
"control, control",snippets

[snippet]
Hello world
my.email@example.com
"Best regards,
Steve"
```

### Remaps

One rule per line: `input,output`. Combine modifiers with `+`: `option+shift+a`. Sequences use `, ` inside quotes: `"option, option"`.

Special outputs:
- `snippets` — open the snippet picker
- `toggle_input` — cycle through enabled keyboard input sources (e.g. English → Russian → English)

Caps lock remaps to real keys (e.g. `caps_lock,f20`) use `hidutil` for HID-level remapping. All other remaps use CGEventTap. When using caps lock remaps, set Caps Lock to "No Action" in System Settings > Keyboard > Modifier Keys to avoid conflicts.

### Snippets

One snippet per line — the text that will be pasted. For multi-line snippets, wrap in double quotes (RFC 4180). Use `""` to escape a literal `"`.

When the snippet picker opens, type to filter, use arrow keys to navigate, Enter to paste, Escape to close. Search is fuzzy — it prioritizes matches at word boundaries (e.g. `jd` finds `john@doe.com`) and prefers matches closer to the start of a snippet.

### Key names

`a`–`z`, `0`–`9`, `f1`–`f20`, `return`, `tab`, `space`, `delete`, `escape`, `caps_lock`, `forward_delete`, `up`, `down`, `left`, `right`, `minus`, `equal`, `left_bracket`, `right_bracket`, `backslash`, `semicolon`, `quote`, `grave`, `comma`, `period`, `slash`, `shift`, `control`, `option`, `command` (and `right_*` variants).

## License

MIT
