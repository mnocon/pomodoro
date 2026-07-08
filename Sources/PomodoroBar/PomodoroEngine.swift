import Foundation

enum PomodoroState: Equatable {
    case idle
    case runningTask(endDate: Date)
    case taskCompletePrompt
    case onBreak(endDate: Date)
    case breakCompletePrompt
}

/// Single source of truth for the pomodoro lifecycle. All UI observes it
/// through the three callbacks; all user actions funnel into its methods.
final class PomodoroEngine {
    private let config: Config
    private let store: SessionStore
    private var timer: Timer?

    /// The in-flight work session; created at task start, sealed (end +
    /// completed written) when the task lifecycle truly ends. Extensions
    /// keep it open.
    private(set) var currentSession: Session?

    /// When a task's timer expires we remember the scheduled end so that a
    /// Mac that slept through it still records the true finish time.
    private var pendingFinish: Date?

    private(set) var state: PomodoroState = .idle {
        didSet { stateDidChange() }
    }

    var onStateChanged: ((PomodoroState) -> Void)?
    var onTick: (() -> Void)?
    var onSessionSealed: (() -> Void)?

    init(config: Config, store: SessionStore) {
        self.config = config
        self.store = store
    }

    // MARK: - Actions

    func startTask() {
        switch state {
        case .idle, .breakCompletePrompt:
            beginTask()
        case .taskCompletePrompt:
            sealSession(completed: true)
            beginTask()
        case .runningTask, .onBreak:
            break
        }
    }

    func startBreak() {
        switch state {
        case .taskCompletePrompt:
            sealSession(completed: true)
            state = .onBreak(endDate: Date().addingTimeInterval(config.breakDuration))
        case .idle:
            state = .onBreak(endDate: Date().addingTimeInterval(config.breakDuration))
        default:
            break
        }
    }

    /// Stop whatever is running: abandon a task, end a break, close a prompt.
    func stop() {
        switch state {
        case .runningTask:
            sealSession(completed: false)
            state = .idle
        case .onBreak, .breakCompletePrompt:
            state = .idle
        case .taskCompletePrompt:
            sealSession(completed: true)
            state = .idle
        case .idle:
            break
        }
    }

    /// Extend the current task/break, or reopen one from its completion prompt.
    func extend() {
        let increment = config.extendIncrement
        switch state {
        case .runningTask(let end):
            state = .runningTask(endDate: end.addingTimeInterval(increment))
        case .onBreak(let end):
            state = .onBreak(endDate: end.addingTimeInterval(increment))
        case .taskCompletePrompt:
            pendingFinish = nil
            state = .runningTask(endDate: Date().addingTimeInterval(increment))
        case .breakCompletePrompt:
            state = .onBreak(endDate: Date().addingTimeInterval(increment))
        case .idle:
            break
        }
    }

    /// Esc on a completion prompt: acknowledge it and go idle.
    func dismissPrompt() {
        switch state {
        case .taskCompletePrompt:
            sealSession(completed: true)
            state = .idle
        case .breakCompletePrompt:
            state = .idle
        default:
            break
        }
    }

    /// Context-aware global hotkey: always advances to the next focus state.
    func hotkeyPressed() {
        switch state {
        case .idle:
            startTask()
        case .taskCompletePrompt:
            startBreak()
        case .breakCompletePrompt:
            startTask()
        case .runningTask, .onBreak:
            break
        }
    }

    func appWillTerminate() {
        switch state {
        case .runningTask:
            sealSession(completed: false)
        case .taskCompletePrompt:
            sealSession(completed: true)
        default:
            break
        }
    }

    /// Force an immediate timer evaluation (used after wake from sleep).
    func forceTick() {
        tick()
    }

    func remaining() -> TimeInterval? {
        switch state {
        case .runningTask(let end), .onBreak(let end):
            return max(0, end.timeIntervalSinceNow)
        default:
            return nil
        }
    }

    // MARK: - Internals

    private func beginTask() {
        let session = Session(id: UUID(), start: Date(), end: nil, completed: false)
        currentSession = session
        store.append(session)
        state = .runningTask(endDate: Date().addingTimeInterval(config.taskDuration))
    }

    private func sealSession(completed: Bool) {
        guard var session = currentSession else { return }
        session.end = completed ? (pendingFinish ?? Date()) : Date()
        session.completed = completed
        store.update(session)
        currentSession = nil
        pendingFinish = nil
        onSessionSealed?()
    }

    private func stateDidChange() {
        switch state {
        case .runningTask, .onBreak:
            startTimerIfNeeded()
        default:
            timer?.invalidate()
            timer = nil
        }
        onStateChanged?(state)
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common mode so the countdown keeps ticking while the status menu is open.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        switch state {
        case .runningTask(let end):
            if end.timeIntervalSinceNow <= 0 {
                pendingFinish = end
                state = .taskCompletePrompt
            } else {
                onTick?()
            }
        case .onBreak(let end):
            if end.timeIntervalSinceNow <= 0 {
                state = .breakCompletePrompt
            } else {
                onTick?()
            }
        default:
            break
        }
    }
}
