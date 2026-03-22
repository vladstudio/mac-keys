import AppKit

class SnippetPicker: NSPanel, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let search = NSTextField()
    private let table = NSTableView()
    private var all = [String]()
    private var filtered = [String]()
    private var prevApp: NSRunningApplication?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
                   styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
                   backing: .buffered, defer: false)
        title = "Snippets"
        titlebarAppearsTransparent = true
        level = .floating
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)

        let cv = contentView!

        search.placeholderString = "Search snippets…"
        search.isBordered = false
        search.focusRingType = .none
        search.drawsBackground = false
        search.delegate = self
        search.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(search)

        let sep = NSBox(); sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(sep)

        let col = NSTableColumn(identifier: .init("s"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 28
        table.style = .plain
        table.doubleAction = #selector(pick)
        table.target = self

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(scroll)

        let icon = NSImageView()
        icon.image = loadAppIcon()
        icon.contentTintColor = .tertiaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(icon)

        let hints = makeHints()
        hints.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(hints)

        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: cv.topAnchor, constant: 28),
            search.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 12),
            search.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -12),
            sep.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 6),
            sep.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: sep.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: icon.topAnchor, constant: -6),
            icon.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 12),
            icon.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -8),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            hints.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -12),
            hints.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
        ])
    }

    // MARK: - UI helpers

    private func loadAppIcon() -> NSImage? {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        if let url = Bundle.main.url(forResource: "MenuIcon@2x", withExtension: "png"),
           let rep = NSImageRep(contentsOf: url) {
            rep.size = NSSize(width: 16, height: 16)
            image.addRepresentation(rep)
            return image
        }
        return NSImage(systemSymbolName: "keyboard.fill", accessibilityDescription: "Keys")
    }

    private func makeHints() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 5
        stack.addArrangedSubview(keyBadge("↑↓"))
        stack.addArrangedSubview(hintLabel("Navigate"))
        stack.addArrangedSubview(spacer(12))
        stack.addArrangedSubview(keyBadge("↵"))
        stack.addArrangedSubview(hintLabel("Paste"))
        stack.addArrangedSubview(spacer(12))
        stack.addArrangedSubview(keyBadge("esc"))
        stack.addArrangedSubview(hintLabel("Close"))
        return stack
    }

    private func spacer(_ width: CGFloat) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: width).isActive = true
        return v
    }

    private func hintLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 11)
        l.textColor = .tertiaryLabelColor
        return l
    }

    private func keyBadge(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        badge.layer?.cornerRadius = 4
        badge.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: badge.topAnchor, constant: 1),
            label.bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: -1),
        ])
        return badge
    }

    // MARK: - Show / Dismiss

    func show(snippets: [String]) {
        all = snippets
        filtered = snippets
        prevApp = NSWorkspace.shared.frontmostApplication
        search.stringValue = ""
        table.reloadData()
        if !filtered.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
        center()
        makeKeyAndOrderFront(nil)
        makeFirstResponder(search)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismiss() {
        orderOut(nil)
        prevApp?.activate()
    }

    @objc private func pick() {
        guard table.selectedRow >= 0 else { return }
        let text = filtered[table.selectedRow]
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            EventEmitter.pasteText(text)
        }
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ n: Notification) {
        let q = search.stringValue.lowercased()
        filtered = q.isEmpty ? all : all.filter {
            $0.localizedCaseInsensitiveContains(q)
        }
        table.reloadData()
        if !filtered.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
    }

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(insertNewline(_:)): pick(); return true
        case #selector(cancelOperation(_:)): dismiss(); return true
        case #selector(moveUp(_:)):
            moveSel(max(0, table.selectedRow - 1)); return true
        case #selector(moveDown(_:)):
            moveSel(min(filtered.count - 1, table.selectedRow + 1)); return true
        default: return false
        }
    }

    private func moveSel(_ row: Int) {
        guard row >= 0 else { return }
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    // MARK: - NSTableViewDataSource & Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTextField(labelWithString: filtered[row])
        cell.lineBreakMode = .byTruncatingTail
        cell.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(cell)
        NSLayoutConstraint.activate([
            cell.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            cell.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            cell.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }
}
