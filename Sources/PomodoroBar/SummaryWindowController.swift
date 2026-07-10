import AppKit

/// "Pomodoro History" window: all recorded sessions grouped by day (newest day
/// first) with per-day totals in the group headers, plus a today-total footer.
/// Refreshes live while visible.
final class SummaryWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private enum Row {
        case header(String)
        case session(Session)
    }

    private var window: NSWindow?
    private var tableView: NSTableView!
    private var totalLabel: NSTextField!
    private var refreshTimer: Timer?
    private var rows: [Row] = []

    var allSessions: (() -> [Session])?
    var currentSessionID: (() -> UUID?)?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
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

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .header = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let title):
            // Group rows are requested with tableColumn == nil and span the width.
            let identifier = NSUserInterfaceItemIdentifier("dayHeader")
            let cell = reusableCell(in: tableView, identifier: identifier) { field in
                field.font = .systemFont(ofSize: 12, weight: .semibold)
                field.textColor = .secondaryLabelColor
            }
            cell.textField?.stringValue = title
            return cell
        case .session(let session):
            guard let column = tableColumn else { return nil }
            let cell = reusableCell(in: tableView, identifier: column.identifier) { field in
                field.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            }
            let value = text(for: session, column: column.identifier.rawValue)
            cell.textField?.stringValue = value
            switch column.identifier.rawValue {
            case "goal", "comment":
                cell.toolTip = value == "—" ? nil : value
            default:
                cell.toolTip = nil
            }
            return cell
        }
    }

    private func reusableCell(in tableView: NSTableView,
                              identifier: NSUserInterfaceItemIdentifier,
                              configure: (NSTextField) -> Void) -> NSTableCellView {
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
            return reused
        }
        let cell = NSTableCellView()
        cell.identifier = identifier
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingTail
        configure(field)
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        cell.textField = field
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            field.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    // MARK: - Internals

    private func reload() {
        let sessions = allSessions?() ?? []
        let grouped = Dictionary(grouping: sessions) { Calendar.current.startOfDay(for: $0.start) }
        var newRows: [Row] = []
        for day in grouped.keys.sorted(by: >) {
            let daySessions = grouped[day]!.sorted { $0.start < $1.start }
            newRows.append(.header(headerText(day: day, sessions: daySessions)))
            newRows.append(contentsOf: daySessions.map(Row.session))
        }
        rows = newRows
        tableView.reloadData()
        totalLabel.stringValue = totalText(sessions: sessions)
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
        case "goal":
            guard let goal = session.goal else { return "—" }
            switch session.goalAchieved {
            case .some(true): return "\(goal) ✓"
            case .some(false): return "\(goal) ✗"
            case .none: return goal
            }
        case "comment":
            return session.endComment ?? "—"
        default:
            return ""
        }
    }

    private func headerText(day: Date, sessions: [Session]) -> String {
        let (total, completed) = focusTotal(sessions)
        return "\(Self.dayFormatter.string(from: day)) — Total: \(Self.durationText(total)) (\(completed) ✅)"
    }

    private func totalText(sessions: [Session]) -> String {
        let today = sessions.filter { Calendar.current.isDateInToday($0.start) }
        let (total, completed) = focusTotal(today)
        let count = completed == 1 ? "1 pomodoro" : "\(completed) pomodoros"
        return "Total focus today: \(Self.durationText(total)) (\(count) completed)"
    }

    private func focusTotal(_ sessions: [Session]) -> (duration: TimeInterval, completed: Int) {
        let inFlightID = currentSessionID?()
        var total: TimeInterval = 0
        var completedCount = 0
        for session in sessions {
            let end = session.end ?? (session.id == inFlightID ? Date() : session.start)
            total += end.timeIntervalSince(session.start)
            if session.completed { completedCount += 1 }
        }
        return (total, completedCount)
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
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 440),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pomodoro History"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let table = NSTableView()
        table.selectionHighlightStyle = .none
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 22
        table.floatsGroupRows = false

        let columns: [(String, String, CGFloat)] = [
            ("times", "Start – Finish", 120),
            ("duration", "Duration", 70),
            ("status", "Status", 110),
            ("goal", "Goal", 180),
            ("comment", "Comment", 200),
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
