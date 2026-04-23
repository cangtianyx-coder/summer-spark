import Foundation
import SQLite3
import CryptoKit

// MARK: - CreditTransaction

struct CreditTransaction: Codable, Identifiable {
    let id: UUID
    let fromNodeId: UUID
    let toNodeId: UUID
    let amount: Int64
    let timestamp: Date
    let signature: Data
    let prevTransactionId: UUID?

    init(from: UUID, to: UUID, amount: Int64, signature: Data, prevTransactionId: UUID? = nil) {
        self.id = UUID()
        self.fromNodeId = from
        self.toNodeId = to
        self.amount = amount
        self.timestamp = Date()
        self.signature = signature
        self.prevTransactionId = prevTransactionId
    }
}

// MARK: - LedgerEntry

struct LedgerEntry: Codable {
    let transactionId: UUID
    let nodeId: UUID
    let balanceChange: Int64
    let balanceAfter: Int64
    let timestamp: Date
}

// MARK: - CreditError

enum CreditError: Error, LocalizedError {
    case insufficientBalance
    case duplicateTransaction
    case invalidSignature
    case doubleSpendAttempt(transactionId: UUID)
    case databaseError(String)
    case syncFailed(String)
    case nodeNotFound(nodeId: UUID)

    var errorDescription: String? {
        switch self {
        case .insufficientBalance:
            return "余额不足"
        case .duplicateTransaction:
            return "交易已存在"
        case .invalidSignature:
            return "签名无效"
        case .doubleSpendAttempt(let id):
            return "检测到双花尝试: \(id)"
        case .databaseError(let msg):
            return "数据库错误: \(msg)"
        case .syncFailed(let msg):
            return "同步失败: \(msg)"
        case .nodeNotFound(let id):
            return "节点未找到: \(id)"
        }
    }
}

// MARK: - CreditSyncManagerDelegate

protocol CreditSyncManagerDelegate: AnyObject {
    func creditSyncManager(_ manager: CreditSyncManager, didUpdateBalance balance: Int64, for nodeId: UUID)
    func creditSyncManager(_ manager: CreditSyncManager, didReceiveTransaction transaction: CreditTransaction)
    func creditSyncManager(_ manager: CreditSyncManager, didFailWithError error: Error)
    func creditSyncManager(_ manager: CreditSyncManager, didDetectDoubleSpend transactionId: UUID)
}

final class CreditSyncManager {
    weak var delegate: CreditSyncManagerDelegate?
    static let shared = CreditSyncManager()

    // MARK: - Properties

    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "com.creditsync.db", qos: .userInitiated)
    private let syncQueue = DispatchQueue(label: "com.creditsync.sync", qos: .userInitiated)

    private var pendingTransactions: Set<UUID> = []
    private let pendingLock = NSLock()

    private var localNodeId: UUID {
        return MeshService.shared.localNodeId
    }

    // MARK: - Configuration

    struct Config {
        public var initialBalance: Int64 = 1000
        public var maxTransactionAmount: Int64 = 10000
        public var minTransactionAmount: Int64 = 1
        public var ledgerRetentionDays: Int = 90
        public var syncRetryCount: Int = 3
        public var syncRetryDelaySeconds: TimeInterval = 2.0

        public init() {}
    }

    public var config = Config()

    lazy var operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.creditsync.operationQueue"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    // MARK: - Initialization

    private init() {
        setupDatabase()
        setupMeshListener()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        sqlite3_close(db)
    }

    // MARK: - Database Setup

    private func setupDatabase() {
        dbQueue.async { [weak self] in
            guard let self = self else { return }

            let fileManager = FileManager.default
            guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                Logger.shared.error("CreditSyncManager: Failed to get application support directory")
                return
            }
            let dbDir = appSupport.appendingPathComponent("CreditSync")

            try? fileManager.createDirectory(at: dbDir, withIntermediateDirectories: true)

            let dbPath = dbDir.appendingPathComponent("credits.sqlite").path

            if sqlite3_open(dbPath, &self.db) != SQLITE_OK {
                let errMsg = String(cString: sqlite3_errmsg(self.db))
                Logger.shared.error("CreditSyncManager: Failed to open database - \(errMsg)")
                return
            }

            self.createTables()
            self.createIndexes()
        }
    }

    private func createTables() {
        let createTransactionsTable = """
        CREATE TABLE IF NOT EXISTS transactions (
            id TEXT PRIMARY KEY,
            from_node_id TEXT NOT NULL,
            to_node_id TEXT NOT NULL,
            amount INTEGER NOT NULL,
            timestamp REAL NOT NULL,
            signature BLOB NOT NULL,
            prev_transaction_id TEXT,
           UNIQUE(id)
        );
        """

        let createLedgerTable = """
        CREATE TABLE IF NOT EXISTS ledger (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            transaction_id TEXT NOT NULL,
            node_id TEXT NOT NULL,
            balance_change INTEGER NOT NULL,
            balance_after INTEGER NOT NULL,
            timestamp REAL NOT NULL,
            UNIQUE(transaction_id, node_id)
        );
        """

        let createBalancesTable = """
        CREATE TABLE IF NOT EXISTS balances (
            node_id TEXT PRIMARY KEY,
            balance INTEGER NOT NULL DEFAULT 0,
            updated_at REAL NOT NULL
        );
        """

        let createPendingTable = """
        CREATE TABLE IF NOT EXISTS pending_transactions (
            transaction_id TEXT PRIMARY KEY,
            received_at REAL NOT NULL
        );
        """

        executeSQL(createTransactionsTable)
        executeSQL(createLedgerTable)
        executeSQL(createBalancesTable)
        executeSQL(createPendingTable)
    }

    private func createIndexes() {
        let idx1 = "CREATE INDEX IF NOT EXISTS idx_tx_timestamp ON transactions(timestamp);"
        let idx2 = "CREATE INDEX IF NOT EXISTS idx_tx_from ON transactions(from_node_id);"
        let idx3 = "CREATE INDEX IF NOT EXISTS idx_tx_to ON transactions(to_node_id);"
        let idx4 = "CREATE INDEX IF NOT EXISTS idx_ledger_node ON ledger(node_id);"
        let idx5 = "CREATE INDEX IF NOT EXISTS idx_ledger_tx ON ledger(transaction_id);"

        executeSQL(idx1)
        executeSQL(idx2)
        executeSQL(idx3)
        executeSQL(idx4)
        executeSQL(idx5)
    }

    private func executeSQL(_ sql: String) {
        var errMsg: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let err = errMsg {
                let msg = String(cString: err)
                Logger.shared.error("CreditSyncManager SQL Error: \(msg)")
                sqlite3_free(errMsg)
            }
        }
    }

    // MARK: - Mesh Listener

    private func setupMeshListener() {
        // Listen for credit sync messages via MeshService
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMeshMessage(_:)),
            name: .meshMessageReceived,
            object: nil
        )
    }

    @objc private func handleMeshMessage(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let message = userInfo["message"] as? MeshMessage,
              let payload = try? JSONDecoder().decode(CreditMessagePayload.self, from: message.payload) else {
            return
        }

        syncQueue.async { [weak self] in
            self?.handleIncomingMessage(payload, from: message.sourceNodeId)
        }
    }

    private func handleIncomingMessage(_ payload: CreditMessagePayload, from sourceNodeId: UUID) {
        switch payload.type {
        case .transaction:
            if let tx = payload.transaction {
                handleIncomingTransaction(tx)
            }
        case .syncRequest:
            if let nodeId = payload.nodeId {
                respondToSyncRequest(nodeId: nodeId, requestor: sourceNodeId)
            }
        case .syncResponse:
            if let entries = payload.ledgerEntries {
                mergeLedgerEntries(entries)
            }
        case .balanceQuery:
            if let nodeId = payload.nodeId {
                respondToBalanceQuery(nodeId: nodeId, requestor: sourceNodeId)
            }
        case .balanceResponse:
            if let balance = payload.balance, let nodeId = payload.nodeId {
                updateRemoteBalance(nodeId: nodeId, balance: balance)
            }
        }
    }

    // MARK: - Transaction Operations

    /// Transfer credits to another node
    func transfer(toNodeId: UUID, amount: Int64) throws {
        guard amount >= config.minTransactionAmount else {
            throw CreditError.insufficientBalance
        }
        guard amount <= config.maxTransactionAmount else {
            throw CreditError.syncFailed("金额超出限制")
        }

        let fromNodeId = localNodeId

        // Get current balance
        let currentBalance = try getBalance(for: fromNodeId)
        guard currentBalance >= amount else {
            throw CreditError.insufficientBalance
        }

        // Get last transaction for chaining
        let prevTxId = try getLastTransactionId(for: fromNodeId)

        // Create transaction
        let txData = createTransactionData(from: fromNodeId, to: toNodeId, amount: amount, prevTxId: prevTxId)
        let signature = signTransaction(txData)

        let transaction = CreditTransaction(
            from: fromNodeId,
            to: toNodeId,
            amount: amount,
            signature: signature,
            prevTransactionId: prevTxId
        )

        // Check for double-spend
        if try isDoubleSpend(transaction) {
            throw CreditError.doubleSpendAttempt(transactionId: transaction.id)
        }

        // Persist and apply
        try persistTransaction(transaction)
        try applyTransaction(transaction)

        // Broadcast to network
        broadcastTransaction(transaction)
    }

    /// Get current balance for a node
    func getBalance(for nodeId: UUID) throws -> Int64 {
        var balance: Int64 = 0

        dbQueue.sync {
            let sql = "SELECT balance FROM balances WHERE node_id = ?;"
            var stmt: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, nodeId.uuidString, -1, nil)

                if sqlite3_step(stmt) == SQLITE_ROW {
                    balance = sqlite3_column_int64(stmt, 0)
                } else {
                    // Initialize balance for new node (local only)
                    if nodeId == localNodeId {
                        balance = config.initialBalance
                        try? insertOrUpdateBalance(nodeId: nodeId, balance: balance)
                    }
                }
            }
            sqlite3_finalize(stmt)
        }

        return balance
    }

    // MARK: - Double-Spend Prevention

    private func isDoubleSpend(_ transaction: CreditTransaction) throws -> Bool {
        var exists = false

        dbQueue.sync {
            let sql = "SELECT 1 FROM transactions WHERE id = ?;"
            var stmt: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, transaction.id.uuidString, -1, nil)
                exists = sqlite3_step(stmt) == SQLITE_ROW
            }
            sqlite3_finalize(stmt)
        }

        return exists
    }

    private func markTransactionPending(_ transactionId: UUID) {
        pendingLock.lock()
        pendingTransactions.insert(transactionId)
        pendingLock.unlock()

        dbQueue.async { [weak self] in
            guard let self = self else { return }
            let sql = "INSERT OR IGNORE INTO pending_transactions (transaction_id, received_at) VALUES (?, ?);"
            var stmt: OpaquePointer?

            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, transactionId.uuidString, -1, nil)
                sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    private func isTransactionPending(_ transactionId: UUID) -> Bool {
        pendingLock.lock()
        let isPending = pendingTransactions.contains(transactionId)
        pendingLock.unlock()
        return isPending
    }

    // MARK: - Persistence

    private func persistTransaction(_ transaction: CreditTransaction) throws {
        var success = false

        dbQueue.sync {
            let sql = """
            INSERT INTO transactions (id, from_node_id, to_node_id, amount, timestamp, signature, prev_transaction_id)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, transaction.id.uuidString, -1, nil)
                sqlite3_bind_text(stmt, 2, transaction.fromNodeId.uuidString, -1, nil)
                sqlite3_bind_text(stmt, 3, transaction.toNodeId.uuidString, -1, nil)
                sqlite3_bind_int64(stmt, 4, transaction.amount)
                sqlite3_bind_double(stmt, 5, transaction.timestamp.timeIntervalSince1970)
                sqlite3_bind_blob(stmt, 6, (transaction.signature as NSData).bytes, Int32(transaction.signature.count), nil)
                if let prevId = transaction.prevTransactionId {
                    sqlite3_bind_text(stmt, 7, prevId.uuidString, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 7)
                }

                success = sqlite3_step(stmt) == SQLITE_DONE
                if !success {
                    let errMsg = String(cString: sqlite3_errmsg(db))
                    Logger.shared.error("CreditSyncManager: persistTransaction failed - \(errMsg)")
                }
            }
            sqlite3_finalize(stmt)
        }

        if !success {
            throw CreditError.databaseError("Failed to persist transaction")
        }
    }

    private func applyTransaction(_ transaction: CreditTransaction) throws {
        // Update sender balance
        let senderBalance = try getBalance(for: transaction.fromNodeId)
        let newSenderBalance = senderBalance - transaction.amount
        try insertOrUpdateBalance(nodeId: transaction.fromNodeId, balance: newSenderBalance)

        // Update recipient balance
        let recipientBalance = try getBalance(for: transaction.toNodeId)
        let newRecipientBalance = recipientBalance + transaction.amount
        try insertOrUpdateBalance(nodeId: transaction.toNodeId, balance: newRecipientBalance)

        // Record ledger entries
        try recordLedgerEntry(for: transaction.fromNodeId, transactionId: transaction.id, balanceChange: -transaction.amount, balanceAfter: newSenderBalance)
        try recordLedgerEntry(for: transaction.toNodeId, transactionId: transaction.id, balanceChange: transaction.amount, balanceAfter: newRecipientBalance)

        // Notify delegate
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.creditSyncManager(self, didUpdateBalance: newSenderBalance, for: transaction.fromNodeId)
            self.delegate?.creditSyncManager(self, didUpdateBalance: newRecipientBalance, for: transaction.toNodeId)
            self.delegate?.creditSyncManager(self, didReceiveTransaction: transaction)
        }
    }

    private func insertOrUpdateBalance(nodeId: UUID, balance: Int64) throws {
        dbQueue.sync {
            let sql = """
            INSERT INTO balances (node_id, balance, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(node_id) DO UPDATE SET balance = ?, updated_at = ?;
            """
            var stmt: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, nodeId.uuidString, -1, nil)
                sqlite3_bind_int64(stmt, 2, balance)
                sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
                sqlite3_bind_int64(stmt, 4, balance)
                sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    private func recordLedgerEntry(for nodeId: UUID, transactionId: UUID, balanceChange: Int64, balanceAfter: Int64) throws {
        dbQueue.sync {
            let sql = """
            INSERT INTO ledger (transaction_id, node_id, balance_change, balance_after, timestamp)
            VALUES (?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, transactionId.uuidString, -1, nil)
                sqlite3_bind_text(stmt, 2, nodeId.uuidString, -1, nil)
                sqlite3_bind_int64(stmt, 3, balanceChange)
                sqlite3_bind_int64(stmt, 4, balanceAfter)
                sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    private func getLastTransactionId(for nodeId: UUID) throws -> UUID? {
        var lastId: UUID?

        dbQueue.sync {
            let sql = """
            SELECT t.id FROM transactions t
            WHERE t.from_node_id = ? OR t.to_node_id = ?
            ORDER BY t.timestamp DESC LIMIT 1;
            """
            var stmt: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, nodeId.uuidString, -1, nil)
                sqlite3_bind_text(stmt, 2, nodeId.uuidString, -1, nil)

                if sqlite3_step(stmt) == SQLITE_ROW {
                    let idStr = String(cString: sqlite3_column_text(stmt, 0))
                    lastId = UUID(uuidString: idStr)
                }
            }
            sqlite3_finalize(stmt)
        }

        return lastId
    }

    // MARK: - Network Broadcast

    private func broadcastTransaction(_ transaction: CreditTransaction) {
        let payload = CreditMessagePayload(type: .transaction, transaction: transaction, nodeId: nil, balance: nil, ledgerEntries: nil)

        guard let payloadData = try? JSONEncoder().encode(payload) else { return }

        let message = MeshMessage(
            source: localNodeId,
            destination: nil,
            payload: payloadData,
            ttl: 64
        )

        MeshService.shared.sendMessage(message)
    }

    private func handleIncomingTransaction(_ transaction: CreditTransaction) {
        // Skip if already processed
        if isTransactionPending(transaction.id) { return }

        markTransactionPending(transaction.id)

        syncQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                // Verify signature
                guard self.verifyTransaction(transaction) else {
                    throw CreditError.invalidSignature
                }

                // Check for double-spend
                if try self.isDoubleSpend(transaction) {
                    throw CreditError.doubleSpendAttempt(transactionId: transaction.id)
                }

                // Persist and apply
                try self.persistTransaction(transaction)
                try self.applyTransaction(transaction)

            } catch let error as CreditError {
                if case .doubleSpendAttempt = error {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.creditSyncManager(self, didDetectDoubleSpend: transaction.id)
                    }
                } else {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.creditSyncManager(self, didFailWithError: error)
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.creditSyncManager(self, didFailWithError: error)
                }
            }
        }
    }

    // MARK: - Sync Operations

    func requestSyncFromNetwork() {
        let payload = CreditMessagePayload(type: .syncRequest, transaction: nil, nodeId: localNodeId, balance: nil, ledgerEntries: nil)

        guard let payloadData = try? JSONEncoder().encode(payload) else { return }

        let message = MeshMessage(
            source: localNodeId,
            destination: nil,
            payload: payloadData,
            ttl: 32
        )

        MeshService.shared.sendMessage(message)
    }

    private func respondToSyncRequest(nodeId: UUID, requestor: UUID) {
        let entries = getLedgerEntries(for: nodeId, limit: 1000)
        let payload = CreditMessagePayload(type: .syncResponse, transaction: nil, nodeId: nodeId, balance: nil, ledgerEntries: entries)

        guard let payloadData = try? JSONEncoder().encode(payload) else { return }

        let message = MeshMessage(
            source: localNodeId,
            destination: requestor,
            payload: payloadData,
            ttl: 32
        )

        MeshService.shared.sendMessage(message)
    }

    private func mergeLedgerEntries(_ entries: [LedgerEntry]) {
        dbQueue.async { [weak self] in
            guard let self = self else { return }

            for entry in entries {
                let sql = """
                INSERT OR IGNORE INTO ledger (transaction_id, node_id, balance_change, balance_after, timestamp)
                VALUES (?, ?, ?, ?, ?);
                """
                var stmt: OpaquePointer?

                if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, entry.transactionId.uuidString, -1, nil)
                    sqlite3_bind_text(stmt, 2, entry.nodeId.uuidString, -1, nil)
                    sqlite3_bind_int64(stmt, 3, entry.balanceChange)
                    sqlite3_bind_int64(stmt, 4, entry.balanceAfter)
                    sqlite3_bind_double(stmt, 5, entry.timestamp.timeIntervalSince1970)
                    sqlite3_step(stmt)
                }
                sqlite3_finalize(stmt)
            }
        }
    }

    func queryBalance(for nodeId: UUID) {
        let payload = CreditMessagePayload(type: .balanceQuery, transaction: nil, nodeId: nodeId, balance: nil, ledgerEntries: nil)

        guard let payloadData = try? JSONEncoder().encode(payload) else { return }

        let message = MeshMessage(
            source: localNodeId,
            destination: nil,
            payload: payloadData,
            ttl: 16
        )

        MeshService.shared.sendMessage(message)
    }

    private func respondToBalanceQuery(nodeId: UUID, requestor: UUID) {
        do {
            let balance = try getBalance(for: nodeId)
            let payload = CreditMessagePayload(type: .balanceResponse, transaction: nil, nodeId: nodeId, balance: balance, ledgerEntries: nil)

            guard let payloadData = try? JSONEncoder().encode(payload) else { return }

            let message = MeshMessage(
                source: localNodeId,
                destination: requestor,
                payload: payloadData,
                ttl: 16
            )

            MeshService.shared.sendMessage(message)
        } catch {
            Logger.shared.error("CreditSyncManager: Failed to respond to balance query - \(error)")
        }
    }

    private func updateRemoteBalance(nodeId: UUID, balance: Int64) {
        // Update local cache of remote balance
        dbQueue.async { [weak self] in
            guard let self = self else { return }
            try? self.insertOrUpdateBalance(nodeId: nodeId, balance: balance)
        }
    }

    // MARK: - Ledger Queries

    func getLedgerEntries(for nodeId: UUID, limit: Int = 100) -> [LedgerEntry] {
        var entries: [LedgerEntry] = []

        dbQueue.sync {
            let sql = """
            SELECT transaction_id, node_id, balance_change, balance_after, timestamp
            FROM ledger
            WHERE node_id = ?
            ORDER BY timestamp DESC LIMIT ?;
            """
            var stmt: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, nodeId.uuidString, -1, nil)
                sqlite3_bind_int(stmt, 2, Int32(limit))

                while sqlite3_step(stmt) == SQLITE_ROW {
                    let txIdStr = String(cString: sqlite3_column_text(stmt, 0))
                    let nodeIdStr = String(cString: sqlite3_column_text(stmt, 1))

                    if let txId = UUID(uuidString: txIdStr),
                       let nodeId = UUID(uuidString: nodeIdStr) {
                        let entry = LedgerEntry(
                            transactionId: txId,
                            nodeId: nodeId,
                            balanceChange: sqlite3_column_int64(stmt, 2),
                            balanceAfter: sqlite3_column_int64(stmt, 3),
                            timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
                        )
                        entries.append(entry)
                    }
                }
            }
            sqlite3_finalize(stmt)
        }

        return entries
    }

    func getTransactionHistory(for nodeId: UUID, limit: Int = 50) -> [CreditTransaction] {
        var transactions: [CreditTransaction] = []

        dbQueue.sync {
            let sql = """
            SELECT id, from_node_id, to_node_id, amount, timestamp, signature, prev_transaction_id
            FROM transactions
            WHERE from_node_id = ? OR to_node_id = ?
            ORDER BY timestamp DESC LIMIT ?;
            """
            var stmt: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, nodeId.uuidString, -1, nil)
                sqlite3_bind_text(stmt, 2, nodeId.uuidString, -1, nil)
                sqlite3_bind_int(stmt, 3, Int32(limit))

                while sqlite3_step(stmt) == SQLITE_ROW {
                    let idStr = String(cString: sqlite3_column_text(stmt, 0))
                    let fromStr = String(cString: sqlite3_column_text(stmt, 1))
                    let toStr = String(cString: sqlite3_column_text(stmt, 2))

                    if let id = UUID(uuidString: idStr),
                       let from = UUID(uuidString: fromStr),
                       let to = UUID(uuidString: toStr) {

                        let sigBytes = sqlite3_column_blob(stmt, 5)
                        let sigLen = sqlite3_column_bytes(stmt, 5)
                        let signature = Data(bytes: sigBytes!, count: Int(sigLen))

                        var prevId: UUID?
                        if let prevIdStr = sqlite3_column_text(stmt, 6), let prev = UUID(uuidString: String(cString: prevIdStr)) {
                            prevId = prev
                        }

                        let tx = CreditTransaction(
                            from: from,
                            to: to,
                            amount: sqlite3_column_int64(stmt, 3),
                            signature: signature,
                            prevTransactionId: prevId
                        )
                        transactions.append(tx)
                    }
                }
            }
            sqlite3_finalize(stmt)
        }

        return transactions
    }

    // MARK: - Cryptographic Operations

    private func createTransactionData(from: UUID, to: UUID, amount: Int64, prevTxId: UUID?) -> Data {
        var data = Data()
        data.append(from.uuidString.data(using: .utf8)!)
        data.append(to.uuidString.data(using: .utf8)!)
        data.append(String(amount).data(using: .utf8)!)
        if let prevId = prevTxId {
            data.append(prevId.uuidString.data(using: .utf8)!)
        }
        return data
    }

    private func signTransaction(_ data: Data) -> Data {
        guard let identity = IdentityManager.shared.getPrivateKey() else {
            return Data()
        }
        return CryptoEngine.shared.sign(data: data, privateKey: identity)
    }

    private func verifyTransaction(_ transaction: CreditTransaction) -> Bool {
        let data = createTransactionData(
            from: transaction.fromNodeId,
            to: transaction.toNodeId,
            amount: transaction.amount,
            prevTxId: transaction.prevTransactionId
        )

        // For incoming transactions, we need the sender's public key
        // In a real implementation, this would be fetched from IdentityManager
        // using the fromNodeId to look up the appropriate key
        guard let publicKey = getPublicKey(for: transaction.fromNodeId) else {
            return false // Reject if we can't verify (prevents unsigned/fake transactions)
        }

        return CryptoEngine.shared.verify(
            signature: transaction.signature,
            data: data,
            publicKey: publicKey
        )
    }

    // P0-FIX: 从MeshService获取对应节点的公钥，而不是返回本地公钥
    private func getPublicKey(for nodeId: UUID) -> P256.Signing.PublicKey? {
        // 优先从MeshService获取该节点的公钥
        if let publicKey = MeshService.shared.getPublicKey(for: nodeId) {
            return publicKey
        }
        
        // 如果是本地节点，返回本地公钥
        if nodeId == localNodeId {
            return IdentityManager.shared.getPublicKey()
        }
        
        // 从缓存中查找
        if let cachedKey = publicKeyCache[nodeId] {
            return cachedKey
        }
        
        Logger.shared.warn("CreditSyncManager: Public key not found for node \(nodeId)")
        return nil
    }
    
    // P0-FIX: 添加公钥缓存
    private var publicKeyCache: [UUID: P256.Signing.PublicKey] = [:]
    private let keyCacheLock = NSLock()
    
    // P0-FIX: 缓存公钥的方法
    func cachePublicKey(_ publicKey: P256.Signing.PublicKey, for nodeId: UUID) {
        keyCacheLock.lock()
        publicKeyCache[nodeId] = publicKey
        keyCacheLock.unlock()
    }

    // MARK: - Cleanup

    func cleanupOldLedgerEntries() {
        dbQueue.async { [weak self] in
            guard let self = self else { return }

            let cutoff = Date().addingTimeInterval(-Double(self.config.ledgerRetentionDays * 24 * 3600))
            let sql = "DELETE FROM ledger WHERE timestamp < ?;"

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, cutoff.timeIntervalSince1970)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }
}

// MARK: - CreditMessagePayload

struct CreditMessagePayload: Codable {
    enum MessageType: String, Codable {
        case transaction
        case syncRequest
        case syncResponse
        case balanceQuery
        case balanceResponse
    }

    let type: MessageType
    let transaction: CreditTransaction?
    let nodeId: UUID?
    let balance: Int64?
    let ledgerEntries: [LedgerEntry]?
}

// MARK: - Stub Methods for SummerSpark Compilation

extension CreditSyncManager {
    func startSync() {
        // Stub for SummerSpark compilation
    }

    func createSyncOperation() -> Operation {
        return BlockOperation { [weak self] in
            self?.requestSyncFromNetwork()
        }
    }

    func performSync(completion: @escaping (Result<Void, Error>) -> Void) {
        requestSyncFromNetwork()
        completion(.success(()))
    }
}
