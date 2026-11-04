import Foundation

/// Private buckets (`proofs`, `hint-media`) are read through short-lived URLs the server signs after
/// checking the caller may see the photo.
actor SignedURLCache {
    static let shared = SignedURLCache()
    private var cache: [String: (url: URL, expires: Date)] = [:]
    /// The server signs for an hour; refresh a little earlier.
    private let lifetime: TimeInterval = 3300

    func url(bucket: String, path: String) async throws -> URL {
        let key = bucket + "/" + path
        if let hit = cache[key], hit.expires > Date() { return hit.url }
        let url = try await API.fileURL(bucket: bucket, path: path)
        cache[key] = (url, Date().addingTimeInterval(lifetime))
        return url
    }
}
