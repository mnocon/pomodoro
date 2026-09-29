import Foundation

/// Connection details for the NocoDB instance holding the todo table.
/// Deliberately kept outside the repo — in the app's Application Support
/// directory — so the API token is never committed.
struct NocoDBConfig: Codable {
    var apiURL: String
    var token: String
    var tableID: String

    static let fileName = "nocodb.json"

    /// Read the config, or write a blank template and report it as missing so
    /// the error names a file that actually exists on disk.
    static func loadOrCreateTemplate(at url: URL) -> Result<NocoDBConfig, NocoDBError> {
        guard let data = try? Data(contentsOf: url) else {
            let template = NocoDBConfig(apiURL: "http://localhost:8080", token: "", tableID: "")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let blank = try? encoder.encode(template) {
                try? blank.write(to: url, options: .atomic)
            }
            return .failure(.notConfigured(path: url.path))
        }
        guard let config = try? JSONDecoder().decode(NocoDBConfig.self, from: data) else {
            return .failure(.malformedConfig(path: url.path))
        }
        guard !config.token.isEmpty, !config.tableID.isEmpty else {
            return .failure(.notConfigured(path: url.path))
        }
        return .success(config)
    }
}

/// One open todo row. `deadline` is the (typo'd upstream) `Deadine` column.
struct NocoDBTask: Equatable {
    let id: Int
    let title: String
    let deadline: Date?
    let priority: Int

    /// `Title — 13.09`, with overdue rows flagged: `⚠ Title — 11.09 (2 d)`.
    func label(today: Date = Date(), calendar: Calendar = .current) -> String {
        guard let deadline else { return title }
        let day = NocoDBClient.displayFormatter.string(from: deadline)
        let overdueBy = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: deadline),
            to: calendar.startOfDay(for: today)).day ?? 0
        if overdueBy > 0 {
            return "⚠ \(title) — \(day) (\(overdueBy) d)"
        }
        return "\(title) — \(day)"
    }
}

enum NocoDBError: LocalizedError {
    case notConfigured(path: String)
    case malformedConfig(path: String)
    case transport(String)
    case http(status: Int, body: String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured(let path):
            return "NocoDB is not configured. Fill in apiURL, token and tableID in:\n\(path)"
        case .malformedConfig(let path):
            return "NocoDB config file is not valid JSON:\n\(path)"
        case .transport(let message):
            return "Could not reach NocoDB: \(message)"
        case .http(let status, let body):
            return "NocoDB returned HTTP \(status): \(body)"
        case .malformedResponse:
            return "NocoDB returned a response this app could not read."
        }
    }
}

/// Minimal NocoDB v2 client: list today's open TODOs, create one, and prepend
/// a line to a task's `Komentarz`. Every call is one-shot with a short timeout —
/// a pomodoro is already ticking while the caller waits.
final class NocoDBClient {
    private let config: NocoDBConfig
    private let session: URLSession

    init(config: NocoDBConfig, timeout: TimeInterval) {
        self.config = config
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = timeout
        sessionConfig.timeoutIntervalForResource = timeout
        sessionConfig.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        session = URLSession(configuration: sessionConfig)
    }

    // MARK: - Reads

    /// Open TODOs due today or earlier, highest priority first.
    ///
    /// Notes on the filter, all deliberate:
    /// * `Done` is `1`, `0` **or** null in this table, so open is `Done != 1`.
    /// * `Kategoria` is a MultiSelect — `anyof` keeps rows tagged `Kiedyś,TODO`.
    /// * `Deadine <= today` excludes future *and* undated rows by design.
    func fetchTodayTasks(completion: @escaping (Result<[NocoDBTask], NocoDBError>) -> Void) {
        guard var components = URLComponents(string: recordsURL) else {
            return completion(.failure(.malformedResponse))
        }
        let today = Self.dayFormatter.string(from: Date())
        components.queryItems = [
            URLQueryItem(name: "where",
                         value: "(Done,neq,1)~and(Kategoria,anyof,TODO)~and(Deadine,le,exactDate,\(today))"),
            URLQueryItem(name: "sort", value: "-Priority,Id"),
            URLQueryItem(name: "limit", value: "200"),
            URLQueryItem(name: "fields", value: "Id,Title,Deadine,Priority"),
        ]
        guard let url = components.url else { return completion(.failure(.malformedResponse)) }

        send(request(url, method: "GET")) { result in
            completion(result.flatMap { data in
                guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rows = root["list"] as? [[String: Any]] else {
                    return .failure(.malformedResponse)
                }
                // Re-sort locally: the table's Priority is frequently null, and
                // the server's ordering of nulls is not something to rely on.
                let tasks = rows.compactMap(Self.task(from:)).sorted {
                    $0.priority != $1.priority ? $0.priority > $1.priority : $0.id < $1.id
                }
                return .success(tasks)
            })
        }
    }

    // MARK: - Writes

    /// Create a task from the dialog's "Other" field, using the same defaults
    /// as ~/bin/note_nocodb.sh so both entry points produce identical rows.
    func createTask(title: String, completion: @escaping (Result<NocoDBTask, NocoDBError>) -> Void) {
        guard let url = URL(string: recordsURL) else {
            return completion(.failure(.malformedResponse))
        }
        let today = Date()
        let body: [String: Any] = [
            "Title": title,
            "Deadine": Self.dayFormatter.string(from: today),
            "Kategoria": "TODO",
            "Priority": 0,
            "Komentarz": NSNull(),
            "Done": NSNull(),
        ]
        var req = request(url, method: "POST")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        send(req) { result in
            completion(result.flatMap { data in
                guard let id = Self.identifier(in: data) else { return .failure(.malformedResponse) }
                return .success(NocoDBTask(id: id, title: title,
                                           deadline: Calendar.current.startOfDay(for: today),
                                           priority: 0))
            })
        }
    }

    /// Put `line` at the top of the task's `Komentarz`, keeping what was there.
    /// Read-then-write: NocoDB has no append primitive.
    func prependComment(taskID: Int, line: String,
                        completion: @escaping (Result<Void, NocoDBError>) -> Void) {
        guard var components = URLComponents(string: "\(recordsURL)/\(taskID)") else {
            return completion(.failure(.malformedResponse))
        }
        components.queryItems = [URLQueryItem(name: "fields", value: "Id,Komentarz")]
        guard let readURL = components.url, let writeURL = URL(string: recordsURL) else {
            return completion(.failure(.malformedResponse))
        }

        send(request(readURL, method: "GET")) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let data):
                let row = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let existing = (row?["Komentarz"] as? String) ?? ""
                let merged = existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? line : "\(line)\n\n\(existing)"

                var req = self.request(writeURL, method: "PATCH")
                req.httpBody = try? JSONSerialization.data(
                    withJSONObject: ["Id": taskID, "Komentarz": merged])
                self.send(req) { completion($0.map { _ in () }) }
            }
        }
    }

    // MARK: - Internals

    private var recordsURL: String {
        "\(config.apiURL)/api/v2/tables/\(config.tableID)/records"
    }

    private func request(_ url: URL, method: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(config.token, forHTTPHeaderField: "xc-token")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    private func send(_ request: URLRequest,
                      completion: @escaping (Result<Data, NocoDBError>) -> Void) {
        session.dataTask(with: request) { data, response, error in
            if let error {
                return completion(.failure(.transport(error.localizedDescription)))
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                return completion(.failure(.http(status: status, body: String(body.prefix(300)))))
            }
            completion(.success(data ?? Data()))
        }.resume()
    }

    /// Create/patch replies are `{"Id": 123}`, sometimes wrapped in an array.
    private static func identifier(in data: Data) -> Int? {
        let json = try? JSONSerialization.jsonObject(with: data)
        if let row = json as? [String: Any] { return row["Id"] as? Int }
        if let rows = json as? [[String: Any]] { return rows.first?["Id"] as? Int }
        return nil
    }

    private static func task(from row: [String: Any]) -> NocoDBTask? {
        guard let id = row["Id"] as? Int, let title = row["Title"] as? String else { return nil }
        let deadline = (row["Deadine"] as? String).flatMap { dayFormatter.date(from: $0) }
        return NocoDBTask(id: id, title: title, deadline: deadline,
                          priority: row["Priority"] as? Int ?? 0)
    }

    /// NocoDB date columns are plain `yyyy-MM-dd`, read in the local calendar.
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd.MM"
        return formatter
    }()
}
