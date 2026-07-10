import AppKit

/// Owns the NSStatusItem: live countdown in the menu bar title plus the menu.
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let engine: PomodoroEngine
    private let config: Config

    private let headerItem = NSMenuItem()
    private let startItem = NSMenuItem()
    private let stopItem = NSMenuItem()
    private let extendItem = NSMenuItem()
    private let breakItem = NSMenuItem()
    private let loginItem = NSMenuItem()

    var onShowSummary: (() -> Void)?

    init(engine: PomodoroEngine, config: Config) {
        self.engine = engine
        self.config = config
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize, weight: .regular)
        statusItem.menu = buildMenu()
        update()
    }

    /// Refresh the status bar title and menu header from the engine state.
    func update() {
        statusItem.button?.title = title(for: engine.state)
        headerItem.title = headerText()
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(.separator())

        startItem.title = "Start Pomodoro"
        startItem.target = self
        startItem.action = #selector(startPomodoro)
        startItem.keyEquivalent = "p"
        startItem.keyEquivalentModifierMask = [.control, .option, .command]
        menu.addItem(startItem)

        stopItem.title = "Stop Pomodoro"
        stopItem.target = self
        stopItem.action = #selector(stopPomodoro)
        menu.addItem(stopItem)

        extendItem.title = "Extend +\(config.extendLabel)"
        extendItem.target = self
        extendItem.action = #selector(extendCurrent)
        menu.addItem(extendItem)

        breakItem.target = self
        breakItem.action = #selector(breakAction)
        menu.addItem(breakItem)

        menu.addItem(.separator())

        let summaryItem = NSMenuItem(title: "History…",
                                     action: #selector(showSummary), keyEquivalent: "")
        summaryItem.target = self
        menu.addItem(summaryItem)

        menu.addItem(.separator())

        loginItem.title = "Start at Login"
        loginItem.target = self
        loginItem.action = #selector(toggleLoginItem)
        menu.addItem(loginItem)

        let quitItem = NSMenuItem(title: "Quit PomodoroBar",
                                  action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        headerItem.title = headerText()

        // Refresh on every open: the user can also toggle it in System Settings.
        loginItem.isEnabled = LoginItemManager.isAvailable
        loginItem.state = LoginItemManager.isEnabled ? .on : .off
        loginItem.toolTip = LoginItemManager.isAvailable ? nil
            : "Available only when running from PomodoroBar.app (scripts/make-app.sh)"

        switch engine.state {
        case .idle:
            startItem.isEnabled = true
            stopItem.isEnabled = false
            extendItem.isEnabled = false
            breakItem.title = "Start Break"
            breakItem.isEnabled = true
        case .runningTask:
            startItem.isEnabled = false
            stopItem.isEnabled = true
            extendItem.isEnabled = true
            breakItem.title = "Start Break"
            breakItem.isEnabled = false
        case .taskCompletePrompt:
            startItem.isEnabled = true
            stopItem.isEnabled = false
            extendItem.isEnabled = true
            breakItem.title = "Start Break"
            breakItem.isEnabled = true
        case .onBreak:
            startItem.isEnabled = false
            stopItem.isEnabled = false
            extendItem.isEnabled = true
            breakItem.title = "End Break"
            breakItem.isEnabled = true
        case .breakCompletePrompt:
            startItem.isEnabled = true
            stopItem.isEnabled = false
            extendItem.isEnabled = true
            breakItem.title = "Start Break"
            breakItem.isEnabled = false
        }
    }

    // MARK: - Actions

    @objc private func startPomodoro() { engine.startTask() }
    @objc private func stopPomodoro() { engine.stop() }
    @objc private func extendCurrent() { engine.extend() }

    @objc private func breakAction() {
        if case .onBreak = engine.state {
            engine.stop()
        } else {
            engine.startBreak()
        }
    }

    @objc private func showSummary() { onShowSummary?() }
    @objc private func toggleLoginItem() { try? LoginItemManager.setEnabled(!LoginItemManager.isEnabled) }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Formatting

    private func title(for state: PomodoroState) -> String {
        switch state {
        case .idle:
            return "🍅"
        case .runningTask:
            return "🍅 " + Self.format(engine.remaining() ?? 0)
        case .taskCompletePrompt:
            return "🍅 ✓"
        case .onBreak:
            return "☕️ " + Self.format(engine.remaining() ?? 0)
        case .breakCompletePrompt:
            return "☕️ ✓"
        }
    }

    private func headerText() -> String {
        switch engine.state {
        case .idle:
            return "Idle — no pomodoro running"
        case .runningTask:
            return "Focusing — \(Self.format(engine.remaining() ?? 0)) left"
        case .taskCompletePrompt:
            return "Pomodoro complete"
        case .onBreak:
            return "On break — \(Self.format(engine.remaining() ?? 0)) left"
        case .breakCompletePrompt:
            return "Break finished"
        }
    }

    static func format(_ interval: TimeInterval) -> String {
        let total = Int(ceil(max(0, interval)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
