import Combine
import Foundation

enum CacheError: Error, LocalizedError {
    case typeMismatch

    var errorDescription: String? {
        switch self {
        case .typeMismatch: "Cache type mismatch."
        }
    }
}

/// Manages caching of zones and records with TTL support
@MainActor
class CacheManager: ObservableObject {
    static let shared = CacheManager()

    // MARK: - Cache Storage

    private let memoryCache = NSCache<NSString, MemoryCacheItem>()

    // MARK: - Request Deduplication

    private var ongoingRequests: [String: Task<Any, Error>] = [:]

    // MARK: - Configuration

    private let defaultZonesTTL: TimeInterval = 30 * 60 // 30 minutes
    private let defaultRecordsTTL: TimeInterval = 5 * 60 // 5 minutes

    private init() {
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 10 * 1024 * 1024 // 10MB
    }

    // MARK: - Generic Cache Operations

    /// Retrieve cached data if valid (works with any type)
    func get<T>(_ type: T.Type, key: String) -> T? {
        if let item = memoryCache.object(forKey: NSString(string: key)),
           !item.isExpired
        {
            return item.data as? T
        }

        return nil
    }

    /// Store data in cache with specified TTL (works with any type)
    func set(_ value: some Any, key: String, ttl: TimeInterval? = nil) {
        guard SettingsManager.shared.enableCache else { return }

        let actualTTL = ttl ?? defaultTTL(for: key)
        let item = MemoryCacheItem(data: value, timestamp: Date(), ttl: actualTTL)

        memoryCache.setObject(item, forKey: NSString(string: key))
    }

    /// Invalidate specific cache entry
    func invalidate(key: String) {
        memoryCache.removeObject(forKey: NSString(string: key))
    }

    /// Invalidate all cache entries for an environment
    func invalidateEnvironment(environmentId: UUID) {
        let prefix = "\(environmentId.uuidString)|"

        let keysToRemove = ongoingRequests.keys.filter { $0.hasPrefix(prefix) }
        for key in keysToRemove {
            ongoingRequests.removeValue(forKey: key)
            memoryCache.removeObject(forKey: NSString(string: key))
        }
    }

    /// Clear all cached data
    func clearAll() {
        memoryCache.removeAllObjects()
    }

    // MARK: - Request Deduplication

    /// Execute a request only once if multiple callers request the same data
    func deduplicate<T>(
        key: String,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        if let existingTask = ongoingRequests[key] {
            do {
                let result = try await existingTask.value
                guard let typedResult = result as? T else {
                    ongoingRequests.removeValue(forKey: key)
                    throw CacheError.typeMismatch
                }
                return typedResult
            } catch {
                ongoingRequests.removeValue(forKey: key)
                throw error
            }
        }

        let task = Task<Any, Error> {
            try await operation()
        }

        ongoingRequests[key] = task

        do {
            let result = try await task.value
            ongoingRequests.removeValue(forKey: key)
            guard let typedResult = result as? T else {
                throw CacheError.typeMismatch
            }
            return typedResult
        } catch {
            ongoingRequests.removeValue(forKey: key)
            throw error
        }
    }

    // MARK: - Cache Key Helpers

    /// Generate cache key for zones in an environment
    func zonesKey(environmentId: UUID) -> String {
        "\(environmentId.uuidString)|zones"
    }

    /// Generate cache key for records in a zone
    func recordsKey(environmentId: UUID, zoneId: String) -> String {
        "\(environmentId.uuidString)|\(zoneId)|records"
    }

    // MARK: - Private Methods

    private func defaultTTL(for key: String) -> TimeInterval {
        if key.contains("|zones") {
            return defaultZonesTTL
        } else if key.contains("|records") {
            return defaultRecordsTTL
        }
        return defaultRecordsTTL
    }
}

// MARK: - Cache Item Wrapper for NSCache

private class MemoryCacheItem: NSObject {
    let data: Any
    let timestamp: Date
    let ttl: TimeInterval

    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > ttl
    }

    init(data: Any, timestamp: Date, ttl: TimeInterval) {
        self.data = data
        self.timestamp = timestamp
        self.ttl = ttl
        super.init()
    }
}
