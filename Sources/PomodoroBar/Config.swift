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

    static func load() -> Config {
        let defaults = UserDefaults.standard
        func seconds(_ key: String, default def: TimeInterval) -> TimeInterval {
            let value = defaults.double(forKey: key)
            return value > 0 ? value : def
        }
        return Config(
            taskDuration: seconds("taskSeconds", default: 25 * 60),
            breakDuration: seconds("breakSeconds", default: 5 * 60),
            extendIncrement: seconds("extendSeconds", default: 5 * 60),
            activityWindow: seconds("activityWindowSeconds", default: 30),
            snoozeDuration: seconds("snoozeSeconds", default: 5 * 60),
            pollInterval: seconds("pollSeconds", default: 5)
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
