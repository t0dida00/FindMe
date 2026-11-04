import Foundation
import Supabase

/// Private buckets (`proofs`, `hint-media`) are read through short-lived signed URLs.
actor SignedURLCache {
    static let shared = SignedURLCache()
    private var cache: [String: (url: URL, expires: Date)] = [:]
    private let lifetime = 3600

    func url(bucket: String, path: String) async throws -> URL {
        let key = bucket + "/" + path
        if let hit = cache[key], hit.expires > Date().addingTimeInterval(60) { return hit.url }
        let url = try await Supa.client.storage.from(bucket).createSignedURL(path: path, expiresIn: lifetime)
        cache[key] = (url, Date().addingTimeInterval(TimeInterval(lifetime)))
        return url
    }
}
