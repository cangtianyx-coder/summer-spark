import Foundation
import CryptoKit

// MARK: - EncryptedCacheError

enum EncryptedCacheError: Error, LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case keyDerivationFailed
    case capacityExceeded
    case itemNotFound
    case invalidData
    case notInitialized

    var errorDescription: String? {
        switch self {
        case .encryptionFailed: return "加密失败"
        case .decryptionFailed: return "解密失败"
        case .keyDerivationFailed: return "密钥派生失败"
        case .capacityExceeded: return "缓存容量已满"
        case .itemNotFound: return "缓存项不存在"
        case .invalidData: return "数据无效"
        case .notInitialized: return "加密缓存未初始化"
        }
    }
}

// MARK: - CacheEntry

struct CacheEntry: Codable {
    let key: String
    let value: Data
    let createdAt: Date
    var lastAccessedAt: Date
    let size: Int64
    let nonce: Data

    var isExpired: Bool {
        return Date().timeIntervalSince(createdAt) > CacheEntry.maxAge
    }

    static var maxAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days default
}

// MARK: - EncryptionKeyProvider

protocol EncryptionKeyProvider {
    func getEncryptionKey() throws -> SymmetricKey
}

// MARK: - DefaultKeyProvider

struct DefaultKeyProvider: EncryptionKeyProvider {
    private let keyData: Data

    init(keyData: Data) {
        self.keyData = keyData
    }

    func getEncryptionKey() throws -> SymmetricKey {
        return SymmetricKey(data: keyData)
    }
}

// MARK: - EncryptedCache

final class EncryptedCache {

    // MARK: - Configuration

    struct Config {
        public var maxCapacity: Int64 = 100 * 1024 * 1024 // 100MB default
        public var evictionThreshold: Double = 0.8 // Evict when 80% full
        public var maxItemAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
        public var maxItemSize: Int64 = 10 * 1024 * 1024 // 10MB max per item
        public var enableCompression: Bool = false
        public var cacheDirectory: URL? = nil

        public init() {}
    }

    // MARK: - Properties

    private let queue = DispatchQueue(label: "com.encryptedcache", qos: .userInitiated, attributes: .concurrent)
    private let keyProvider: EncryptionKeyProvider
    private let config: Config

    private var cacheEntries: [String: CacheEntry] = [:]
    private var accessOrder: [String] = [] // LRU tracking
    private var currentSize: Int64 = 0

    private var persistencePath: URL?
    private let fileManager = FileManager.default

    private var hitCount: Int = 0
    private var missCount: Int = 0

    // MARK: - Initialization

    init(keyProvider: EncryptionKeyProvider, config: Config = Config()) {
        self.keyProvider = keyProvider
        self.config = config

        if let customDir = config.cacheDirectory {
            self.persistencePath = customDir.appendingPathComponent("EncryptedCache", isDirectory: true)
        } else {
            guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                fatalError("EncryptedCache: Failed to get caches directory")
            }
            self.persistencePath = caches.appendingPathComponent("EncryptedCache", isDirectory: true)
        }

        setupCacheDirectory()
        loadFromDisk()
    }

    private func setupCacheDirectory() {
        guard let path = persistencePath else { return }
        try? fileManager.createDirectory(at: path, withIntermediateDirectories: true)
        
        // 设置缓存目录的文件保护级别
        setFileProtectionLevel()
    }
    
    /// 设置缓存目录的文件保护级别
    /// 使用 completeUnlessOpen：文件打开时可读写，关闭后需解锁设备才能访问
    private func setFileProtectionLevel() {
        guard let cachePath = persistencePath else { return }
        
        do {
            // 设置缓存目录保护级别
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen],
                ofItemAtPath: cachePath.path
            )
            
            // 为目录中所有现有文件设置保护级别
            let files = try fileManager.contentsOfDirectory(
                at: cachePath,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            
            for file in files {
                try fileManager.setAttributes(
                    [.protectionKey: FileProtectionType.completeUnlessOpen],
                    ofItemAtPath: file.path
                )
            }
            
            Logger.shared.info("缓存目录文件保护级别已设置为 completeUnlessOpen")
        } catch {
            Logger.shared.error("设置缓存目录文件保护级别失败: \(error)")
        }
    }

    // MARK: - Public Interface

    /// Store encrypted data in cache
    func set(_ key: String, data: Data) throws {
        guard !data.isEmpty else { return }
        guard Int64(data.count) <= config.maxItemSize else {
            throw EncryptedCacheError.capacityExceeded
        }

        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            do {
                try self.performSet(key: key, data: data)
            } catch {
                Logger.shared.error("EncryptedCache set error: \(error)")
            }
        }
    }

    /// Retrieve and decrypt data from cache
    func get(_ key: String) throws -> Data? {
        var result: Data?
        var error: Error?

        queue.sync {
            do {
                result = try self.performGet(key: key)
            } catch let e {
                error = e
            }
        }

        if let err = error { throw err }
        return result
    }

    /// Remove item from cache
    func remove(_ key: String) {
        queue.async(flags: .barrier) { [weak self] in
            self?.performRemove(key: key)
        }
    }

    /// Check if key exists
    func contains(_ key: String) -> Bool {
        var exists = false
        queue.sync {
            exists = self.cacheEntries[key] != nil
        }
        return exists
    }

    /// Clear all cached data
    func clear() {
        queue.async(flags: .barrier) { [weak self] in
            self?.performClear()
        }
    }

    // MARK: - Private Operations

    private func performSet(key: String, data: Data) throws {
        // Remove existing entry first
        if let existing = cacheEntries[key] {
            currentSize -= existing.size
            accessOrder.removeAll { $0 == key }
        }

        // Evict if necessary to make room
        let itemSize = Int64(data.count)
        let targetSize = Int64(Double(config.maxCapacity) * config.evictionThreshold)

        while currentSize + itemSize > config.maxCapacity && !accessOrder.isEmpty {
            evictLRU()
        }

        // Also check against target threshold
        while currentSize + itemSize > targetSize && !accessOrder.isEmpty && currentSize > 0 {
            evictLRU()
        }

        // Encrypt data
        let encrypted = try encrypt(data)

        // Create cache entry
        let entry = CacheEntry(
            key: key,
            value: encrypted,
            createdAt: Date(),
            lastAccessedAt: Date(),
            size: itemSize,
            nonce: encrypted.prefix(12) // GCM nonce is 12 bytes
        )

        cacheEntries[key] = entry
        accessOrder.append(key)
        currentSize += itemSize

        // Persist to disk
        persistEntry(entry)

        // Update access order for LRU
        updateLRU(key: key)
    }

    private func performGet(key: String) throws -> Data? {
        guard let entry = cacheEntries[key] else {
            missCount += 1
            return nil
        }

        // Check expiration
        if Date().timeIntervalSince(entry.createdAt) > config.maxItemAge {
            performRemove(key: key)
            missCount += 1
            return nil
        }

        hitCount += 1
        updateLRU(key: key)

        // Decrypt
        return try decrypt(entry.value)
    }

    private func performRemove(key: String) {
        guard let entry = cacheEntries[key] else { return }

        cacheEntries.removeValue(forKey: key)
        accessOrder.removeAll { $0 == key }
        currentSize -= entry.size

        // Remove from disk
        removeFromDisk(key: key)
    }

    private func performClear() {
        cacheEntries.removeAll()
        accessOrder.removeAll()
        currentSize = 0

        // Clear disk cache
        if let path = persistencePath {
            try? fileManager.removeItem(at: path)
            setupCacheDirectory()
        }
    }

    // MARK: - LRU Eviction

    private func evictLRU() {
        guard let oldestKey = accessOrder.first else { return }

        if let entry = cacheEntries[oldestKey] {
            currentSize -= entry.size
            cacheEntries.removeValue(forKey: oldestKey)
            accessOrder.removeFirst()
            removeFromDisk(key: oldestKey)
        }
    }

    private func updateLRU(key: String) {
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
            accessOrder.append(key)
        }
    }

    // MARK: - Encryption (AES-256-GCM)

    private func encrypt(_ data: Data) throws -> Data {
        let key = try keyProvider.getEncryptionKey()
        let nonce = AES.GCM.Nonce()

        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)

        guard let combined = sealedBox.combined else {
            throw EncryptedCacheError.encryptionFailed
        }

        return combined
    }

    private func decrypt(_ combinedData: Data) throws -> Data {
        let key = try keyProvider.getEncryptionKey()

        let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)

        return decryptedData
    }

    // MARK: - Persistence

    private func persistEntry(_ entry: CacheEntry) {
        guard let basePath = persistencePath else { return }

        let filePath = basePath.appendingPathComponent(sanitizedKey(entry.key) + ".cache")

        do {
            let data = try JSONEncoder().encode(entry)
            try data.write(to: filePath)
            
            // 设置新写入文件的文件保护级别
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen],
                ofItemAtPath: filePath.path
            )
        } catch {
            Logger.shared.error("Failed to persist cache entry: \(error)")
        }
    }

    private func removeFromDisk(key: String) {
        guard let basePath = persistencePath else { return }

        let filePath = basePath.appendingPathComponent(sanitizedKey(key) + ".cache")
        try? fileManager.removeItem(at: filePath)
    }

    private func loadFromDisk() {
        guard let basePath = persistencePath else { return }

        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            do {
                let files = try self.fileManager.contentsOfDirectory(at: basePath, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)

                for file in files where file.pathExtension == "cache" {
                    if let data = try? Data(contentsOf: file),
                       let entry = try? JSONDecoder().decode(CacheEntry.self, from: data) {
                        self.cacheEntries[entry.key] = entry
                        self.accessOrder.append(entry.key)
                        self.currentSize += entry.size
                    }
                }

                // Sort access order by last accessed
                self.accessOrder.sort { k1, k2 in
                    let e1 = self.cacheEntries[k1]
                    let e2 = self.cacheEntries[k2]
                    return (e1?.lastAccessedAt ?? Date.distantPast) < (e2?.lastAccessedAt ?? Date.distantPast)
                }
            } catch {
                Logger.shared.error("Failed to load cache from disk: \(error)")
            }
        }
    }

    private func sanitizedKey(_ key: String) -> String {
        // Replace problematic characters for file names
        return key.replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: ":", with: "_")
                    .replacingOccurrences(of: " ", with: "_")
    }

    // MARK: - Statistics

    struct CacheStatistics {
        let hitCount: Int
        let missCount: Int
        let hitRate: Double
        let currentSize: Int64
        let maxCapacity: Int64
        let usageRatio: Double
        let itemCount: Int
    }

    func getStatistics() -> CacheStatistics {
        var stats: CacheStatistics?

        queue.sync {
            let total = hitCount + missCount
            let hitRate = total > 0 ? Double(hitCount) / Double(total) : 0.0
            let usage = Double(currentSize) / Double(config.maxCapacity)

            stats = CacheStatistics(
                hitCount: hitCount,
                missCount: missCount,
                hitRate: hitRate,
                currentSize: currentSize,
                maxCapacity: config.maxCapacity,
                usageRatio: usage,
                itemCount: cacheEntries.count
            )
        }

        return stats ?? CacheStatistics(hitCount: 0, missCount: 0, hitRate: 0, currentSize: 0, maxCapacity: 0, usageRatio: 0, itemCount: 0)
    }

    func resetStatistics() {
        queue.async(flags: .barrier) { [weak self] in
            self?.hitCount = 0
            self?.missCount = 0
        }
    }

    // MARK: - Batch Operations

    func setMultiple(_ items: [String: Data]) {
        for (key, data) in items {
            do {
                try set(key, data: data)
            } catch {
                Logger.shared.error("Failed to cache \(key): \(error)")
            }
        }
    }

    func getAll(_ keys: [String]) -> [String: Data?] {
        var results: [String: Data?] = [:]

        for key in keys {
            if let data = try? get(key) {
                results[key] = data
            } else {
                results[key] = nil
            }
        }

        return results
    }

    func removeMultiple(_ keys: [String]) {
        for key in keys {
            remove(key)
        }
    }

    // MARK: - Maintenance

    func compact() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let targetSize = Int64(Double(self.config.maxCapacity) * self.config.evictionThreshold)

            while self.currentSize > targetSize && !self.accessOrder.isEmpty {
                self.evictLRU()
            }
        }
    }

    func cleanupExpired() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let now = Date()
            let expiredKeys = self.cacheEntries.filter { _, entry in
                now.timeIntervalSince(entry.createdAt) > self.config.maxItemAge
            }.map { $0.key }

            for key in expiredKeys {
                self.performRemove(key: key)
            }
        }
    }
}