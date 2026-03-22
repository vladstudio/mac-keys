import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!
    private var errorItem: NSMenuItem?
    private var accessibilityItem: NSMenuItem?
    private var accessibilitySeparator: NSMenuItem?
    private var accessibilityTimer: Timer?
    private let configManager = ConfigManager()
    private let interceptor = KeyboardInterceptor()
    private let snippetPicker = SnippetPicker()

    func applicationDidFinishLaunching(_ notification: Notification) {
        interceptor.snippetPicker = snippetPicker
        setupMenu()
        configManager.delegate = self
        configManager.load()
        configManager.startWatching()

        if !interceptor.start() {
            promptAccessibility()
        }
    }

    // MARK: - Menu

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let icon = loadMenuIcon() {
                icon.isTemplate = true
                button.image = icon
            } else {
                button.image = NSImage(
                    systemSymbolName: "keyboard",
                    accessibilityDescription: "Keys")
            }
        }

        let menu = NSMenu()

        toggleItem = NSMenuItem(title: "Keys is ON", action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let reload = NSMenuItem(
            title: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "r")
        reload.target = self
        menu.addItem(reload)

        let edit = NSMenuItem(
            title: "Edit Config", action: #selector(editConfig), keyEquivalent: "e")
        edit.target = self
        menu.addItem(edit)

        menu.addItem(.separator())

        let about = NSMenuItem(
            title: "About Keys", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit Keys", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func toggle() {
        interceptor.isEnabled.toggle()
        toggleItem.title = interceptor.isEnabled ? "Keys is ON" : "Keys is OFF"
        updateIcon()
    }

    @objc private func reloadConfig() {
        configManager.load()
    }

    @objc private func editConfig() {
        configManager.openInEditor()
    }

    @objc private func openAbout() {
        if let url = URL(string: "https://keys.vlad.studio") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Helpers

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        button.appearsDisabled = !interceptor.isEnabled && errorItem == nil
    }

    private func loadMenuIcon() -> NSImage? {
        let bundle = Bundle.main
        let image = NSImage(size: NSSize(width: 18, height: 18))

        if let url1x = bundle.url(forResource: "MenuIcon", withExtension: "png"),
           let rep1x = NSImageRep(contentsOf: url1x) {
            rep1x.size = NSSize(width: 18, height: 18)
            image.addRepresentation(rep1x)
        }
        if let url2x = bundle.url(forResource: "MenuIcon@2x", withExtension: "png"),
           let rep2x = NSImageRep(contentsOf: url2x) {
            rep2x.size = NSSize(width: 18, height: 18)
            image.addRepresentation(rep2x)
        }

        guard !image.representations.isEmpty else { return nil }
        return image
    }

    private func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)

        let sep = NSMenuItem.separator()
        let item = NSMenuItem(
            title: "Grant Accessibility Access…",
            action: #selector(openAccessibilitySettings), keyEquivalent: "")
        item.target = self
        statusItem.menu?.insertItem(item, at: 0)
        statusItem.menu?.insertItem(sep, at: 1)
        accessibilityItem = item
        accessibilitySeparator = sep

        toggleItem.title = "Keys is OFF (no permission)"
        toggleItem.action = nil

        // Poll until permission is granted
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if AXIsProcessTrusted() {
                self.accessibilityGranted()
            }
        }
    }

    private func accessibilityGranted() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil

        if let item = accessibilityItem { statusItem.menu?.removeItem(item) }
        if let sep = accessibilitySeparator { statusItem.menu?.removeItem(sep) }
        accessibilityItem = nil
        accessibilitySeparator = nil

        toggleItem.title = "Keys is ON"
        toggleItem.action = #selector(toggle)

        if interceptor.start() {
            configManager.load() // apply config to the now-running interceptor
        }
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

// MARK: - ConfigManagerDelegate

extension AppDelegate: ConfigManagerDelegate {
    func configDidUpdate(_ config: Config) {
        interceptor.update(config: config)
        if let item = errorItem {
            statusItem.menu?.removeItem(item)
            errorItem = nil
        }
        updateIcon()
    }

    func configDidFail(_ error: String) {
        if let item = errorItem {
            item.title = "⚠ \(error)"
        } else {
            let item = NSMenuItem(title: "⚠ \(error)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            statusItem.menu?.insertItem(item, at: 1)
            errorItem = item
        }
        updateIcon()
    }
}
