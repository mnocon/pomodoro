import CoreGraphics
import Foundation

/// Watches for user input while no pomodoro is running and, after a sustained
/// stretch of activity, asks for the "start a pomodoro" nag to be shown.
/// Uses CGEventSource.secondsSinceLastEventType, which needs no permissions.
final class ActivityMonitor {
    private let config: Config
    private var timer: Timer?
    private var activeAccumulated: TimeInterval = 0
    private var snoozeUntil: Date = .distantPast

    /// Should return true only when the engine is idle and no prompt is up.
    var shouldNag: (() -> Bool)?
    var onSustainedActivity: (() -> Void)?

    init(config: Config) {
        self.config = config
    }

    func start() {
        let t = Timer(timeInterval: config.pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func snooze() {
        snoozeUntil = Date().addingTimeInterval(config.snoozeDuration)
        activeAccumulated = 0
    }

    func reset() {
        activeAccumulated = 0
    }

    private func poll() {
        guard shouldNag?() == true, Date() >= snoozeUntil else {
            activeAccumulated = 0
            return
        }
        if secondsSinceLastInput() < config.pollInterval {
            activeAccumulated += config.pollInterval
        } else {
            activeAccumulated = 0
        }
        if activeAccumulated >= config.activityWindow {
            activeAccumulated = 0
            onSustainedActivity?()
        }
    }

    private func secondsSinceLastInput() -> TimeInterval {
        // kCGAnyInputEventType has no Swift constant; ~0 is its raw value.
        if let anyInput = CGEventType(rawValue: ~UInt32(0)) {
            return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        }
        let types: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown,
                                    .rightMouseDown, .scrollWheel, .leftMouseDragged]
        return types
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? .infinity
    }
}
