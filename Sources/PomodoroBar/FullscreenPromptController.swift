import AppKit

enum PromptKind {
    case taskDone
    case breakDone
    case startNag
}

/// Shows a fullscreen overlay on every screen (content on the main screen,
/// dimming on the others), above full-screen apps, on all Spaces.
final class FullscreenPromptController: NSObject {
    private final class PromptWindow: NSWindow {
        var onCancel: (() -> Void)?
        override var canBecomeKey: Bool { true }
        override func cancelOperation(_ sender: Any?) { onCancel?() }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { // Esc — belt and braces next to cancelOperation
                onCancel?()
            } else {
                super.keyDown(with: event)
            }
        }
    }

    private let config: Config
    private var windows: [PromptWindow] = []
    private(set) var currentKind: PromptKind?

    // Input guard: swallow keystrokes that are in flight when the prompt
    // appears, so typing can't blindly trigger Return/Esc. Every keystroke
    // while locked re-arms the timer; the prompt unlocks only after the
    // keyboard has been quiet for `config.promptGuard`.
    private(set) var isLocked = false
    private var guardTimer: Timer?
    private var keyMonitor: Any?
    private var primaryButton: NSButton?
    private var secondaryButton: NSButton?
    private var hintLabel: NSTextField?

    var isVisible: Bool { currentKind != nil }

    var onPrimary: ((PromptKind) -> Void)?
    var onSecondary: ((PromptKind) -> Void)?
    var onDismiss: ((PromptKind) -> Void)?

    init(config: Config) {
        self.config = config
    }

    func show(_ kind: PromptKind) {
        hide()
        currentKind = kind

        let mainScreen = NSScreen.main ?? NSScreen.screens.first
        var keyWindow: PromptWindow?
        for screen in NSScreen.screens {
            let isMain = (screen == mainScreen)
            let window = makeWindow(for: screen, isMain: isMain, kind: kind)
            windows.append(window)
            if isMain { keyWindow = window }
        }

        NSApp.activate(ignoringOtherApps: true)
        for window in windows where window !== keyWindow {
            window.orderFront(nil)
        }
        keyWindow?.makeKeyAndOrderFront(nil)
        engageGuard()
    }

    func hide() {
        disengageGuard()
        for window in windows {
            window.orderOut(nil)
        }
        windows = []
        currentKind = nil
        primaryButton = nil
        secondaryButton = nil
        hintLabel = nil
    }

    // MARK: - Input guard

    private func engageGuard() {
        isLocked = true
        updateGuardUI()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, self.isLocked, self.isVisible else { return event }
            if event.type == .keyDown {
                self.restartGuardTimer() // still typing — stay locked
            }
            return nil // swallow: no Return/Esc/key-equivalent gets through
        }
        restartGuardTimer()
    }

    private func restartGuardTimer() {
        guardTimer?.invalidate()
        guardTimer = Timer.scheduledTimer(withTimeInterval: config.promptGuard, repeats: false) { [weak self] _ in
            self?.unlockGuard()
        }
    }

    private func unlockGuard() {
        isLocked = false
        removeKeyMonitor()
        guardTimer?.invalidate()
        guardTimer = nil
        updateGuardUI()
    }

    private func disengageGuard() {
        isLocked = false
        removeKeyMonitor()
        guardTimer?.invalidate()
        guardTimer = nil
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func updateGuardUI() {
        primaryButton?.isEnabled = !isLocked
        secondaryButton?.isEnabled = !isLocked
        hintLabel?.stringValue = isLocked
            ? "⌨ Keyboard ignored while you finish typing…"
            : "Esc to dismiss"
    }

    // MARK: - Window construction

    private func makeWindow(for screen: NSScreen, isMain: Bool, kind: PromptKind) -> PromptWindow {
        let window = PromptWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isOpaque = false
        window.hasShadow = false
        window.backgroundColor = NSColor.black.withAlphaComponent(isMain ? 0.85 : 0.6)
        window.setFrame(screen.frame, display: true)
        window.onCancel = { [weak self] in
            guard let self, !self.isLocked, let kind = self.currentKind else { return }
            self.onDismiss?(kind)
        }
        if isMain {
            window.contentView = buildContent(kind: kind)
        }
        return window
    }

    private func buildContent(kind: PromptKind) -> NSView {
        let texts = texts(for: kind)

        let title = NSTextField(labelWithString: texts.title)
        title.font = .systemFont(ofSize: 42, weight: .bold)
        title.textColor = .white
        title.alignment = .center

        let body = NSTextField(labelWithString: texts.body)
        body.font = .systemFont(ofSize: 20)
        body.textColor = NSColor.white.withAlphaComponent(0.8)
        body.alignment = .center

        let primary = NSButton(title: texts.primary, target: self, action: #selector(primaryClicked))
        primary.keyEquivalent = "\r"
        primary.controlSize = .large
        primaryButton = primary

        let secondary = NSButton(title: texts.secondary, target: self, action: #selector(secondaryClicked))
        secondary.controlSize = .large
        secondaryButton = secondary

        let buttons = NSStackView(views: [secondary, primary])
        buttons.orientation = .horizontal
        buttons.spacing = 16

        let hint = NSTextField(labelWithString: "Esc to dismiss")
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = NSColor.white.withAlphaComponent(0.45)
        hint.alignment = .center
        hintLabel = hint

        let stack = NSStackView(views: [title, body, buttons, hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 24
        stack.setCustomSpacing(40, after: body)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    private func texts(for kind: PromptKind)
        -> (title: String, body: String, primary: String, secondary: String) {
        switch kind {
        case .taskDone:
            return ("Pomodoro complete! 🍅",
                    "Great work. Time for a break.",
                    "Start Break",
                    "Extend Task +\(config.extendLabel)")
        case .breakDone:
            return ("Break's over ☕️",
                    "Ready for the next pomodoro?",
                    "Start Pomodoro",
                    "Extend Break +\(config.extendLabel)")
        case .startNag:
            return ("No pomodoro running",
                    "You seem to be working — start a pomodoro to track it.",
                    "Start Pomodoro",
                    "Snooze \(config.snoozeLabel)")
        }
    }

    @objc private func primaryClicked() {
        guard !isLocked, let kind = currentKind else { return }
        onPrimary?(kind)
    }

    @objc private func secondaryClicked() {
        guard !isLocked, let kind = currentKind else { return }
        onSecondary?(kind)
    }
}
