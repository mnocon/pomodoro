import Foundation

/// App configuration. Every duration can be overridden for testing via
/// command-line arguments, which macOS maps into UserDefaults automatically:
///
///     swift run PomodoroBar -taskSeconds 15 -breakSeconds 10 -activityWindowSeconds 10 -snoozeSeconds 20
struct Config {
    let taskDuration: TimeInterval
    let breakDuration: TimeInterval
    let extendIncrement: TimeInterval
    let activityWindow: TimeInterval
    let snoozeDuration: TimeInterval
    let pollInterval: TimeInterval
    /// How long the keyboard must be quiet before a fullscreen prompt
    /// accepts input — prevents in-flight typing from dismissing it.
    let promptGuard: TimeInterval
    /// How long the task dialog waits on NocoDB before giving up. Short on
    /// purpose: the pomodoro clock is already running behind the dialog.
    let nocodbTimeout: TimeInterval
    /// Background refresh interval for the task list shown in the menu.
    let taskListRefresh: TimeInterval
    /// Work-hours window; task mode auto-engages outside it.
    let workDayStartHour: Int
    let workDayEndHour: Int
    /// How many tasks the status bar menu lists.
    let menuTaskLimit: Int

    static func load() -> Config {
        let defaults = UserDefaults.standard
        func seconds(_ key: String, default def: TimeInterval) -> TimeInterval {
            let value = defaults.double(forKey: key)
            return value > 0 ? value : def
        }
        // Hours and counts, unlike durations, have meaningful zero values.
        func integer(_ key: String, default def: Int) -> Int {
            defaults.object(forKey: key) == nil ? def : defaults.integer(forKey: key)
        }
        return Config(
            taskDuration: seconds("taskSeconds", default: 25 * 60),
            breakDuration: seconds("breakSeconds", default: 5 * 60),
            extendIncrement: seconds("extendSeconds", default: 5 * 60),
            activityWindow: seconds("activityWindowSeconds", default: 30),
            snoozeDuration: seconds("snoozeSeconds", default: 5 * 60),
            pollInterval: seconds("pollSeconds", default: 5),
            promptGuard: seconds("promptGuardSeconds", default: 1.5),
            nocodbTimeout: seconds("nocodbTimeoutSeconds", default: 3),
            taskListRefresh: seconds("taskListRefreshSeconds", default: 5 * 60),
            workDayStartHour: integer("workDayStartHour", default: 9),
            workDayEndHour: integer("workDayEndHour", default: 17),
            menuTaskLimit: integer("menuTaskLimit", default: 7)
        )
    }

    var extendLabel: String { Config.durationLabel(extendIncrement) }
    var snoozeLabel: String { Config.durationLabel(snoozeDuration) }

    static func durationLabel(_ interval: TimeInterval) -> String {
        if interval >= 60 && interval.truncatingRemainder(dividingBy: 60) == 0 {
            return "\(Int(interval) / 60) min"
        }
        return "\(Int(interval)) s"
    }
}
