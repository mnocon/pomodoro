import Foundation

/// Holds the last successfully fetched task list so the status bar menu can be
/// built synchronously in `menuNeedsUpdate`. Refreshes happen in the
/// background; failures are silent here — a stale menu is fine, and errors
/// that matter surface when a pomodoro actually starts.
final class TaskListCache {
    private(set) var tasks: [NocoDBTask] = []

    var client: NocoDBClient?
    /// Don't poll NocoDB during work hours when task mode is off.
    var isEnabled: () -> Bool = { true }
    var onChange: (() -> Void)?

    private var timer: Timer?
    private var isFetching = false

    func start(interval: TimeInterval) {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func refresh() {
        guard isEnabled(), let client, !isFetching else { return }
        isFetching = true
        client.fetchTodayTasks { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFetching = false
                guard case .success(let tasks) = result else { return }
                self.replace(tasks)
            }
        }
    }

    /// Adopt a list fetched elsewhere (the session-start fetch) so the menu
    /// doesn't lag one refresh interval behind what the dialog just showed.
    func replace(_ tasks: [NocoDBTask]) {
        guard tasks != self.tasks else { return }
        self.tasks = tasks
        onChange?()
    }
}
