import AppKit
import IOKit.hid
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!
    private var errorItem: NSMenuItem?
    private var accessibilityItem: NSMenuItem?
    private var inputMonitoringItem: NSMenuItem?
    private var permissionSeparator: NSMenuItem?
    private var permissionTimer: Timer?
    private var loginItem: NSMenuItem!
    private let configManager = ConfigManager()
    private let interceptor = KeyboardInterceptor()
    private let snippetPicker = SnippetPicker()

    func applicationDidFinishLaunching(_ notification: Notification) {
        interceptor.snippetPicker = snippetPicker
        interceptor.onWarning = { [weak self] msg in self?.configDidFail(msg) }
        interceptor.onPermissionLost = { [weak self] in self?.promptPermissions() }
        setupMenu()
        configManager.delegate = self
        configManager.load()
        configManager.startWatching()

        ensurePermissions()
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

        let edit = NSMenuItem(
            title: "Edit Config", action: #selector(editConfig), keyEquivalent: "e")
        edit.target = self
        menu.addItem(edit)

        menu.addItem(.separator())

        loginItem = NSMenuItem(
            title: "Start on Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        setupLoginItem()

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

    @objc private func editConfig() {
        configManager.openInEditor()
    }

    @objc private func openAbout() {
        if let url = URL(string: "https://keys.vlad.studio") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {}
        loginItem.state = service.status == .enabled ? .on : .off
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        HIDManager.reset()
    }

    // MARK: - Helpers

    private func setupLoginItem() {
        let service = SMAppService.mainApp
        if !UserDefaults.standard.bool(forKey: "loginItemConfigured") {
            UserDefaults.standard.set(true, forKey: "loginItemConfigured")
            try? service.register()
        }
        loginItem.state = service.status == .enabled ? .on : .off
    }

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

    // MARK: - Permissions

    private var hasAccessibility: Bool { AXIsProcessTrusted() }
    private var hasInputMonitoring: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    private func ensurePermissions() {
        if !hasAccessibility {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
        if !hasInputMonitoring {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }

        if !hasAccessibility || !hasInputMonitoring {
            promptPermissions()
        } else if !interceptor.start() {
            promptPermissions()
        }
    }

    private func promptPermissions() {
        interceptor.stop()
        guard permissionTimer == nil else { return }

        toggleItem.title = "Keys is OFF (no permission)"
        toggleItem.action = nil
        updatePermissionItems()

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updatePermissionItems()
            guard self.hasAccessibility, self.hasInputMonitoring else { return }
            if self.interceptor.start() {
                self.permissionsGranted()
            }
        }
    }

    private func updatePermissionItems() {
        let menu = statusItem.menu!

        if !hasAccessibility && accessibilityItem == nil {
            let item = NSMenuItem(title: "Grant Accessibility Access…",
                                  action: #selector(openAccessibilitySettings), keyEquivalent: "")
            item.target = self
            menu.insertItem(item, at: 0)
            accessibilityItem = item
        } else if hasAccessibility, let item = accessibilityItem {
            menu.removeItem(item)
            accessibilityItem = nil
        }

        if !hasInputMonitoring && inputMonitoringItem == nil {
            let item = NSMenuItem(title: "Grant Input Monitoring Access…",
                                  action: #selector(openInputMonitoringSettings), keyEquivalent: "")
            item.target = self
            let idx = accessibilityItem != nil ? 1 : 0
            menu.insertItem(item, at: idx)
            inputMonitoringItem = item
        } else if hasInputMonitoring, let item = inputMonitoringItem {
            menu.removeItem(item)
            inputMonitoringItem = nil
        }

        let needsSep = accessibilityItem != nil || inputMonitoringItem != nil
        if needsSep && permissionSeparator == nil {
            let sep = NSMenuItem.separator()
            let idx = (accessibilityItem != nil ? 1 : 0) + (inputMonitoringItem != nil ? 1 : 0)
            menu.insertItem(sep, at: idx)
            permissionSeparator = sep
        } else if !needsSep, let sep = permissionSeparator {
            menu.removeItem(sep)
            permissionSeparator = nil
        }
    }

    private func permissionsGranted() {
        permissionTimer?.invalidate()
        permissionTimer = nil

        for item in [accessibilityItem, inputMonitoringItem, permissionSeparator].compactMap({ $0 }) {
            statusItem.menu?.removeItem(item)
        }
        accessibilityItem = nil
        inputMonitoringItem = nil
        permissionSeparator = nil

        toggleItem.title = "Keys is ON"
        toggleItem.action = #selector(toggle)

        configManager.load()
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openInputMonitoringSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
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
