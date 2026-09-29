import Foundation

/// What the user picked in the *Task Mode* submenu. `.auto` defers to the
/// work-hours window; the other two are absolute.
enum TaskModeSetting: String, CaseIterable {
    case auto
    case on
    case off

    var title: String {
        switch self {
        case .auto: return "Auto (outside work hours)"
        case .on: return "Always On"
        case .off: return "Off"
        }
    }
}

/// Decides whether a pomodoro should be tied to a NocoDB task.
///
/// Under `.auto` task mode is active *outside* Mon–Fri work hours — evenings,
/// nights and weekends — which is when the todo list is what needs attention.
final class TaskModeController {
    private static let defaultsKey = "taskModeSetting"

    private let startHour: Int
    private let endHour: Int
    private let calendar: Calendar

    var onChange: (() -> Void)?

    private(set) var setting: TaskModeSetting {
        didSet {
            guard setting != oldValue else { return }
            UserDefaults.standard.set(setting.rawValue, forKey: Self.defaultsKey)
            onChange?()
        }
    }

    init(config: Config, calendar: Calendar = .current) {
        startHour = config.workDayStartHour
        endHour = config.workDayEndHour
        self.calendar = calendar
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey)
        setting = stored.flatMap(TaskModeSetting.init(rawValue:)) ?? .auto
    }

    func select(_ setting: TaskModeSetting) {
        self.setting = setting
    }

    var isActive: Bool { isActive(at: Date()) }

    func isActive(at date: Date) -> Bool {
        switch setting {
        case .on: return true
        case .off: return false
        case .auto: return !isWorkHours(at: date)
        }
    }

    private func isWorkHours(at date: Date) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour], from: date)
        guard let weekday = parts.weekday, let hour = parts.hour else { return false }
        let isWeekday = (2...6).contains(weekday) // Gregorian: 1 = Sunday
        return isWeekday && hour >= startHour && hour < endHour
    }
}
