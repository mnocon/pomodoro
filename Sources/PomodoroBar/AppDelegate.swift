import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config: Config!
    private var store: SessionStore!
    private var engine: PomodoroEngine!
    private var statusBar: StatusBarController!
    private var hotkey: HotkeyManager!
    private var prompts: FullscreenPromptController!
    private var activity: ActivityMonitor!
    private var summary: SummaryWindowController!
    private var dialogs: SessionDialogController!
    private var taskMode: TaskModeController!
    private var taskCache: TaskListCache!
    private var nocodb: NocoDBClient?
    /// Why NocoDB is unusable, if it is — shown instead of a task list.
    private var nocodbError: NocoDBError?
    /// Set while starting a pomodoro straight from a menu task, which skips
    /// the picker dialog. Consumed synchronously by `onSessionStarted`.
    private var presetTask: NocoDBTask?

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = Config.load()
        store = SessionStore()
        engine = PomodoroEngine(config: config, store: store)
        statusBar = StatusBarController(engine: engine, config: config)
        prompts = FullscreenPromptController(config: config)
        summary = SummaryWindowController()
        dialogs = SessionDialogController()
        hotkey = HotkeyManager()
        activity = ActivityMonitor(config: config)
        taskMode = TaskModeController(config: config)
        taskCache = TaskListCache()
        loadNocoDB()

        wireComponents()
        activity.start()
        taskCache.start(interval: config.taskListRefresh)

        // Wake from sleep: evaluate the timer immediately so an expired
        // task/break flips to its prompt without waiting for the next tick.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.engine.forceTick()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.appWillTerminate()
    }

    private func loadNocoDB() {
        let url = SessionStore.supportDirectory()
            .appendingPathComponent(NocoDBConfig.fileName)
        switch NocoDBConfig.loadOrCreateTemplate(at: url) {
        case .success(let config):
            nocodb = NocoDBClient(config: config, timeout: self.config.nocodbTimeout)
        case .failure(let error):
            nocodbError = error
        }
    }

    private func wireComponents() {
        engine.onStateChanged = { [weak self] state in
            self?.handleStateChange(state)
        }
        engine.onTick = { [weak self] in
            self?.statusBar.update()
        }
        engine.isTaskModeActive = { [weak self] in
            self?.taskMode.isActive ?? false
        }
        engine.onSessionStarted = { [weak self] session in
            guard let self else { return }
            // Started by clicking a task in the menu: it is already chosen.
            if let task = self.presetTask {
                self.engine.setTask(task, for: session.id)
                self.summary.reloadIfVisible()
                return
            }
            guard self.taskMode.isActive else {
                self.dialogs.askGoal { goal in
                    self.engine.setGoal(goal, for: session.id)
                    self.summary.reloadIfVisible()
                }
                return
            }
            self.askForTask(session)
        }
        engine.onSessionSealed = { [weak self] session, interactive in
            guard let self else { return }
            self.summary.reloadIfVisible()
            guard interactive else { return } // quit path: no dialog
            // Sampled now, not after the dialog: a comment typed at 17:05 on a
            // pomodoro begun at 16:45 belongs to the mode it started in.
            let modeUnchanged = (session.taskModeAtStart ?? false) == self.taskMode.isActive
            self.dialogs.askOutcome(for: session) { achieved, comment in
                self.store.setOutcome(id: session.id, achieved: achieved, comment: comment)
                self.summary.reloadIfVisible()
                self.pushComment(for: session, comment: comment, modeUnchanged: modeUnchanged)
            }
        }

        statusBar.onShowSummary = { [weak self] in
            self?.summary.show()
        }

        statusBar.taskModeSetting = { [weak self] in self?.taskMode.setting ?? .auto }
        statusBar.isTaskModeActive = { [weak self] in self?.taskMode.isActive ?? false }
        statusBar.taskList = { [weak self] in self?.taskCache.tasks ?? [] }
        statusBar.onSelectTaskMode = { [weak self] setting in
            self?.taskMode.select(setting)
        }
        statusBar.onRefreshTasks = { [weak self] in
            self?.taskCache.refresh()
        }
        statusBar.onStartTask = { [weak self] task in
            guard let self else { return }
            self.presetTask = task
            self.engine.startTask() // fires onSessionStarted synchronously
            self.presetTask = nil
        }

        taskCache.client = nocodb
        taskCache.isEnabled = { [weak self] in self?.taskMode.isActive ?? false }
        taskCache.onChange = { [weak self] in self?.statusBar.update() }

        hotkey.onHotkey = { [weak self] in
            self?.engine.hotkeyPressed()
        }

        summary.allSessions = { [weak self] in
            self?.store.sessions ?? []
        }
        summary.currentSessionID = { [weak self] in
            self?.engine.currentSession?.id
        }

        activity.shouldNag = { [weak self] in
            guard let self else { return false }
            return self.engine.state == .idle && !self.prompts.isVisible && !self.dialogs.isShowing
        }
        activity.onSustainedActivity = { [weak self] in
            self?.prompts.show(.startNag)
        }

        prompts.onPrimary = { [weak self] kind in
            guard let self else { return }
            switch kind {
            case .taskDone:
                self.engine.startBreak()
            case .breakDone, .startNag:
                self.engine.startTask()
            }
        }
        prompts.onSecondary = { [weak self] kind in
            guard let self else { return }
            switch kind {
            case .taskDone, .breakDone:
                self.engine.extend()
            case .startNag:
                self.activity.snooze()
                self.prompts.hide()
            }
        }
        prompts.onDismiss = { [weak self] kind in
            guard let self else { return }
            switch kind {
            case .taskDone, .breakDone:
                self.engine.dismissPrompt()
            case .startNag:
                self.activity.snooze()
                self.prompts.hide()
            }
        }
    }

    // MARK: - Task mode

    /// Fetch today's tasks, then ask which one this pomodoro is for. Any
    /// failure aborts the pomodoro: in task mode a session without a task is
    /// not a thing the app records.
    private func askForTask(_ session: Session) {
        guard let client = nocodb else {
            return abort(session, reason: nocodbError?.localizedDescription ?? "NocoDB is unavailable.")
        }
        client.fetchTodayTasks { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .failure(let error):
                    self.abort(session, reason: error.localizedDescription)
                case .success(let tasks):
                    self.taskCache.replace(tasks)
                    self.dialogs.askTask(tasks: tasks) { choice in
                        switch choice {
                        case .cancelled:
                            self.engine.abortSession(id: session.id)
                        case .existing(let task):
                            self.engine.setTask(task, for: session.id)
                            self.summary.reloadIfVisible()
                        case .new(let title):
                            self.createTask(titled: title, for: session)
                        }
                    }
                }
            }
        }
    }

    /// "Other" creates the row immediately, so it exists even if this pomodoro
    /// is abandoned — and shows up in the rest of today's dropdowns.
    private func createTask(titled title: String, for session: Session) {
        guard let client = nocodb else { return }
        client.createTask(title: title) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let task):
                    self.engine.setTask(task, for: session.id)
                    self.summary.reloadIfVisible()
                    self.taskCache.refresh()
                case .failure(let error):
                    self.abort(session, reason: error.localizedDescription)
                }
            }
        }
    }

    private func abort(_ session: Session, reason: String) {
        engine.abortSession(id: session.id) // stop the clock first
        summary.reloadIfVisible()
        dialogs.showError(
            title: "Pomodoro cancelled — no task list",
            message: "Task mode needs NocoDB to name a task.\n\n\(reason)\n\n"
                + "Set Task Mode to Off in the menu to run pomodoros without a task.")
    }

    /// Prepend this pomodoro to its task's `Komentarz`. Only completed sessions
    /// are logged, and only while the mode has not flipped underneath them.
    private func pushComment(for session: Session, comment: String?, modeUnchanged: Bool) {
        guard session.completed, modeUnchanged,
              let taskID = session.nocodbTaskID, let client = nocodb else { return }

        let line = Self.commentLine(start: session.start, comment: comment)
        client.prependComment(taskID: taskID, line: line) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    self.taskCache.refresh()
                case .failure(let error):
                    // No retry and no queue by design — the alert carries the
                    // text so it can be pasted into NocoDB by hand.
                    self.dialogs.showError(
                        title: "Couldn't write to NocoDB",
                        message: "Task: \(session.goal ?? "#\(taskID)")\n\n\(line)\n\n"
                            + error.localizedDescription)
                }
            }
        }
    }

    /// `2026-09-13 14:30 — comment`, stamped with the session's start time. A
    /// blank comment still logs the line: it records attention spent.
    static func commentLine(start: Date, comment: String?) -> String {
        let stamp = commentFormatter.string(from: start)
        guard let comment, !comment.isEmpty else { return "\(stamp) —" }
        return "\(stamp) — \(comment)"
    }

    private static let commentFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private func handleStateChange(_ state: PomodoroState) {
        statusBar.update()
        summary.reloadIfVisible()

        switch state {
        case .taskCompletePrompt:
            prompts.show(.taskDone)
        case .breakCompletePrompt:
            prompts.show(.breakDone)
        case .runningTask, .onBreak:
            prompts.hide()
            activity.reset()
        case .idle:
            // Leave a startNag prompt alone (it is shown while idle);
            // completion prompts are closed by their own transitions.
            if prompts.currentKind != .startNag {
                prompts.hide()
            }
        }
    }
}
