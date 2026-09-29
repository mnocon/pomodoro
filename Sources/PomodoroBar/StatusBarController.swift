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
    private let taskModeItem = NSMenuItem()

    /// Menu rows for the task list, tracked so they can be swapped out wholesale
    /// each time the menu opens.
    private var taskItems: [NSMenuItem] = []

    var onShowSummary: (() -> Void)?

    // Task mode. All optional/defaulted so the controller stays usable
    // (and testable) without a NocoDB connection wired up.
    var taskModeSetting: () -> TaskModeSetting = { .auto }
    var isTaskModeActive: () -> Bool = { false }
    var taskList: () -> [NocoDBTask] = { [] }
    var onSelectTaskMode: ((TaskModeSetting) -> Void)?
    var onRefreshTasks: (() -> Void)?
    var onStartTask: ((NocoDBTask) -> Void)?

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

        taskModeItem.title = "Task Mode"
        taskModeItem.submenu = buildTaskModeMenu()
        menu.addItem(taskModeItem)

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

    private func buildTaskModeMenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for setting in TaskModeSetting.allCases {
            let item = NSMenuItem(title: setting.title,
                                  action: #selector(selectTaskMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = setting.rawValue
            submenu.addItem(item)
        }
        return submenu
    }

    /// Rebuild the task rows just below the header. They only exist while task
    /// mode is active, and are drawn from the cache — `menuNeedsUpdate` is
    /// synchronous, so the network refresh it kicks off lands on a later open.
    private func rebuildTaskItems(in menu: NSMenu) {
        for item in taskItems { menu.removeItem(item) }
        taskItems = []
        guard isTaskModeActive() else { return }

        onRefreshTasks?()
        let tasks = Array(taskList().prefix(config.menuTaskLimit))
        let today = Date()

        var newItems: [NSMenuItem] = []
        if tasks.isEmpty {
            let empty = NSMenuItem(title: "No tasks for today", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            newItems.append(empty)
        } else {
            for task in tasks {
                let item = NSMenuItem(title: task.label(today: today),
                                      action: #selector(startTask(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = task
                // Starting a task mid-pomodoro would have to seal the current
                // one; keep it to the states where starting is already allowed.
                item.isEnabled = canStartTask
                newItems.append(item)
            }
        }
        newItems.append(.separator())

        for (offset, item) in newItems.enumerated() {
            menu.insertItem(item, at: 2 + offset) // after header + separator
        }
        taskItems = newItems
    }

    private var canStartTask: Bool {
        switch engine.state {
        case .idle, .taskCompletePrompt, .breakCompletePrompt: return true
        case .runningTask, .onBreak: return false
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        headerItem.title = headerText()
        rebuildTaskItems(in: menu)

        let setting = taskModeSetting()
        taskModeItem.submenu?.items.forEach {
            $0.state = ($0.representedObject as? String) == setting.rawValue ? .on : .off
        }

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

    @objc private func selectTaskMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let setting = TaskModeSetting(rawValue: raw) else { return }
        onSelectTaskMode?(setting)
    }

    @objc private func startTask(_ sender: NSMenuItem) {
        guard let task = sender.representedObject as? NocoDBTask else { return }
        onStartTask?(task)
    }
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
