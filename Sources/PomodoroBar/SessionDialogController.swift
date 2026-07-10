import AppKit

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
