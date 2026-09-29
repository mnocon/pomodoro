import AppKit

/// What the user picked in the task-mode start dialog.
enum TaskChoice {
    case existing(NocoDBTask)
    case new(String)
    /// Esc or Cancel — in task mode this aborts the pomodoro entirely.
    case cancelled
}

/// Accessory view for the task dialog: a dropdown of today's tasks plus
/// "Other…", which reveals a field for naming a new one. The view keeps a
/// constant height so revealing the field never has to re-lay-out the alert.
private final class TaskPickerView: NSView, NSTextFieldDelegate {
    let popup = NSPopUpButton(frame: NSRect(x: 0, y: 30, width: 340, height: 25))
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))

    private let tasks: [NocoDBTask]
    /// Called whenever the choice becomes (in)complete, to gate the Start button.
    var onValidityChange: ((Bool) -> Void)?

    init(tasks: [NocoDBTask]) {
        self.tasks = tasks
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 59))

        // Built as a plain NSMenu rather than via addItem(withTitle:): the
        // table really does hold duplicate titles ("Tydzień: Review" twice
        // today) and NSPopUpButton drops an item whose title it already has.
        let today = Date()
        let menu = NSMenu()
        for task in tasks {
            menu.addItem(withTitle: task.label(today: today), action: nil, keyEquivalent: "")
        }
        menu.addItem(withTitle: "Other…", action: nil, keyEquivalent: "")
        popup.menu = menu
        popup.target = self
        popup.action = #selector(selectionChanged)
        addSubview(popup)

        field.placeholderString = "New task title"
        field.delegate = self
        addSubview(field)

        // Top of the list: the highest-priority task, or — with nothing due
        // today — "Other…", which is then the only answer available.
        popup.selectItem(at: 0)
        syncFieldVisibility()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var isOtherSelected: Bool { popup.indexOfSelectedItem >= tasks.count }

    var choice: TaskChoice {
        if isOtherSelected {
            let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? .cancelled : .new(title)
        }
        let index = popup.indexOfSelectedItem
        guard tasks.indices.contains(index) else { return .cancelled }
        return .existing(tasks[index])
    }

    var isValid: Bool {
        if case .cancelled = choice { return false }
        return true
    }

    @objc private func selectionChanged() {
        syncFieldVisibility()
        if isOtherSelected { window?.makeFirstResponder(field) }
        onValidityChange?(isValid)
    }

    func controlTextDidChange(_ notification: Notification) {
        onValidityChange?(isValid)
    }

    private func syncFieldVisibility() {
        field.isHidden = !isOtherSelected
    }
}

/// Serial queue of small session dialogs: goal entry at task start, goal
/// outcome + comment at task end. Requests are enqueued and shown one at a
/// time after the current call stack unwinds, so a chained "seal old task,
/// start new one" produces two dialogs in order instead of stacking, and no
/// modal ever runs inside an engine callback.
final class SessionDialogController {
    private var queue: [() -> Void] = []
    private(set) var isShowing = false

    func askGoal(completion: @escaping (String?) -> Void) {
        enqueue {
            let alert = NSAlert()
            alert.messageText = "What's your goal for this pomodoro?"
            alert.informativeText = "Optional — leave empty to skip."

            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            field.placeholderString = "Goal"
            alert.accessoryView = field
            alert.window.initialFirstResponder = field

            alert.addButton(withTitle: "Set Goal")
            alert.addButton(withTitle: "Skip")

            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            completion(response == .alertFirstButtonReturn ? Self.nonEmpty(field.stringValue) : nil)
        }
    }

    /// Task-mode replacement for `askGoal`: pick today's task, or name a new one.
    func askTask(tasks: [NocoDBTask], completion: @escaping (TaskChoice) -> Void) {
        enqueue {
            let alert = NSAlert()
            alert.messageText = "Which task is this pomodoro for?"
            alert.informativeText = tasks.isEmpty
                ? "Nothing is due today — name what you're working on and it becomes a task."
                : "Sorted by priority. Pick one, or choose Other… to create a new task."

            let picker = TaskPickerView(tasks: tasks)
            alert.accessoryView = picker

            alert.addButton(withTitle: "Start")
            alert.addButton(withTitle: "Cancel")
            let start = alert.buttons[0]
            start.isEnabled = picker.isValid
            picker.onValidityChange = { start.isEnabled = $0 }

            alert.window.initialFirstResponder = tasks.isEmpty ? picker.field : picker.popup

            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            completion(response == .alertFirstButtonReturn ? picker.choice : .cancelled)
        }
    }

    /// Surface a NocoDB failure through the same queue, so it can never appear
    /// on top of (or underneath) a session dialog.
    func showError(title: String, message: String) {
        enqueue {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            _ = alert.runModal()
        }
    }

    func askOutcome(for session: Session, completion: @escaping (Bool?, String?) -> Void) {
        enqueue {
            let alert = NSAlert()
            alert.messageText = "Pomodoro ended"
            if let goal = session.goal {
                alert.informativeText = "Goal: \(goal)\nDid you achieve it?"
            } else {
                alert.informativeText = "How did it go?"
            }

            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            field.placeholderString = "Comment (optional)"
            alert.accessoryView = field
            alert.window.initialFirstResponder = field

            alert.addButton(withTitle: "Yes")
            alert.addButton(withTitle: "No")
            alert.addButton(withTitle: "Skip")

            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            let achieved: Bool?
            switch response {
            case .alertFirstButtonReturn: achieved = true
            case .alertSecondButtonReturn: achieved = false
            default: achieved = nil
            }
            completion(achieved, Self.nonEmpty(field.stringValue))
        }
    }

    // MARK: - Internals

    private func enqueue(_ show: @escaping () -> Void) {
        queue.append(show)
        guard !isShowing else { return }
        DispatchQueue.main.async { self.drain() }
    }

    private func drain() {
        guard !isShowing, !queue.isEmpty else { return }
        isShowing = true
        let show = queue.removeFirst()
        show()
        isShowing = false
        if !queue.isEmpty {
            DispatchQueue.main.async { self.drain() }
        }
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
