import Foundation
import SQLite3

// MARK: - DatabaseManagerDelegate

protocol DatabaseManagerDelegate: AnyObject {
    func databaseManagerDidMigrate(_ manager: DatabaseManager, from oldVersion: Int, to newVersion: Int)
    func databaseManager(_ manager: DatabaseManager, didEncounterError error: DatabaseError)
}

// MARK: - DatabaseError

enum DatabaseError: Error, LocalizedError {
    case openFailed(String)
    case executeFailed(String)
    case queryFailed(String)
    case migrationFailed(String, Int)
    case transactionFailed(String)
    case notInitialized

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "数据库打开失败: \(msg)"
        case .executeFailed(let msg): return "SQL执行失败: \(msg)"
        case .queryFailed(let msg): return "查询失败: \(msg)"
        case .migrationFailed(let msg, let version): return "迁移到v\(version)失败: \(msg)"
        case .transactionFailed(let msg): return "事务失败: \(msg)"
        case .notInitialized: return "数据库未初始化"
        }
    }
}

// MARK: - TableSchema

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

        init(name: String, type: String, notNull: Bool = false, defaultValue: String? = nil, unique: Bool = false) {
            self.name = name
            self.type = type
            self.notNull = notNull
            self.defaultValue = defaultValue
            self.unique = unique
        }
    }

    init(name: String, columns: [ColumnDefinition], primaryKey: String? = nil) {
        self.name = name
        self.columns = columns
        self.primaryKey = primaryKey
    }

    func createSQL() -> String {
        var parts: [String] = []
        for col in columns {
            var colStr = "\(col.name) \(col.type)"
            if col.notNull { colStr += " NOT NULL" }
            if let def = col.defaultValue { colStr += " DEFAULT \(def)" }
            if col.unique { colStr += " UNIQUE" }
            parts.append(colStr)
        }
        if let pk = primaryKey {
            parts.append("PRIMARY KEY (\(pk))")
        }
        return "CREATE TABLE IF NOT EXISTS \(name) (\(parts.joined(separator: ", ")));"
    }
}

// MARK: - Migration

struct Migration {
    let version: Int
    let upSQL: [String]
    let downSQL: [String]

    init(version: Int, up: [String], down: [String] = []) {
        self.version = version
        self.upSQL = up
        self.downSQL = down
    }
}

// MARK: - DatabaseManager

final class DatabaseManager {
    static let shared = DatabaseManager()

    // MARK: - Table Name Whitelist (SQL Injection Protection)

    /// Valid table names for SQL operations - prevents SQL injection via table name
    private static let validTableNames: Set<String> = [
        "nodes", "sessions", "messages", "credentials", "audit_log",
        "credits", "routes", "tracks", "map_tiles", "groups"
    ]

    /// Validate table name against whitelist to prevent SQL injection
    /// - Parameter name: Table name to validate
    /// - Returns: true if table name is valid, false otherwise
    private func validateTableName(_ name: String) -> Bool {
        return Self.validTableNames.contains(name)
    }


    
    // MARK: - Delegate

    weak var delegate: DatabaseManagerDelegate?

    // MARK: - Properties

    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "com.summerSpark.database", qos: .userInitiated)

    private(set) var databasePath: URL?
    private(set) var isInitialized: Bool = false

    private var currentVersion: Int = 0

    // MARK: - Schema Definitions

    private static let schemas: [String: TableSchema] = [
        "nodes": TableSchema(
            name: "nodes",
            columns: [
                .init(name: "id", type: "TEXT", notNull: true, unique: true),
                .init(name: "public_key", type: "BLOB"),
                .init(name: "display_name", type: "TEXT"),
                .init(name: "last_seen", type: "REAL"),
                .init(name: "trust_score", type: "REAL", defaultValue: "0.5"),
                .init(name: "is_trusted", type: "INTEGER", defaultValue: "0"),
                .init(name: "signature", type: "BLOB"),
                .init(name: "created_at", type: "REAL")
            ],
            primaryKey: "id"
        ),
        "sessions": TableSchema(
            name: "sessions",
            columns: [
                .init(name: "id", type: "TEXT", notNull: true, unique: true),
                .init(name: "node_id", type: "TEXT", notNull: true),
                .init(name: "started_at", type: "REAL"),
                .init(name: "ended_at", type: "REAL"),
                .init(name: "data_transferred", type: "INTEGER", defaultValue: "0")
            ],
            primaryKey: "id"
        ),
        "messages": TableSchema(
            name: "messages",
            columns: [
                .init(name: "id", type: "TEXT", notNull: true, unique: true),
                .init(name: "session_id", type: "TEXT"),
                .init(name: "sender_id", type: "TEXT"),
                .init(name: "encrypted_content", type: "BLOB"),
                .init(name: "timestamp", type: "REAL"),
                .init(name: "is_delivered", type: "INTEGER", defaultValue: "0")
            ],
            primaryKey: "id"
        ),
        "credentials": TableSchema(
            name: "credentials",
            columns: [
                .init(name: "id", type: "INTEGER", notNull: true),
                .init(name: "node_id", type: "TEXT", notNull: true),
                .init(name: "encrypted_key", type: "BLOB"),
                .init(name: "label", type: "TEXT"),
                .init(name: "created_at", type: "REAL")
            ],
            primaryKey: "id"
        ),
        "audit_log": TableSchema(
            name: "audit_log",
            columns: [
                .init(name: "id", type: "INTEGER", notNull: true),
                .init(name: "action", type: "TEXT"),
                .init(name: "node_id", type: "TEXT"),
                .init(name: "timestamp", type: "REAL"),
                .init(name: "details", type: "TEXT")
            ],
            primaryKey: "id"
        )
    ]

    // MARK: - Migrations

    private static let migrations: [Migration] = [
        Migration(version: 1, up: [
            "CREATE INDEX IF NOT EXISTS idx_sessions_node ON sessions(node_id);",
            "CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id);",
            "CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp);"
        ]),
        Migration(version: 2, up: [
            "ALTER TABLE nodes ADD COLUMN signature BLOB;"
        ]),
        Migration(version: 3, up: [
            "CREATE TABLE IF NOT EXISTS audit_log (id INTEGER PRIMARY KEY, action TEXT, node_id TEXT, timestamp REAL, details TEXT);"
        ])
    ]

    // MARK: - Configuration

    struct Config {
        public var databaseName: String = "summer_spark.db"
        public var applicationSupportDirectory: URL? = nil
        public var enableWAL: Bool = true
        public var synchronous: Int = 1 // NORMAL
        public var cacheSize: Int = 2000 // pages
        public var tempStore: Int = 2 // MEMORY
        public var pageSize: Int = 4096

        public init() {}
    }

    public var config = Config()

    // MARK: - Initialization

    private init() {}

    // MARK: - Setup

    func setup() {
        initialize()
    }

    func initialize(with config: Config? = nil) {
        guard !isInitialized else { return }

        if let cfg = config { self.config = cfg }

        let appSupport = config?.applicationSupportDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let dbDir = appSupport.appendingPathComponent("Database", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        } catch {
            delegate?.databaseManager(self, didEncounterError: .openFailed("无法创建目录: \(error.localizedDescription)"))
            return
        }

        databasePath = dbDir.appendingPathComponent(self.config.databaseName)

        dbQueue.sync { [weak self] in
            self?.setupDatabase()
            self?.runMigrations()
        }

        isInitialized = true
    }

    private func setupDatabase() {
        guard let path = databasePath else { return }

        if sqlite3_open(path.path, &db) != SQLITE_OK {
            let errMsg = String(cString: sqlite3_errmsg(db))
            delegate?.databaseManager(self, didEncounterError: .openFailed(errMsg))
            db = nil
            return
        }

        // Enable WAL mode
        if config.enableWAL {
            executeSQL("PRAGMA journal_mode=WAL;")
        }

        // Set synchronous level
        executeSQL("PRAGMA synchronous=\(config.synchronous);")

        // Set cache size
        executeSQL("PRAGMA cache_size=\(config.cacheSize);")

        // Set temp store
        executeSQL("PRAGMA temp_store=\(config.tempStore);")

        // Set page size
        executeSQL("PRAGMA page_size=\(config.pageSize);")

        // Enable foreign keys
        executeSQL("PRAGMA foreign_keys=ON;")

        // Create all tables
        createAllTables()
        
        // 设置文件保护级别 - 设备锁定时文件不可访问
        setFileProtectionLevel()
    }
    
    /// 设置数据库文件的文件保护级别
    /// 使用 completeUnlessOpen：文件打开时可读写，关闭后需解锁设备才能访问
    private func setFileProtectionLevel() {
        guard let dbPath = databasePath else { return }
        
        do {
            // 设置数据库文件保护级别
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen],
                ofItemAtPath: dbPath.path
            )
            
            // 设置WAL日志文件保护级别（如果存在）
            let walPath = dbPath.path + "-wal"
            if FileManager.default.fileExists(atPath: walPath) {
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUnlessOpen],
                    ofItemAtPath: walPath
                )
            }
            
            // 设置SHM共享内存文件保护级别（如果存在）
            let shmPath = dbPath.path + "-shm"
            if FileManager.default.fileExists(atPath: shmPath) {
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUnlessOpen],
                    ofItemAtPath: shmPath
                )
            }
            
            // 设置数据库目录的保护级别
            let dbDir = dbPath.deletingLastPathComponent()
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen],
                ofItemAtPath: dbDir.path
            )
            
            Logger.shared.info("数据库文件保护级别已设置为 completeUnlessOpen")
        } catch {
            Logger.shared.error("设置数据库文件保护级别失败: \(error)")
        }
    }

    // MARK: - Thread-safe Database Access

    func inDatabase(_ block: @escaping (OpaquePointer?) -> Void) {
        dbQueue.async { [weak self] in
            guard let self = self, let db = self.db else { return }
            block(db)
        }
    }

    func inTransaction(_ block: @escaping (OpaquePointer?, UnsafeMutablePointer<ObjCBool>) -> Void) {
        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            var rollback = ObjCBool(false)

            if sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil) != SQLITE_OK {
                return
            }

            block(db, &rollback)

            if rollback.boolValue {
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            } else {
                sqlite3_exec(db, "COMMIT;", nil, nil, nil)
            }
        }
    }

    // MARK: - Table Management

    func createTable(_ name: String) -> Bool {
        guard let schema = Self.schemas[name] else {
            delegate?.databaseManager(self, didEncounterError: .executeFailed("未知表: \(name)"))
            return false
        }

        var success = false
        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }
            let result = sqlite3_exec(db, schema.createSQL(), nil, nil, nil)
            success = result == SQLITE_OK
        }
        return success
    }

    func createAllTables() {
        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }
            for (_, schema) in Self.schemas {
                sqlite3_exec(db, schema.createSQL(), nil, nil, nil)
            }
        }
    }

    func tableExists(_ name: String) -> Bool {
        // SQL注入防护：验证表名
        guard validateTableName(name) else {
            Logger.shared.error("SQL注入防护：无效表名 '\(name)'")
            return false
        }

        var exists = false
        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let query = "SELECT name FROM sqlite_master WHERE type='table' AND name='\(name)';"
            var stmt: OpaquePointer?

            if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                exists = sqlite3_step(stmt) == SQLITE_ROW
            }
            sqlite3_finalize(stmt)
        }
        return exists
    }

    // MARK: - Schema Version & Migrations

    private func getUserVersion() -> Int {
        var version = 0
        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    version = Int(sqlite3_column_int(stmt, 0))
                }
            }
            sqlite3_finalize(stmt)
        }
        return version
    }

    private func setUserVersion(_ version: Int) {
        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }
            let sql = "PRAGMA user_version=\(version);"
            sqlite3_exec(db, sql, nil, nil, nil)
        }
    }

    func runMigrations() {
        let oldVersion = getUserVersion()
        let newVersion = Self.migrations.count

        guard oldVersion < newVersion else { return }

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            if sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil) != SQLITE_OK {
                return
            }

            var failed = false

            for migration in Self.migrations where migration.version > oldVersion {
                for sql in migration.upSQL {
                    if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                        let errMsg = String(cString: sqlite3_errmsg(db))
                        self.delegate?.databaseManager(self, didEncounterError: .migrationFailed(errMsg, migration.version))
                        failed = true
                        break
                    }
                }
                if failed { break }
            }

            if failed {
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            } else {
                sqlite3_exec(db, "COMMIT;", nil, nil, nil)
                self.setUserVersion(newVersion)
                self.currentVersion = newVersion

                DispatchQueue.main.async {
                    self.delegate?.databaseManagerDidMigrate(self, from: oldVersion, to: newVersion)
                }
            }
        }
    }

    // MARK: - SQL Execution Helper

    private func executeSQL(_ sql: String) {
        guard let db = db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - Generic CRUD Operations

    func insert(table: String, values: [String: Any]) throws {
        guard !values.isEmpty else { return }
        guard isInitialized else { throw DatabaseError.notInitialized }

        // SQL注入防护：验证表名
        guard validateTableName(table) else {
            Logger.shared.error("SQL注入防护：无效表名 '\(table)'")
            throw DatabaseError.executeFailed("无效表名")
        }

        let columns = values.keys.joined(separator: ", ")
        let placeholders = values.keys.map { _ in "?" }.joined(separator: ", ")
        let sql = "INSERT OR REPLACE INTO \(table) (\(columns)) VALUES (\(placeholders));"

        var success = false
        var errorMsg: String?

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                var idx: Int32 = 1
                for value in values.values {
                    bindValue(stmt, idx, value)
                    idx += 1
                }

                success = sqlite3_step(stmt) == SQLITE_DONE
                if !success {
                    errorMsg = String(cString: sqlite3_errmsg(db))
                }
            } else {
                errorMsg = String(cString: sqlite3_errmsg(db))
            }
            sqlite3_finalize(stmt)
        }

        if !success {
            throw DatabaseError.executeFailed(errorMsg ?? "未知错误")
        }
    }

    func query(table: String, columns: [String]? = nil, where condition: String? = nil, orderBy: String? = nil, limit: Int? = nil) throws -> [[String: Any]] {
        guard isInitialized else { throw DatabaseError.notInitialized }

        // SQL注入防护：验证表名
        guard validateTableName(table) else {
            Logger.shared.error("SQL注入防护：无效表名 '\(table)'")
            throw DatabaseError.queryFailed("无效表名")
        }

        let cols = (columns ?? ["*"]).joined(separator: ", ")
        var sql = "SELECT \(cols) FROM \(table)"
        if let cond = condition { sql += " WHERE \(cond)" }
        if let order = orderBy { sql += " ORDER BY \(order)" }
        if let lim = limit { sql += " LIMIT \(lim)" }
        sql += ";"

        var results: [[String: Any]] = []
        var errorMsg: String?

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    var row: [String: Any] = [:]
                    for i in 0..<sqlite3_column_count(stmt) {
                        let name = String(cString: sqlite3_column_name(stmt, i))
                        let colIdx = sqlite3_column_type(stmt, i)

                        switch colIdx {
                        case SQLITE_INTEGER:
                            row[name] = sqlite3_column_int64(stmt, i)
                        case SQLITE_FLOAT:
                            row[name] = sqlite3_column_double(stmt, i)
                        case SQLITE_TEXT:
                            if let text = sqlite3_column_text(stmt, i) {
                                row[name] = String(cString: text)
                            }
                        case SQLITE_BLOB:
                            if let blob = sqlite3_column_blob(stmt, i) {
                                let size = sqlite3_column_bytes(stmt, i)
                                row[name] = Data(bytes: blob, count: Int(size))
                            }
                        default:
                            row[name] = nil
                        }
                    }
                    results.append(row)
                }
            } else {
                errorMsg = String(cString: sqlite3_errmsg(db))
            }
            sqlite3_finalize(stmt)
        }

        if let err = errorMsg {
            throw DatabaseError.queryFailed(err)
        }

        return results
    }

    func update(table: String, values: [String: Any], where condition: String) throws -> Int {
        guard isInitialized else { throw DatabaseError.notInitialized }

        // SQL注入防护：验证表名
        guard validateTableName(table) else {
            Logger.shared.error("SQL注入防护：无效表名 '\(table)'")
            throw DatabaseError.executeFailed("无效表名")
        }

        let setParts = values.keys.map { "\($0) = ?" }.joined(separator: ", ")
        let sql = "UPDATE \(table) SET \(setParts) WHERE \(condition);"

        var affected = 0
        var errorMsg: String?

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                var idx: Int32 = 1
                for value in values.values {
                    bindValue(stmt, idx, value)
                    idx += 1
                }

                sqlite3_step(stmt)
                affected = Int(sqlite3_changes(db))
            } else {
                errorMsg = String(cString: sqlite3_errmsg(db))
            }
            sqlite3_finalize(stmt)
        }

        if let err = errorMsg {
            throw DatabaseError.executeFailed(err)
        }

        return affected
    }

    func delete(table: String, where condition: String) throws -> Int {
        guard isInitialized else { throw DatabaseError.notInitialized }

        // SQL注入防护：验证表名
        guard validateTableName(table) else {
            Logger.shared.error("SQL注入防护：无效表名 '\(table)'")
            throw DatabaseError.executeFailed("无效表名")
        }

        let sql = "DELETE FROM \(table) WHERE \(condition);"

        var affected = 0
        var errorMsg: String?

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_step(stmt)
                affected = Int(sqlite3_changes(db))
            } else {
                errorMsg = String(cString: sqlite3_errmsg(db))
            }
            sqlite3_finalize(stmt)
        }

        if let err = errorMsg {
            throw DatabaseError.executeFailed(err)
        }

        return affected
    }

    func executeRaw(_ sql: String, arguments: [Any]? = nil) throws {
        guard isInitialized else { throw DatabaseError.notInitialized }

        var errorMsg: String?

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                if let args = arguments {
                    var idx: Int32 = 1
                    for arg in args {
                        bindValue(stmt, idx, arg)
                        idx += 1
                    }
                }
                sqlite3_step(stmt)
            } else {
                errorMsg = String(cString: sqlite3_errmsg(db))
            }
            sqlite3_finalize(stmt)
        }

        if let err = errorMsg {
            throw DatabaseError.executeFailed(err)
        }
    }

    // MARK: - Value Binding Helper

    private func bindValue(_ stmt: OpaquePointer?, _ idx: Int32, _ value: Any) {
        guard let stmt = stmt else { return }

        if let str = value as? String {
            sqlite3_bind_text(stmt, idx, str, -1, nil)
        } else if let data = value as? Data {
            sqlite3_bind_blob(stmt, idx, (data as NSData).bytes, Int32(data.count), nil)
        } else if let num = value as? Int {
            sqlite3_bind_int64(stmt, idx, Int64(num))
        } else if let num = value as? Int64 {
            sqlite3_bind_int64(stmt, idx, num)
        } else if let num = value as? Double {
            sqlite3_bind_double(stmt, idx, num)
        } else if let num = value as? Int32 {
            sqlite3_bind_int(stmt, idx, num)
        } else if value is NSNull {
            sqlite3_bind_null(stmt, idx)
        }
    }

    // MARK: - Utility

    func vacuum() {
        dbQueue.async { [weak self] in
            guard let self = self, let db = self.db else { return }
            sqlite3_exec(db, "VACUUM;", nil, nil, nil)
        }
    }

    func clearTable(_ table: String) {
        // SQL注入防护：验证表名
        guard validateTableName(table) else {
            Logger.shared.error("SQL注入防护：无效表名 '\(table)'")
            return
        }

        dbQueue.async { [weak self] in
            guard let self = self, let db = self.db else { return }
            let sql = "DELETE FROM \(table);"
            sqlite3_exec(db, sql, nil, nil, nil)
        }
    }

    func getTableInfo(_ table: String) -> [String] {
        // SQL注入防护：验证表名
        guard validateTableName(table) else {
            Logger.shared.error("SQL注入防护：无效表名 '\(table)'")
            return []
        }

        var columns: [String] = []

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let sql = "PRAGMA table_info(\(table));"
            var stmt: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let namePtr = sqlite3_column_text(stmt, 1) {
                        columns.append(String(cString: namePtr))
                    }
                }
            }
            sqlite3_finalize(stmt)
        }

        return columns
    }

    func getRowCount(table: String) -> Int {
        // SQL注入防护：验证表名
        guard validateTableName(table) else {
            Logger.shared.error("SQL注入防护：无效表名 '\(table)'")
            return 0
        }

        var count = 0

        dbQueue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let sql = "SELECT COUNT(*) FROM \(table);"
            var stmt: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    count = Int(sqlite3_column_int64(stmt, 0))
                }
            }
            sqlite3_finalize(stmt)
        }

        return count
    }

    // MARK: - Cleanup

    func close() {
        dbQueue.sync { [weak self] in
            guard let self = self else { return }
            if let db = self.db {
                sqlite3_close(db)
                self.db = nil
            }
            self.isInitialized = false
            self.currentVersion = 0
        }
    }

    deinit {
        close()
    }
}