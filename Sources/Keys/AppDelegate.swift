import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!
    private var errorItem: NSMenuItem?
    private let configManager = ConfigManager()
    private let interceptor = KeyboardInterceptor()

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        if let url = bundle.url(forResource: "MenuIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        return nil
    }

    private func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)

        let item = NSMenuItem(
            title: "⚠ Grant Accessibility Access",
            action: #selector(openAccessibilitySettings), keyEquivalent: "")
        item.target = self
        statusItem.menu?.insertItem(item, at: 0)
        statusItem.menu?.insertItem(.separator(), at: 1)
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
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
