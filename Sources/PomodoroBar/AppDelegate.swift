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

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = Config.load()
        store = SessionStore()
        engine = PomodoroEngine(config: config, store: store)
        statusBar = StatusBarController(engine: engine, config: config)
        prompts = FullscreenPromptController(config: config)
        summary = SummaryWindowController()
        hotkey = HotkeyManager()
        activity = ActivityMonitor(config: config)

        wireComponents()
        activity.start()

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

    private func wireComponents() {
        engine.onStateChanged = { [weak self] state in
            self?.handleStateChange(state)
        }
        engine.onTick = { [weak self] in
            self?.statusBar.update()
        }
        engine.onSessionSealed = { [weak self] in
            self?.summary.reloadIfVisible()
        }

        statusBar.onShowSummary = { [weak self] in
            self?.summary.show()
        }

        hotkey.onHotkey = { [weak self] in
            self?.engine.hotkeyPressed()
        }

        summary.todaySessions = { [weak self] in
            self?.store.todaySessions() ?? []
        }
        summary.currentSessionID = { [weak self] in
            self?.engine.currentSession?.id
        }

        activity.shouldNag = { [weak self] in
            guard let self else { return false }
            return self.engine.state == .idle && !self.prompts.isVisible
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
