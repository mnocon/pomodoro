import Foundation

struct Session: Codable, Identifiable {
    let id: UUID
    let start: Date
    var end: Date?
    var completed: Bool
    var goal: String?
    var goalAchieved: Bool?
    var endComment: String?
    /// Set when the session was started in task mode: the NocoDB row this
    /// pomodoro belongs to. `goal` carries that task's title.
    var nocodbTaskID: Int?
    /// Whether task mode was active when this session began. The end-of-session
    /// comment only reaches NocoDB if the mode still matches at seal time.
    var taskModeAtStart: Bool?
}

/// Persists pomodoro sessions as JSON in ~/Library/Application Support/PomodoroBar/.
/// The full history is kept (pruned after 30 days) and shown in the history window.
final class SessionStore {
    private(set) var sessions: [Session] = []
    private let fileURL: URL

    /// ~/Library/Application Support/PomodoroBar, created on demand. Also home
    /// to nocodb.json, which is why it is shared rather than private.
    static func supportDirectory() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PomodoroBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init() {
        fileURL = Self.supportDirectory().appendingPathComponent("sessions.json")
        load()
    }

    func append(_ session: Session) {
        sessions.append(session)
        save()
    }

    func update(_ session: Session) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index] = session
        save()
    }

    /// Record the goal outcome for an already-sealed session.
    func setOutcome(id: UUID, achieved: Bool?, comment: String?) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].goalAchieved = achieved
        sessions[index].endComment = comment
        save()
    }

    /// Drop a session outright — used when the task dialog is cancelled, which
    /// means the pomodoro never really started.
    func remove(id: UUID) {
        sessions.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded = (try? decoder.decode([Session].self, from: data)) ?? []

        // A session left open by a crash can never complete — mark it abandoned.
        for index in loaded.indices where loaded[index].end == nil {
            loaded[index].completed = false
        }
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        sessions = loaded.filter { $0.start >= cutoff }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(sessions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
