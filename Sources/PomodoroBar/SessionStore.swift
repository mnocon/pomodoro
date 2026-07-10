import Foundation

struct Session: Codable, Identifiable {
    let id: UUID
    let start: Date
    var end: Date?
    var completed: Bool
    var goal: String?
    var goalAchieved: Bool?
    var endComment: String?
}

/// Persists pomodoro sessions as JSON in ~/Library/Application Support/PomodoroBar/.
/// The full history is kept (pruned after 30 days) and shown in the history window.
final class SessionStore {
    private(set) var sessions: [Session] = []
    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PomodoroBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("sessions.json")
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
