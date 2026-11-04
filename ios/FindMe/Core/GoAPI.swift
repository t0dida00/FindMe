import Foundation

/// Client for the Find Me! Go API (github.com/t0dida00/FindMe-Go). Every call carries the Supabase
/// access token (the Go API verifies it), and the JSON uses the same snake_case shapes as Supabase's
/// REST API, so the app's models decode it unchanged. Server errors come back as
/// `{"error":{"code":"game_full"}}` and become `GoAPI.Failure`, which `AppError` maps to messages
/// exactly like SQL error codes.
enum GoAPI {
    /// Which backend serves data. Set GO_API_URL in Config/Secrets.xcconfig to use the Go API; leave it
    /// empty to talk to Supabase directly (the shipped behaviour).
    static var isEnabled: Bool { AppConfig.goAPIURL != nil }

    /// A failed call: the server's stable error code (`game_full`, `not_found`…) and HTTP status.
    struct Failure: LocalizedError, Sendable {
        let code: String
        let status: Int
        var errorDescription: String? { AppError.message(code: code) ?? code }
    }

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    /// Long-lived SSE connections: no overall deadline; the server pings every 25 s, so 60 s of
    /// silence means the connection is dead.
    static let streamSession: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 7 * 24 * 3600
        return URLSession(configuration: c)
    }()

    static func url(_ path: String, query: [String: String] = [:]) throws -> URL {
        guard let base = AppConfig.goAPIURL else { throw Failure(code: "not_configured", status: 0) }
        var c = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return c.url!
    }

    static func request(_ method: String, _ path: String, query: [String: String] = [:], body: Data? = nil) async throws -> URLRequest {
        var r = URLRequest(url: try url(path, query: query))
        r.httpMethod = method
        let token = try await Supa.client.auth.session.accessToken // refreshed by supabase-swift when needed
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            r.httpBody = body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    /// Sends a request and returns the body; throws `Failure` for non-2xx answers.
    @discardableResult
    static func send(_ method: String, _ path: String, query: [String: String] = [:], body: Data? = nil) async throws -> Data {
        let req = try await request(method, path, query: query, body: body)
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            struct Envelope: Decodable { struct E: Decodable { let code: String }; let error: E }
            let code = (try? JSONDecoder().decode(Envelope.self, from: data))?.error.code ?? "http_\(status)"
            throw Failure(code: code, status: status)
        }
        return data
    }

    static func get<T: Decodable>(_ path: String, query: [String: String] = [:], as: T.Type = T.self) async throws -> T {
        try JSONCoding.decoder.decode(T.self, from: try await send("GET", path, query: query))
    }

    static func write<T: Decodable>(_ method: String, _ path: String, body: some Encodable, as: T.Type = T.self) async throws -> T {
        try JSONCoding.decoder.decode(T.self, from: try await send(method, path, body: try JSONCoding.encoder.encode(body)))
    }

    static func write(_ method: String, _ path: String, body: some Encodable) async throws {
        try await send(method, path, body: try JSONCoding.encoder.encode(body))
    }

    static func write(_ method: String, _ path: String) async throws {
        try await send(method, path)
    }

    /// Reads may fall back to Supabase when the Go API is unreachable or broken (network error or
    /// 5xx). Writes never do: a retried write could apply twice.
    static func shouldFallBack(_ error: Error) -> Bool {
        if error is URLError { return true }
        if let f = error as? Failure { return f.status >= 500 || f.status == 0 }
        return false
    }

    /// Runs `go` against the Go API when enabled, else (or if it is unreachable) `supabase`.
    static func read<T>(_ go: () async throws -> T, supabase: () async throws -> T) async throws -> T {
        guard isEnabled else { return try await supabase() }
        do { return try await go() } catch where shouldFallBack(error) {
            print("GoAPI read failed, falling back to Supabase: \(error)")
            return try await supabase()
        }
    }

    /// Go first; nil when Go is off or unreachable (the caller then runs its Supabase code).
    /// Rule errors (4xx) are thrown as they are.
    static func tryRead<T>(_ go: () async throws -> T) async throws -> T? {
        guard isEnabled else { return nil }
        do { return try await go() } catch where shouldFallBack(error) {
            print("GoAPI read failed, falling back to Supabase: \(error)")
            return nil
        }
    }

    /// A single row that may not exist: 404 → nil.
    static func getOptional<T: Decodable>(_ path: String, as: T.Type) async throws -> T? {
        do { return try await get(path, as: T.self) } catch let f as Failure where f.status == 404 { return nil }
    }

    static func ids(_ list: [UUID]) -> String { list.map { $0.uuidString.lowercased() }.joined(separator: ",") }
}

/// JSON object body built from optional fields: nil values are sent as null (to clear a column).
struct JSONBody: Encodable, Sendable {
    let fields: [String: JSONValue]
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        for (k, v) in fields { try c.encode(v, forKey: Key(stringValue: k)!) }
    }
    struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
