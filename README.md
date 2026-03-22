# Keys

<img src="keys app icon.png" width="128" alt="Keys icon">

A macOS menu bar app that remaps keys and expands text snippets.

- **Key remapping** — single keys, modifier combos, double-tap sequences
- **Text expansion** — type a trigger, get it replaced instantly
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
caps_lock,f20
option+shift+a,control+b
"option, option",f19

[snippet]
:hi,Hello world
:sig,"Best regards,
Steve"
```

### Key names

`a`–`z`, `0`–`9`, `f1`–`f20`, `return`, `tab`, `space`, `delete`, `escape`, `caps_lock`, `forward_delete`, `up`, `down`, `left`, `right`, `minus`, `equal`, `left_bracket`, `right_bracket`, `backslash`, `semicolon`, `quote`, `grave`, `comma`, `period`, `slash`, `shift`, `control`, `option`, `command` (and `right_*` variants).

Combine modifiers with `+`: `option+shift+a`. Sequences with `, `: `"option, option"`.

## License

MIT
