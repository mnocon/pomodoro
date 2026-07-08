import AppKit

/// "Today's Summary" window: a table of today's pomodoros (start–finish,
/// duration, status) with a total-focus footer. Refreshes live while visible.
final class SummaryWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var tableView: NSTableView!
    private var totalLabel: NSTextField!
    private var refreshTimer: Timer?
    private var rows: [Session] = []

    var todaySessions: (() -> [Session])?
    var currentSessionID: (() -> UUID?)?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    func show() {
        if window == nil { createWindow() }
        reload()
        startRefreshTimer()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func reloadIfVisible() {
        guard window?.isVisible == true else { return }
        reload()
    }

    func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn else { return nil }
        let identifier = column.identifier
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let field = NSTextField(labelWithString: "")
            field.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            cell.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                field.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -2),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        cell.textField?.stringValue = text(for: rows[row], column: identifier.rawValue)
        return cell
    }

    // MARK: - Internals

    private func reload() {
        rows = todaySessions?() ?? []
        tableView.reloadData()
        totalLabel.stringValue = totalText()
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.reloadIfVisible()
        }
        RunLoop.main.add(t, forMode: .common)
        refreshTimer = t
    }

    private func text(for session: Session, column: String) -> String {
        let isInFlight = session.id == currentSessionID?()
        switch column {
        case "times":
            let start = Self.timeFormatter.string(from: session.start)
            if let end = session.end {
                return "\(start) – \(Self.timeFormatter.string(from: end))"
            }
            return isInFlight ? "\(start) – running…" : "\(start) – ?"
        case "duration":
            let end = session.end ?? (isInFlight ? Date() : nil)
            guard let end else { return "—" }
            return Self.durationText(end.timeIntervalSince(session.start))
        case "status":
            if isInFlight { return "⏳ In progress" }
            return session.completed ? "✅ Completed" : "✖️ Abandoned"
        default:
            return ""
        }
    }

    private func totalText() -> String {
        let inFlightID = currentSessionID?()
        var total: TimeInterval = 0
        var completedCount = 0
        for session in rows {
            let end = session.end ?? (session.id == inFlightID ? Date() : session.start)
            total += end.timeIntervalSince(session.start)
            if session.completed { completedCount += 1 }
        }
        let count = completedCount == 1 ? "1 pomodoro" : "\(completedCount) pomodoros"
        return "Total focus today: \(Self.durationText(total)) (\(count) completed)"
    }

    private static func durationText(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        if minutes >= 60 {
            return String(format: "%dh %02dm", minutes / 60, minutes % 60)
        }
        if minutes >= 1 {
            return "\(minutes)m"
        }
        return "\(Int(interval))s"
    }

    private func createWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Today's Summary"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let table = NSTableView()
        table.selectionHighlightStyle = .none
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 22

        let columns: [(String, String, CGFloat)] = [
            ("times", "Start – Finish", 160),
            ("duration", "Duration", 90),
            ("status", "Status", 140),
        ]
        for (id, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        tableView = table

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true

        let total = NSTextField(labelWithString: "")
        total.font = .systemFont(ofSize: 13, weight: .medium)
        totalLabel = total

        let stack = NSStackView(views: [scroll, total])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
        ])
        window.contentView = content
        self.window = window
    }
}
