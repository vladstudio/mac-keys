# Keys

A macOS menu bar app that remaps keys and expands text snippets.

- **Key remapping** — single keys, modifier combos, double-tap sequences
- **Text expansion** — type a trigger, get it replaced instantly
- **Plain text config** — edit `~/.keys.toml`, changes apply automatically

## Install

```
git clone https://github.com/nicedream/keys.git
cd keys
./build.sh
open Keys.app
```

macOS 14+ required. On first launch, grant Accessibility access in System Settings.

## Configuration

Edit `~/.keys.toml`:

```toml
# Remap caps lock to F20
[[remap]]
input = "caps_lock"
output = "f20"

# Double-tap option for Ctrl+Space
[[remap]]
input = "option, option"
output = "control+space"

# Text snippets
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

### Key names

`a`–`z`, `0`–`9`, `f1`–`f20`, `return`, `tab`, `space`, `delete`, `escape`, `caps_lock`, `forward_delete`, `up`, `down`, `left`, `right`, `minus`, `equal`, `left_bracket`, `right_bracket`, `backslash`, `semicolon`, `quote`, `grave`, `comma`, `period`, `slash`, `shift`, `control`, `option`, `command` (and `right_*` variants).

Combine modifiers with `+`: `option+shift+a`. Sequences with `, `: `option, option`.

## Menu bar

- **Keys is ON / OFF** — toggle interception
- **Reload Config** — manual reload (also auto-reloads on file change)
- **Edit Config** — opens `~/.keys.toml` in your editor
- **About Keys** — [keys.vlad.studio](https://keys.vlad.studio)

## License

MIT
