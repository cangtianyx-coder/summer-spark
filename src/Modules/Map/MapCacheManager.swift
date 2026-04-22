import Foundation
import SQLite3

final class MapCacheManager {

    static let shared = MapCacheManager()

    // MARK: - Configuration

    private let maxCacheSize: Int64 = 500 * 1024 * 1024 // 500MB
    private let preloadBatchSize: Int = 20
    private let cacheDirectory: URL

    // MARK: - LRU Cache

    private var accessOrder: [String] = []
    private var cacheData: [String: Data] = [:]
    private var cacheSizes: [String: Int64] = [:]
    private var currentCacheSize: Int64 = 0

    private let cacheLock = NSLock()

    // MARK: - SQLite Metadata

    private var db: OpaquePointer?
    private let dbPath: URL

    // MARK: - Statistics

    private var hitCount: Int64 = 0
    private var missCount: Int64 = 0
    private var preloadCount: Int64 = 0
    
    // MARK: - Operation Queue
    
    let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.map.cache.operations"
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .userInitiated
        return queue
    }()

    // MARK: - Preload Queue

    private var preloadQueue: [String] = []
    private let preloadLock = NSLock()
    private var preloadTask: DispatchWorkItem?

    // MARK: - Initialization

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("MapCache", isDirectory: true)
        dbPath = cacheDirectory.appendingPathComponent("cache_metadata.sqlite")

        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        openDatabase()
        loadMetadata()
        startPreloadTimer()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Database

    private func openDatabase() {
        if sqlite3_open(dbPath.path, &db) != SQLITE_OK {
            print("MapCacheManager: Failed to open database at \(dbPath.path)")
            db = nil
            return
        }

        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS cache_entries (
            key TEXT PRIMARY KEY,
            size INTEGER NOT NULL,
            last_accessed REAL NOT NULL,
            access_count INTEGER DEFAULT 0,
            preloaded INTEGER DEFAULT 0,
            created_at REAL NOT NULL
        );
        """
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, createTableSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    private func loadMetadata() {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        let query = "SELECT key, size, last_accessed, access_count FROM cache_entries ORDER BY last_accessed ASC"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let keyPtr = sqlite3_column_text(statement, 0),
                  let sizePtr = sqlite3_column_text(statement, 1) else { continue }

            let key = String(cString: keyPtr)
            let sizeText = String(cString: sizePtr)
            let size = Int64(sizeText) ?? 0

            accessOrder.append(key)
            cacheSizes[key] = size
            currentCacheSize += size
        }
        sqlite3_finalize(statement)
    }

    private func updateMetadata(for key: String, size: Int64, preloaded: Bool = false) {
        let upsertSQL = """
        INSERT INTO cache_entries (key, size, last_accessed, access_count, preloaded, created_at)
        VALUES (?, ?, ?, 1, ?, ?)
        ON CONFLICT(key) DO UPDATE SET
            size = excluded.size,
            last_accessed = excluded.last_accessed,
            access_count = access_count + 1;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, upsertSQL, -1, &statement, nil) == SQLITE_OK else { return }

        sqlite3_bind_text(statement, 1, key, -1, nil)
        sqlite3_bind_int64(statement, 2, size)
        sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)
        sqlite3_bind_int(statement, 4, preloaded ? 1 : 0)
        sqlite3_bind_double(statement, 5, Date().timeIntervalSince1970)

        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    private func removeMetadata(for key: String) {
        let deleteSQL = "DELETE FROM cache_entries WHERE key = ?"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK else { return }

        sqlite3_bind_text(statement, 1, key, -1, nil)
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    // MARK: - Cache Operations

    func get(key: String) -> Data? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        guard let data = cacheData[key] else {
            missCount += 1
            return nil
        }

        // Update LRU order
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
            accessOrder.append(key)
        }

        hitCount += 1
        return data
    }

    func set(key: String, data: Data) {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        let size = Int64(data.count)

        // Remove existing entry if present
        if cacheData[key] != nil {
            remove(key: key, locked: true)
        }

        // Evict if necessary to make room
        while currentCacheSize + size > maxCacheSize && !accessOrder.isEmpty {
            evictLRU(locked: true)
        }

        cacheData[key] = data
        accessOrder.append(key)
        cacheSizes[key] = size
        currentCacheSize += size

        updateMetadata(for: key, size: size)
    }

    func remove(key: String, locked: Bool = false) {
        if !locked { cacheLock.lock() }
        defer { if !locked { cacheLock.unlock() } }

        guard let _ = cacheData[key] else { return }

        cacheData.removeValue(forKey: key)
        accessOrder.removeAll { $0 == key }
        if let size = cacheSizes[key] {
            currentCacheSize -= size
            cacheSizes.removeValue(forKey: key)
        }

        removeMetadata(for: key)
    }

    private func evictLRU(locked: Bool) {
        if !locked { cacheLock.lock() }
        defer { if !locked { cacheLock.unlock() } }

        guard let oldestKey = accessOrder.first else { return }

        cacheData.removeValue(forKey: oldestKey)
        accessOrder.removeFirst()
        if let size = cacheSizes[oldestKey] {
            currentCacheSize -= size
            cacheSizes.removeValue(forKey: oldestKey)
        }

        removeMetadata(for: oldestKey)
    }

    // MARK: - Preloading

    func queuePreload(keys: [String]) {
        preloadLock.lock()
        defer { preloadLock.unlock() }

        preloadQueue.append(contentsOf: keys)
    }

    func startPreload() {
        preloadLock.lock()
        let keys = Array(preloadQueue.prefix(preloadBatchSize))
        preloadQueue.removeFirst(min(preloadBatchSize, preloadQueue.count))
        preloadLock.unlock()

        guard !keys.isEmpty else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            for key in keys {
                self?.preloadTile(key: key)
            }
        }
    }

    private func preloadTile(key: String) {
        cacheLock.lock()
        let exists = cacheData[key] != nil
        cacheLock.unlock()

        guard !exists else { return }

        // Simulate tile loading - replace with actual tile loading logic
        guard let data = loadTileFromDisk(key: key) else { return }

        cacheLock.lock()
        let size = Int64(data.count)

        while currentCacheSize + size > maxCacheSize && !accessOrder.isEmpty {
            evictLRU(locked: true)
        }

        cacheData[key] = data
        accessOrder.append(key)
        cacheSizes[key] = size
        currentCacheSize += size

        updateMetadata(for: key, size: size, preloaded: true)

        cacheLock.unlock()

        preloadLock.lock()
        preloadCount += 1
        preloadLock.unlock()
    }

    private func loadTileFromDisk(key: String) -> Data? {
        let fileURL = cacheDirectory.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_"))
        return try? Data(contentsOf: fileURL)
    }

    private func startPreloadTimer() {
        preloadTask = DispatchWorkItem { [weak self] in
            self?.startPreload()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0, execute: {
                self?.startPreloadTimer()
            })
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0, execute: preloadTask!)
    }

    // MARK: - Statistics

    struct CacheStatistics {
        let hitCount: Int64
        let missCount: Int64
        let hitRate: Double
        let preloadCount: Int64
        let currentCacheSize: Int64
        let maxCacheSize: Int64
        let cachedTileCount: Int
    }

    func getStatistics() -> CacheStatistics {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        let total = hitCount + missCount
        let hitRate = total > 0 ? Double(hitCount) / Double(total) : 0.0

        preloadLock.lock()
        let preload = preloadCount
        preloadLock.unlock()

        return CacheStatistics(
            hitCount: hitCount,
            missCount: missCount,
            hitRate: hitRate,
            preloadCount: preload,
            currentCacheSize: currentCacheSize,
            maxCacheSize: maxCacheSize,
            cachedTileCount: cacheData.count
        )
    }

    func resetStatistics() {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        hitCount = 0
        missCount = 0

        preloadLock.lock()
        preloadCount = 0
        preloadLock.unlock()
    }

    // MARK: - Cache Management

    func clearCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        cacheData.removeAll()
        accessOrder.removeAll()
        cacheSizes.removeAll()
        currentCacheSize = 0

        let deleteAllSQL = "DELETE FROM cache_entries"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteAllSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    func compactCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        let targetSize = Int64(Double(maxCacheSize) * 0.7)

        while currentCacheSize > targetSize && !accessOrder.isEmpty {
            evictLRU(locked: true)
        }
    }
}
