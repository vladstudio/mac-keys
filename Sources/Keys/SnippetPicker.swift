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
            scroll.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
        ])
    }

    // MARK: - Show / Dismiss

    func show(snippets: [String]) {
        all = snippets
        prevApp = NSWorkspace.shared.frontmostApplication
        search.stringValue = ""
        refilter()
        center()
        makeKeyAndOrderFront(nil)
        makeFirstResponder(search)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refilter() {
        let q = search.stringValue.lowercased()
        filtered = q.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(q) }
        table.reloadData()
        if !filtered.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
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

    func controlTextDidChange(_ n: Notification) { refilter() }

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

    private static let cellID = NSUserInterfaceItemIdentifier("snippet")

    private func displayText(_ s: String) -> String {
        let first = s.prefix(while: { $0 != "\n" })
        return s.contains("\n") ? first + "…" : String(first)
    }

    func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        if let view = tv.makeView(withIdentifier: Self.cellID, owner: nil) as? NSTableCellView {
            view.textField?.stringValue = displayText(filtered[row])
            return view
        }
        let cell = NSTableCellView()
        cell.identifier = Self.cellID
        let tf = NSTextField(labelWithString: displayText(filtered[row]))
        tf.lineBreakMode = .byTruncatingTail
        tf.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(tf)
        cell.textField = tf
        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
