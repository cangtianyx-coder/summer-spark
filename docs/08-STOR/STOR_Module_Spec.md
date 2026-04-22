# STOR Module Specification

## 1. Module Overview

The STOR (Storage) module provides persistent data storage for the Summer Spark mesh networking application. It handles SQLite database operations, encrypted caching, and group management with end-to-end encryption support.

**Directory**: `src/Modules/Storage/`

### Components

| Component | File | Description |
|-----------|------|-------------|
| DatabaseManager | DatabaseManager.swift | SQLite database, schema management, migrations |
| EncryptedCache | EncryptedCache.swift | AES-GCM encrypted cache with LRU eviction |
| GroupStore | GroupStore.swift | Group/team management with encrypted group keys |

---

## 2. DatabaseManager API

### DatabaseError

```swift
enum DatabaseError: Error, LocalizedError {
    case openFailed(String)
    case executeFailed(String)
    case queryFailed(String)
    case migrationFailed(String, Int)
    case transactionFailed(String)
    case notInitialized
}
```

### Delegate Protocol

```swift
protocol DatabaseManagerDelegate: AnyObject {
    func databaseManagerDidMigrate(_ manager: DatabaseManager, from oldVersion: Int, to newVersion: Int)
    func databaseManager(_ manager: DatabaseManager, didEncounterError error: DatabaseError)
}
```

### TableSchema

```swift
struct TableSchema {
    let name: String
    let columns: [ColumnDefinition]
    let primaryKey: String?
    
    struct ColumnDefinition {
        let name: String
        let type: String
        let notNull: Bool
        let defaultValue: String?
        let unique: Bool
    }
    
    func createSQL() -> String
}
```

### Migration

```swift
struct Migration {
    let version: Int
    let upSQL: [String]
    let downSQL: [String]
}
```

### Database Schemas

#### nodes Table

```sql
CREATE TABLE nodes (
    id TEXT NOT NULL UNIQUE PRIMARY KEY,
    public_key BLOB,
    display_name TEXT,
    last_seen REAL,
    trust_score REAL DEFAULT 0.5,
    is_trusted INTEGER DEFAULT 0,
    signature BLOB,
    created_at REAL
);
```

#### sessions Table

```sql
CREATE TABLE sessions (
    id TEXT NOT NULL UNIQUE PRIMARY KEY,
    node_id TEXT NOT NULL,
    started_at REAL,
    ended_at REAL,
    data_transferred INTEGER DEFAULT 0
);
```

#### messages Table

```sql
CREATE TABLE messages (
    id TEXT NOT NULL UNIQUE PRIMARY KEY,
    session_id TEXT,
    sender_id TEXT,
    encrypted_content BLOB,
    timestamp REAL,
    is_delivered INTEGER DEFAULT 0
);
```

#### credentials Table

```sql
CREATE TABLE credentials (
    id INTEGER NOT NULL PRIMARY KEY,
    node_id TEXT NOT NULL,
    encrypted_key BLOB,
    label TEXT,
    created_at REAL
);
```

#### audit_log Table

```sql
CREATE TABLE audit_log (
    id INTEGER NOT NULL PRIMARY KEY,
    action TEXT,
    node_id TEXT,
    timestamp REAL,
    details TEXT
);
```

### Class: DatabaseManager (Singleton)

```swift
final class DatabaseManager {
    static let shared = DatabaseManager()
    
    weak var delegate: DatabaseManagerDelegate?
    
    var databasePath: URL? { get }
    var isInitialized: Bool { get }
    
    // Lifecycle
    func initialize() throws
    func close()
    
    // CRUD Operations
    func execute(_ sql: String, parameters: [Any]? = nil) throws
    func query(_ sql: String, parameters: [Any]? = nil) throws -> [[String: Any]]
    
    // Transaction
    func beginTransaction() throws
    func commit() throws
    func rollback()
    
    // Migration
    func migrate(to version: Int) throws
    func getCurrentVersion() -> Int
}
```

---

## 3. EncryptedCache API

### EncryptedCacheError

```swift
enum EncryptedCacheError: Error, LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case keyDerivationFailed
    case capacityExceeded
    case itemNotFound
    case invalidData
    case notInitialized
}
```

### CacheEntry

```swift
struct CacheEntry: Codable {
    let key: String
    let value: Data
    let createdAt: Date
    var lastAccessedAt: Date
    let size: Int64
    let nonce: Data
    
    var isExpired: Bool  // age > maxAge (7 days default)
    
    static var maxAge: TimeInterval = 7 * 24 * 60 * 60  // 7 days
}
```

### EncryptionKeyProvider Protocol

```swift
protocol EncryptionKeyProvider {
    func getEncryptionKey() throws -> SymmetricKey
}

struct DefaultKeyProvider: EncryptionKeyProvider {
    init(keyData: Data)
    func getEncryptionKey() throws -> SymmetricKey
}
```

### Configuration

```swift
struct Config {
    var maxCapacity: Int64 = 100 * 1024 * 1024   // 100MB default
    var evictionThreshold: Double = 0.8           // Evict at 80% capacity
    var maxItemAge: TimeInterval = 7 * 24 * 60 * 60  // 7 days
    var maxItemSize: Int64 = 10 * 1024 * 1024     // 10MB max per item
    var enableCompression: Bool = false
    var cacheDirectory: URL? = nil
}
```

### Class: EncryptedCache

```swift
final class EncryptedCache {
    init(config: Config = Config(), keyProvider: EncryptionKeyProvider)
    
    // Basic Operations
    func set(_ value: Data, forKey key: String) throws
    func get(_ key: String) throws -> Data
    func remove(_ key: String) throws
    func contains(_ key: String) -> Bool
    func clear() throws
    
    // Cache Info
    var currentSize: Int64 { get }
    var itemCount: Int { get }
    
    // Eviction
    func evictExpired() throws
    func evictLRU(targetSize: Int64) throws
}
```

**Encryption**: AES-GCM with unique nonce per entry  
**Eviction Policy**: LRU (Least Recently Used) when capacity exceeds threshold

---

## 4. GroupStore API

### GroupMember

```swift
struct GroupMember: Codable, Equatable {
    let uid: String
    var role: GroupRole
    let joinedAt: Date
    
    enum GroupRole: String, Codable {
        case owner
        case admin
        case member
    }
}
```

### Group

```swift
struct Group: Codable, Identifiable {
    let id: String
    var name: String
    let ownerUid: String
    var members: [GroupMember]
    var groupKey: Data?          // Symmetric key (encrypted with owner's key)
    var encryptedGroupKey: Data? // Group key encrypted for specific member
    let createdAt: Date
    var updatedAt: Date
    
    init(id: String = UUID().uuidString, name: String, ownerUid: String)
}
```

### Class: GroupStore (Singleton)

```swift
final class GroupStore {
    static let shared = GroupStore()
    
    // Group CRUD
    func createGroup(name: String, ownerUid: String) -> Group
    func getGroup(id: String) -> Group?
    func updateGroup(_ group: Group) -> Bool
    func deleteGroup(id: String) -> Bool
    
    // Member Management
    func addMember(uid: String, to groupId: String, role: GroupMember.GroupRole) -> Bool
    func removeMember(uid: String, from groupId: String) -> Bool
    func updateMemberRole(uid: String, in groupId: String, newRole: GroupMember.GroupRole) -> Bool
    
    // Group Key Management
    func setGroupKey(_ key: Data, for groupId: String) -> Bool
    func getGroupKey(for groupId: String) -> Data?
    func distributeGroupKeyToMember(groupId: String, memberUid: String) -> Data?
    
    // User Groups
    func getGroups(for uid: String) -> [Group]
    func getMemberGroups(uid: String) -> [String]  // group IDs
    
    // Queries
    func isMember(uid: String, in groupId: String) -> Bool
    func isAdmin(uid: String, in groupId: String) -> Bool
    func isOwner(uid: String, of groupId: String) -> Bool
    func getAllGroups() -> [Group]
}
```

**Persistence**: UserDefaults with JSON encoding  
**Storage Keys**:
- `groups.store` - Groups dictionary
- `groups.userGroups` - UID to group IDs mapping

---

## 5. Configuration Defaults

| Parameter | Default Value |
|-----------|---------------|
| EncryptedCache Max Capacity | 100 MB |
| EncryptedCache Eviction Threshold | 80% |
| EncryptedCache Max Item Age | 7 days |
| EncryptedCache Max Item Size | 10 MB |
| EncryptedCache Compression | Disabled |

---

## 6. Thread Safety

- **DatabaseManager**: Uses serial DispatchQueue (`dbQueue`) for all operations
- **EncryptedCache**: Uses internal synchronization for thread-safe access
- **GroupStore**: Thread-safe with internal locking for concurrent reads/writes

---

## 7. Encryption Details

### EncryptedCache

- **Algorithm**: AES-256-GCM
- **Key Derivation**: Direct key usage (key provider supplies SymmetricKey)
- **Nonce**: Unique per cache entry, stored with entry
- **Authentication**: GCM provides authenticated encryption

### GroupStore

- **Group Key**: AES-256 symmetric key generated per group
- **Key Storage**: Encrypted with owner's key before persistence
- **Key Distribution**: Re-encrypted for each member using member's public key

---

## 8. Dependencies

- **Framework**: Foundation, CryptoKit, SQLite3
- **Internal Dependencies**: None (standalone module)
- **External Dependencies**: SQLite3 (system library)

---

## 9. Database Version History

| Version | Description |
|---------|-------------|
| 1 | Initial schema (nodes, sessions, messages, credentials, audit_log) |

Migrations are stored in `DatabaseManager` and applied sequentially.

---

## 10. Error Handling

All errors are reported via:

- **DatabaseManager**: Throws `DatabaseError` via delegate
- **EncryptedCache**: Throws `EncryptedCacheError` from all public methods
- **GroupStore**: Returns `nil` or `false` for failed operations, no exception thrown