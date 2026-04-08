import AppKit

class SnippetPicker: NSPanel, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let search = NSTextField()
    private let table = NSTableView()
    private var all = [Snippet]()
    private var filtered = [Snippet]()
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

    func show(snippets: [Snippet]) {
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
        if q.isEmpty {
            filtered = all
        } else {
            let kwBonus = 10_000
            let scored = all.compactMap { s -> (Snippet, Int)? in
                if let kw = s.keyword, kw.lowercased() == q { return (s, Int.max) }
                let textScore = fuzzyScore(query: q, target: s.text.lowercased())
                let kwScore = s.keyword.flatMap { fuzzyScore(query: q, target: $0.lowercased()) }
                if let ks = kwScore {
                    return (s, max(ks, textScore ?? 0) + kwBonus)
                }
                if let ts = textScore {
                    return (s, ts)
                }
                return nil
            }
            filtered = scored.sorted { $0.1 > $1.1 }.map { $0.0 }
        }
        table.reloadData()
        if !filtered.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
    }

    private func fuzzyScore(query: String, target: String) -> Int? {
        let q = Array(query), t = Array(target)
        guard !t.isEmpty else { return nil }

        var wordStart = [Bool](repeating: false, count: t.count)
        wordStart[0] = true
        for i in 1..<t.count where !t[i - 1].isLetter && !t[i - 1].isNumber {
            wordStart[i] = true
        }

        var score = 0, ti = 0, prev = -1, first = -1

        for qc in q {
            // Prefer consecutive match to keep runs together
            if prev >= 0 {
                let next = prev + 1
                if next < t.count && t[next] == qc {
                    score += 7
                    if wordStart[next] { score += 10 }
                    if next == 0 { score += 8 }
                    prev = next; ti = next + 1; continue
                }
            }
            // Then word-start match, then any match
            var ws: Int?, any: Int?
            for j in ti..<t.count where t[j] == qc {
                if any == nil { any = j }
                if wordStart[j] { ws = j; break }
            }
            guard let idx = ws ?? any else { return nil }
            if wordStart[idx] { score += 10 }
            if idx == 0 { score += 8 }
            if first < 0 { first = idx }
            prev = idx; ti = idx + 1
        }

        score -= first // earlier first match wins
        return score
    }

    private func dismiss() {
        orderOut(nil)
        prevApp?.activate()
    }

    @objc private func pick() {
        guard table.selectedRow >= 0, table.selectedRow < filtered.count else { return }
        let text = filtered[table.selectedRow].text
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

    private static let kwID = NSUserInterfaceItemIdentifier("keyword")

    func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let snippet = filtered[row]

        if let view = tv.makeView(withIdentifier: Self.cellID, owner: nil) as? NSTableCellView {
            view.textField?.stringValue = displayText(snippet.text)
            let kwLabel = view.subviews.first { $0.identifier == Self.kwID } as? NSTextField
            kwLabel?.stringValue = snippet.keyword ?? ""
            kwLabel?.isHidden = snippet.keyword == nil
            return view
        }

        let cell = NSTableCellView()
        cell.identifier = Self.cellID

        let tf = NSTextField(labelWithString: displayText(snippet.text))
        tf.lineBreakMode = .byTruncatingTail
        tf.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(tf)
        cell.textField = tf

        let kw = NSTextField(labelWithString: snippet.keyword ?? "")
        kw.identifier = Self.kwID
        kw.textColor = .tertiaryLabelColor
        kw.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        kw.alignment = .right
        kw.isHidden = snippet.keyword == nil
        kw.translatesAutoresizingMaskIntoConstraints = false
        kw.setContentHuggingPriority(.required, for: .horizontal)
        kw.setContentCompressionResistancePriority(.required, for: .horizontal)
        cell.addSubview(kw)

        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            kw.leadingAnchor.constraint(greaterThanOrEqualTo: tf.trailingAnchor, constant: 8),
            kw.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            kw.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
