import Foundation
import Supabase

/// Single shared Supabase client, used for sign-in only (Supabase Auth). Every game call goes to the
/// Find Me! server (`GoAPI`), which holds the game rules.
enum Supa {
    static let client: SupabaseClient = {
        let url = AppConfig.supabaseURL ?? URL(string: "https://not-configured.invalid")!
        let key = AppConfig.supabaseAnonKey ?? "not-configured"
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                db: .init(encoder: JSONCoding.encoder, decoder: JSONCoding.decoder),
                auth: .init(
                    redirectToURL: AppConfig.authCallbackURL,
                    flowType: .pkce,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }()

    static var currentUserId: UUID? { client.auth.currentUser?.id }
}

/// snake_case <-> camelCase JSON plus tolerant Postgres timestamp parsing.
enum JSONCoding {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = PostgresDate.parse(s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date: \(s)")
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(PostgresDate.format(date))
        }
        return e
    }()
}

enum PostgresDate {
    /// Accepts "2026-11-03T15:48:26.457123+00:00", "2026-11-03 15:48:26+00", "...Z", etc.
    static func parse(_ raw: String) -> Date? {
        var s = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "T")
        // "+00" -> "+00:00"
        if let r = s.range(of: #"[+-]\d{2}$"#, options: .regularExpression) {
            s.replaceSubrange(r, with: s[r] + ":00")
        }
        // Trim fractional seconds to milliseconds (ISO8601DateFormatter handles 3 digits reliably).
        if let r = s.range(of: #"\.\d+"#, options: .regularExpression) {
            let frac = s[r].dropFirst()
            let ms = String(frac.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            s.replaceSubrange(r, with: "." + ms)
            return fractional().date(from: s)
        }
        return plain().date(from: s)
    }

    static func format(_ date: Date) -> String { fractional().string(from: date) }

    private static func fractional() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    private static func plain() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }
}
