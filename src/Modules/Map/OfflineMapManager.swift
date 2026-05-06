import Foundation
import CryptoKit

// MARK: - OfflineMapManagerDelegate

protocol OfflineMapManagerDelegate: AnyObject {
    func offlineMapManager(_ manager: OfflineMapManager, didUpdateProgress progress: OfflineMapProgress)
    func offlineMapManager(_ manager: OfflineMapManager, didCompleteMap mapInfo: OfflineMapInfo)
    func offlineMapManager(_ manager: OfflineMapManager, didFailMap mapId: String, error: Error)
}

// MARK: - DownloadState

enum DownloadState: Equatable {
    case idle
    case downloading
    case paused
    case completed
    case failed(String)
    
    var isActive: Bool {
        if case .downloading = self { return true }
        return false
    }
    
    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }
    
    var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }
}

// MARK: - TileDownloadTask

struct TileDownloadTask: Equatable {
    let coordinate: TileCoordinate
    let url: URL
    var state: DownloadState
    var data: Data?
    var bytesDownloaded: Int64
    
    static func == (lhs: TileDownloadTask, rhs: TileDownloadTask) -> Bool {
        return lhs.coordinate == rhs.coordinate
    }
}

// MARK: - DownloadedTileRecord

struct DownloadedTileRecord: Codable {
    let coordinate: TileCoordinate
    let filePath: String
    let fileSize: Int64
    let downloadedAt: Date
}

// MARK: - DownloadProgressRecord

struct DownloadProgressRecord: Codable {
    let mapId: String
    let totalTiles: Int
    let downloadedTileCount: Int
    let totalBytes: Int64
    let downloadedBytes: Int64
    let pendingTiles: [TileCoordinate]
    let completedTiles: [TileCoordinate]
    let failedTiles: [TileCoordinate]
    let lastUpdated: Date
    let downloadOffset: Int64
}

// MARK: - OfflineMapManager

final class OfflineMapManager: NSObject {
    static let shared = OfflineMapManager()

    
    // MARK: - Properties
    
    weak var delegate: OfflineMapManagerDelegate?
    
    private(set) var activeDownloads: [String: DownloadState] = [:]
    private(set) var downloadProgress: [String: OfflineMapProgress] = [:]
    
    private let downloadQueue = DispatchQueue(label: "com.map.offline.download", qos: .userInitiated, attributes: .concurrent)
    private let fileQueue = DispatchQueue(label: "com.map.offline.file", qos: .utility)
    
    private var urlSession: URLSession!
    private var downloadTasks: [String: TileDownloadTask] = [:]
    private var pendingTiles: [String: [TileCoordinate]] = [:]
    private var completedTiles: [String: Set<TileCoordinate>] = [:]
    private var failedTiles: [String: Set<TileCoordinate>] = [:]
    private var downloadedBytes: [String: Int64] = [:]
    private var totalBytes: [String: Int64] = [:]
    private var downloadOffsets: [String: Int64] = [:]
    
    private var currentMapInfo: [String: OfflineMapInfo] = [:]
    private var currentTileCount: [String: Int] = [:]
    private var currentDownloadedCount: [String: Int] = [:]
    
    private let maxConcurrentDownloads = 4
    private let maxRetryCount = 3
    private let tileBufferSize = 50
    
    private var suspendedTileBuffers: [String: [TileCoordinate]] = [:]
    private var isProcessingBuffer: [String: Bool] = [:]
    
    private let fileManager = FileManager.default
    private let documentsPath: URL
    
    private let progressKey = "OfflineMapManager.Progress"
    private let recordsKey = "OfflineMapManager.Records"
    
    private lazy var userDefaults: UserDefaults = {
        return UserDefaults.standard
    }()
    
    // MARK: - Initialization
    
    override init() {
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            // 使用临时目录作为后备方案，避免崩溃
            Logger.shared.error("OfflineMapManager: Failed to get documents directory, using temp directory")
            self.documentsPath = FileManager.default.temporaryDirectory.appendingPathComponent("OfflineMaps", isDirectory: true)
            super.init()
            setupURLSession()
            createOfflineMapsDirectory()
            loadPersistedProgress()
            return
        }
        self.documentsPath = documents.appendingPathComponent("OfflineMaps", isDirectory: true)
        
        super.init()
        
        setupURLSession()
        createOfflineMapsDirectory()
        loadPersistedProgress()
    }
    
    private func setupURLSession() {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = maxConcurrentDownloads
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    private func createOfflineMapsDirectory() {
        if !fileManager.fileExists(atPath: documentsPath.path) {
            try? fileManager.createDirectory(at: documentsPath, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Download Control
    
    func startDownload(_ mapInfo: OfflineMapInfo) {
        downloadQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.activeDownloads[mapInfo.mapId]?.isActive == true {
                return
            }
            
            self.currentMapInfo[mapInfo.mapId] = mapInfo
            self.activeDownloads[mapInfo.mapId] = .downloading
            
            self.initializeDownloadState(for: mapInfo)
            self.loadPersistedProgressForMap(mapInfo.mapId)
            self.processTileBuffer(for: mapInfo.mapId)
        }
    }
    
    func pauseDownload(mapId: String) {
        downloadQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.activeDownloads[mapId]?.isActive == true {
                self.activeDownloads[mapId] = .paused
                self.persistProgress(for: mapId)
            }
        }
    }
    
    func resumeDownload(mapId: String) {
        downloadQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.activeDownloads[mapId]?.isPaused == true {
                self.activeDownloads[mapId] = .downloading
                self.loadPersistedProgressForMap(mapId)
                
                if let mapInfo = self.currentMapInfo[mapId] {
                    self.processTileBuffer(for: mapId)
                }
            }
        }
    }
    
    func cancelDownload(mapId: String) {
        downloadQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.activeDownloads[mapId] = .idle
            for key in self.downloadTasks.keys {
                self.downloadTasks[key]?.state = .idle
            }
            self.clearPersistedProgress(for: mapId)
            self.resetDownloadState(for: mapId)
        }
    }
    
    func deleteMap(mapId: String) {
        fileQueue.async { [weak self] in
            guard let self = self else { return }
            
            let mapPath = self.documentsPath.appendingPathComponent(mapId)
            if self.fileManager.fileExists(atPath: mapPath.path) {
                try? self.fileManager.removeItem(at: mapPath)
            }
            
            self.downloadQueue.async {
                self.resetDownloadState(for: mapId)
                self.clearPersistedProgress(for: mapId)
            }
        }
    }
    
    // MARK: - Progress
    
    func getProgress(for mapId: String) -> OfflineMapProgress {
        let total = currentTileCount[mapId] ?? 0
        let downloaded = currentDownloadedCount[mapId] ?? 0
        let totalBytes = self.totalBytes[mapId] ?? 0
        let downloadedBytes = self.downloadedBytes[mapId] ?? 0
        
        let pending = pendingTiles[mapId] ?? []
        let currentTile = pending.first
        
        return OfflineMapProgress(
            mapId: mapId,
            totalTiles: total,
            downloadedTiles: downloaded,
            totalBytes: totalBytes,
            downloadedBytes: downloadedBytes,
            currentTileCoord: currentTile,
            isResumable: activeDownloads[mapId]?.isPaused == true
        )
    }
    
    // MARK: - State Initialization
    
    private func initializeDownloadState(for mapInfo: OfflineMapInfo) {
        let tiles = calculateTiles(for: mapInfo.bounds, minZoom: mapInfo.minZoom, maxZoom: mapInfo.maxZoom)
        
        currentTileCount[mapInfo.mapId] = tiles.count
        currentDownloadedCount[mapInfo.mapId] = 0
        pendingTiles[mapInfo.mapId] = tiles
        completedTiles[mapInfo.mapId] = []
        failedTiles[mapInfo.mapId] = []
        downloadedBytes[mapInfo.mapId] = 0
        totalBytes[mapInfo.mapId] = 0
        downloadOffsets[mapInfo.mapId] = 0
        
        let estimatedTileSize: Int64 = 2048
        totalBytes[mapInfo.mapId] = Int64(tiles.count) * estimatedTileSize
    }
    
    private func resetDownloadState(for mapId: String) {
        pendingTiles.removeValue(forKey: mapId)
        completedTiles.removeValue(forKey: mapId)
        failedTiles.removeValue(forKey: mapId)
        downloadedBytes.removeValue(forKey: mapId)
        totalBytes.removeValue(forKey: mapId)
        downloadOffsets.removeValue(forKey: mapId)
        currentTileCount.removeValue(forKey: mapId)
        currentDownloadedCount.removeValue(forKey: mapId)
        currentMapInfo.removeValue(forKey: mapId)
        downloadTasks.removeValue(forKey: mapId)
        suspendedTileBuffers.removeValue(forKey: mapId)
        isProcessingBuffer.removeValue(forKey: mapId)
        downloadProgress.removeValue(forKey: mapId)
    }
    
    // MARK: - Tile Calculation
    
    private func calculateTiles(for bounds: MapBounds, minZoom: Int, maxZoom: Int) -> [TileCoordinate] {
        var tiles: [TileCoordinate] = []
        
        for zoom in minZoom...maxZoom {
            let minTileX = longitudeToTileX(bounds.southWest.longitude, zoom: zoom)
            let maxTileX = longitudeToTileX(bounds.northEast.longitude, zoom: zoom)
            let minTileY = latitudeToTileY(bounds.northEast.latitude, zoom: zoom)
            let maxTileY = latitudeToTileY(bounds.southWest.latitude, zoom: zoom)
            
            for x in minTileX...maxTileX {
                for y in minTileY...maxTileY {
                    tiles.append(TileCoordinate(x: x, y: y, zoom: zoom))
                }
            }
        }
        
        return tiles
    }
    
    private func longitudeToTileX(_ longitude: Double, zoom: Int) -> Int {
        return Int(floor((longitude + 180.0) / 360.0 * pow(2.0, Double(zoom))))
    }
    
    private func latitudeToTileY(_ latitude: Double, zoom: Int) -> Int {
        let latRad = latitude * .pi / 180.0
        return Int(floor((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * pow(2.0, Double(zoom))))
    }
    
    // MARK: - Tile Buffer Processing
    
    private func processTileBuffer(for mapId: String) {
        guard activeDownloads[mapId]?.isActive == true else { return }
        guard isProcessingBuffer[mapId] != true else { return }
        
        isProcessingBuffer[mapId] = true
        
        let buffer = pendingTiles[mapId] ?? []
        guard !buffer.isEmpty else {
            isProcessingBuffer[mapId] = false
            checkDownloadCompletion(for: mapId)
            return
        }
        
        let tilesToProcess = Array(buffer.prefix(tileBufferSize))
        pendingTiles[mapId] = Array(buffer.dropFirst(tileBufferSize))
        
        for tile in tilesToProcess {
            downloadTile(tile, for: mapId)
        }
        
        isProcessingBuffer[mapId] = false
    }
    
    private func suspendTileBuffer(for mapId: String) {
        let remaining = pendingTiles[mapId] ?? []
        var suspended = suspendedTileBuffers[mapId] ?? []
        suspended.append(contentsOf: remaining)
        suspendedTileBuffers[mapId] = suspended
        pendingTiles[mapId] = []
    }
    
    private func resumeTileBuffer(for mapId: String) {
        let suspended = suspendedTileBuffers[mapId] ?? []
        var pending = pendingTiles[mapId] ?? []
        pending.append(contentsOf: suspended)
        pendingTiles[mapId] = pending
        suspendedTileBuffers[mapId] = []
    }
    
    // MARK: - Map Package Signature Verification
    // P0-FIX: Verify map packages against tampering using ECDSA signatures
    
    /// Verify downloaded map package signature using map provider's public key
    /// Returns true if signature is valid or if no signature is provided (backward compatibility)
    func verifyMapPackageSignature(mapId: String, data: Data, signature: Data?, providerPublicKey: P256.Signing.PublicKey?) -> Bool {
        guard let signature = signature, let publicKey = providerPublicKey else {
            // No signature provided - log warning but allow loading for backward compatibility
            Logger.shared.warn("OfflineMapManager: No signature for map package \(mapId), loading without verification")
            return true
        }
        
        // Calculate SHA256 hash of the map data
        let dataHash = SHA256.hash(data: data)
        let dataHashData = Data(dataHash)
        
        // Verify signature against the data hash
        guard let ecdsaSignature = try? P256.Signing.ECDSASignature(derRepresentation: signature) else {
            Logger.shared.error("OfflineMapManager: Invalid signature format for map \(mapId)")
            return false
        }
        
        let isValid = publicKey.isValidSignature(ecdsaSignature, for: dataHashData)
        
        if isValid {
            Logger.shared.info("OfflineMapManager: Map package \(mapId) signature verified")
        } else {
            Logger.shared.error("OfflineMapManager: Map package \(mapId) signature verification FAILED - possible tampering!")
        }
        
        return isValid
    }
    
    /// Sign map package data for P2P sharing (uses local private key)
    func signMapPackageData(mapId: String, data: Data) -> Data? {
        guard let signingKey = IdentityManager.shared.getPrivateKeyForSigning() else {
            Logger.shared.error("OfflineMapManager: No signing key available for map \(mapId)")
            return nil
        }
        
        let dataHash = SHA256.hash(data: data)
        let dataHashData = Data(dataHash)
        
        guard let signature = try? signingKey.signature(for: dataHashData) else {
            Logger.shared.error("OfflineMapManager: Failed to sign map package \(mapId)")
            return nil
        }
        
        return signature.derRepresentation
    }
    
    // MARK: - Tile Download
    
    private func downloadTile(_ tile: TileCoordinate, for mapId: String) {
        guard let mapInfo = currentMapInfo[mapId] else { return }
        
        guard let tileURL = buildTileURL(for: tile, mapInfo: mapInfo) else {
            // URL构建失败，标记为失败
            handleTileDownloadFailure(tile: tile, mapId: mapId, task: TileDownloadTask(
                coordinate: tile,
                url: URL(string: "about:blank")!,
                state: .downloading,
                data: nil,
                bytesDownloaded: 0
            ), error: NSError(domain: "OfflineMapManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid tile URL"]))
            return
        }

        var task = TileDownloadTask(
            coordinate: tile,
            url: tileURL,
            state: .downloading,
            data: nil,
            bytesDownloaded: 0
        )

        downloadTasks[tile.key] = task

        var request = URLRequest(url: tileURL)
        request.httpMethod = "GET"
        // P0-FIX: Ensure HTTPS is used (already in URL but verify)
        if tileURL.scheme != "https" {
            Logger.shared.warn("OfflineMapManager: Non-HTTPS tile URL detected: \(tileURL)")
        }

        if let offset = downloadOffsets[mapId], offset > 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }

        let downloadTask = urlSession.dataTask(with: request) { [weak self] data, response, error in
            self?.handleTileDownloadCompletion(tile: tile, mapId: mapId, data: data, response: response, error: error)
        }

        downloadTasks[tile.key] = task
        downloadTask.resume()
    }
    
    private func buildTileURL(for tile: TileCoordinate, mapInfo: OfflineMapInfo) -> URL? {
        // P0-FIX: Use HTTPS for secure tile download (yanfa.md 3.7.2 防篡改要求)
        let baseURL = "https://tiles.example.com/\(mapInfo.mapType.rawValue)"
        guard let url = URL(string: "\(baseURL)/\(tile.zoom)/\(tile.x)/\(tile.y).png") else {
            Logger.shared.error("OfflineMapManager: Invalid tile URL constructed for tile (\(tile.x), \(tile.y), \(tile.zoom))")
            return nil
        }
        return url
    }
    
    private func handleTileDownloadCompletion(tile: TileCoordinate, mapId: String, data: Data?, response: URLResponse?, error: Error?) {
        guard var task = downloadTasks[tile.key] else { return }
        
        if let error = error {
            handleTileDownloadFailure(tile: tile, mapId: mapId, task: task, error: error)
            return
        }
        
        guard let data = data else {
            handleTileDownloadFailure(tile: tile, mapId: mapId, task: task, error: NSError(domain: "OfflineMapManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"]))
            return
        }
        
        task.data = data
        task.bytesDownloaded = Int64(data.count)
        task.state = .completed
        downloadTasks[tile.key] = task
        
        saveTileToFile(tile: tile, mapId: mapId, data: data)
        updateDownloadProgress(mapId: mapId, tile: tile, bytes: Int64(data.count))
        
        downloadQueue.async { [weak self] in
            self?.processTileBuffer(for: mapId)
        }
    }
    
    private func handleTileDownloadFailure(tile: TileCoordinate, mapId: String, task: TileDownloadTask, error: Error) {
        var mutableTask = task
        var failed = failedTiles[mapId] ?? []
        
        if (downloadTasks[tile.key] ?? task).state != .failed("") {
            failed.insert(tile)
            failedTiles[mapId] = failed
            mutableTask.state = .failed(error.localizedDescription)
            downloadTasks[tile.key] = mutableTask
            
            downloadQueue.async { [weak self] in
                self?.processTileBuffer(for: mapId)
            }
        }
    }
    
    // MARK: - File Operations
    
    private func saveTileToFile(tile: TileCoordinate, mapId: String, data: Data) {
        fileQueue.async { [weak self] in
            guard let self = self else { return }
            
            let mapPath = self.documentsPath.appendingPathComponent(mapId)
            let zoomPath = mapPath.appendingPathComponent("\(tile.zoom)")
            let tilePath = zoomPath.appendingPathComponent("\(tile.x)_\(tile.y).png")
            
            if !self.fileManager.fileExists(atPath: zoomPath.path) {
                try? self.fileManager.createDirectory(at: zoomPath, withIntermediateDirectories: true)
            }
            
            try? data.write(to: tilePath)
        }
    }
    
    private func loadTileFromFile(tile: TileCoordinate, mapId: String) -> Data? {
        let mapPath = documentsPath.appendingPathComponent(mapId)
        let tilePath = mapPath.appendingPathComponent("\(tile.zoom)/\(tile.x)_\(tile.y).png")
        return try? Data(contentsOf: tilePath)
    }
    
    // MARK: - Progress Updates
    
    private func updateDownloadProgress(mapId: String, tile: TileCoordinate, bytes: Int64) {
        downloadQueue.async { [weak self] in
            guard let self = self else { return }
            
            var completed = self.completedTiles[mapId] ?? []
            completed.insert(tile)
            self.completedTiles[mapId] = completed
            
            var downloaded = self.currentDownloadedCount[mapId] ?? 0
            downloaded += 1
            self.currentDownloadedCount[mapId] = downloaded
            
            var bytesDownloaded = self.downloadedBytes[mapId] ?? 0
            bytesDownloaded += bytes
            self.downloadedBytes[mapId] = bytesDownloaded
            
            let progress = self.getProgress(for: mapId)
            self.downloadProgress[mapId] = progress
            
            self.persistProgress(for: mapId)
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.offlineMapManager(self, didUpdateProgress: progress)
            }
        }
    }
    
    private func checkDownloadCompletion(for mapId: String) {
        let pending = pendingTiles[mapId] ?? []
        let suspended = suspendedTileBuffers[mapId] ?? []
        
        if pending.isEmpty && suspended.isEmpty {
            let completed = completedTiles[mapId] ?? []
            let failed = failedTiles[mapId] ?? []
            let total = currentTileCount[mapId] ?? 0
            
            if failed.isEmpty || failed.count < total {
                activeDownloads[mapId] = .completed
                
                if let mapInfo = currentMapInfo[mapId] {
                    let updatedMapInfo = OfflineMapInfo(
                        mapId: mapInfo.mapId,
                        name: mapInfo.name,
                        version: mapInfo.version,
                        tileCount: mapInfo.tileCount,
                        downloadedTileCount: completed.count,
                        fileSize: downloadedBytes[mapId] ?? 0,
                        downloadedSize: downloadedBytes[mapId] ?? 0,
                        bounds: mapInfo.bounds,
                        minZoom: mapInfo.minZoom,
                        maxZoom: mapInfo.maxZoom,
                        mapType: mapInfo.mapType,
                        coordinateSystem: mapInfo.coordinateSystem,
                        lastUpdated: Date()
                    )
                    
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.offlineMapManager(self, didCompleteMap: updatedMapInfo)
                    }
                }
            } else {
                let errorMessage = "Failed to download \(failed.count) tiles"
                activeDownloads[mapId] = .failed(errorMessage)
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    let error = NSError(domain: "OfflineMapManager", code: -2, userInfo: [NSLocalizedDescriptionKey: errorMessage])
                    self.delegate?.offlineMapManager(self, didFailMap: mapId, error: error)
                }
            }
        }
    }
    
    // MARK: - Persistence
    
    private func persistProgress(for mapId: String) {
        let progress = DownloadProgressRecord(
            mapId: mapId,
            totalTiles: currentTileCount[mapId] ?? 0,
            downloadedTileCount: currentDownloadedCount[mapId] ?? 0,
            totalBytes: totalBytes[mapId] ?? 0,
            downloadedBytes: downloadedBytes[mapId] ?? 0,
            pendingTiles: pendingTiles[mapId] ?? [],
            completedTiles: Array(completedTiles[mapId] ?? []),
            failedTiles: Array(failedTiles[mapId] ?? []),
            lastUpdated: Date(),
            downloadOffset: downloadOffsets[mapId] ?? 0
        )
        
        var allProgress = loadAllProgressRecords()
        allProgress[mapId] = progress
        
        if let data = try? JSONEncoder().encode(allProgress) {
            userDefaults.set(data, forKey: progressKey)
        }
    }
    
    private func loadPersistedProgress() {
        let allProgress = loadAllProgressRecords()
        
        for (mapId, progress) in allProgress {
            currentTileCount[mapId] = progress.totalTiles
            currentDownloadedCount[mapId] = progress.downloadedTileCount
            totalBytes[mapId] = progress.totalBytes
            downloadedBytes[mapId] = progress.downloadedBytes
            pendingTiles[mapId] = progress.pendingTiles
            completedTiles[mapId] = Set(progress.completedTiles)
            failedTiles[mapId] = Set(progress.failedTiles)
            downloadOffsets[mapId] = progress.downloadOffset
        }
    }
    
    private func loadPersistedProgressForMap(_ mapId: String) {
        let allProgress = loadAllProgressRecords()
        
        if let progress = allProgress[mapId] {
            currentTileCount[mapId] = progress.totalTiles
            currentDownloadedCount[mapId] = progress.downloadedTileCount
            totalBytes[mapId] = progress.totalBytes
            downloadedBytes[mapId] = progress.downloadedBytes
            pendingTiles[mapId] = progress.pendingTiles
            completedTiles[mapId] = Set(progress.completedTiles)
            failedTiles[mapId] = Set(progress.failedTiles)
            downloadOffsets[mapId] = progress.downloadOffset
        }
    }
    
    private func loadAllProgressRecords() -> [String: DownloadProgressRecord] {
        guard let data = userDefaults.data(forKey: progressKey),
              let records = try? JSONDecoder().decode([String: DownloadProgressRecord].self, from: data) else {
            return [:]
        }
        return records
    }
    
    private func clearPersistedProgress(for mapId: String) {
        var allProgress = loadAllProgressRecords()
        allProgress.removeValue(forKey: mapId)
        
        if let data = try? JSONEncoder().encode(allProgress) {
            userDefaults.set(data, forKey: progressKey)
        }
    }
    
    // MARK: - Offline Data Preparation
    
    func prepareOfflineData() {
        downloadQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Ensure offline maps directory exists
            self.createOfflineMapsDirectory()
            
            // Preload any existing map data into memory
            if let contents = try? FileManager.default.contentsOfDirectory(at: self.documentsPath, includingPropertiesForKeys: nil) {
                for mapFolder in contents where mapFolder.hasDirectoryPath {
                    let mapId = mapFolder.lastPathComponent
                    self.loadPersistedProgressForMap(mapId)
                }
            }
            
            // Initialize cache manager
            _ = MapCacheManager.shared
        }
    }
    
    // MARK: - Sync Operation
    
    func createMapSyncOperation() -> Operation {
        let operation = BlockOperation { [weak self] in
            guard let self = self else { return }
            
            // Sync all downloaded maps with cloud backup if available
            let mapsToSync = self.availableOfflineMaps.filter { $0.isComplete }
            
            for mapInfo in mapsToSync {
                let mapPath = self.documentsPath.appendingPathComponent(mapInfo.mapId)
                
                if FileManager.default.fileExists(atPath: mapPath.path) {
                    // Trigger sync via MeshService or CloudService
                    // For now, just verify the map is complete
                    self.verifyMapIntegrity(mapId: mapInfo.mapId)
                }
            }
        }
        
        operation.qualityOfService = .background
        return operation
    }
    
    private func verifyMapIntegrity(mapId: String) {
        // Verify downloaded tiles match expected count
        guard let mapInfo = currentMapInfo[mapId] else { return }
        
        let mapPath = documentsPath.appendingPathComponent(mapId)
        guard let contents = try? FileManager.default.contentsOfDirectory(at: mapPath, includingPropertiesForKeys: nil) else { return }
        
        var totalTiles = 0
        for zoomFolder in contents {
            if let zoomContents = try? FileManager.default.contentsOfDirectory(at: zoomFolder, includingPropertiesForKeys: nil) {
                totalTiles += zoomContents.filter { $0.pathExtension == "png" }.count
            }
        }
        
        if totalTiles >= mapInfo.tileCount {
            activeDownloads[mapId] = .completed
        }
    }
    
    private var availableOfflineMaps: [OfflineMapInfo] {
        return currentMapInfo.values.filter { mapInfo in
            activeDownloads[mapInfo.mapId] == .completed
        }
    }
    
    // MARK: - Cache Management
    
    /// 清理缓存（内存警告时调用）
    func clearCache() {
        downloadQueue.async { [weak self] in
            guard let self = self else { return }
            // 清理暂停的下载任务
            for (mapId, state) in self.activeDownloads {
                if state.isPaused {
                    self.suspendedTileBuffers.removeValue(forKey: mapId)
                }
            }
            // 清理已完成的下载任务数据
            self.downloadTasks = self.downloadTasks.filter { $0.value.state.isActive }
            Logger.shared.info("OfflineMapManager: Cache cleared")
        }
    }

    /// Get list of downloaded offline map regions
    func getDownloadedRegions() -> [String]? {
        // Read from UserDefaults where region info is stored
        return UserDefaults.standard.stringArray(forKey: "offlineMap.downloadedRegions")
    }
    
    /// Get list of available regions for download
    func getAvailableRegions() -> [OfflineMapInfo] {
        // Predefined available regions with bounds
        return [
            OfflineMapInfo(
                mapId: "zhejiang_province",
                name: "Zhejiang Province",
                version: "1.0",
                tileCount: 15000,
                downloadedTileCount: 0,
                fileSize: 50_000_000,
                downloadedSize: 0,
                bounds: MapBounds(
                    northEast: Coordinate2D(latitude: 31.18, longitude: 122.98),
                    southWest: Coordinate2D(latitude: 27.18, longitude: 118.88)
                ),
                minZoom: 6,
                maxZoom: 14,
                mapType: .standard,
                coordinateSystem: .gcj02,
                lastUpdated: Date()
            ),
            OfflineMapInfo(
                mapId: "hangzhou_metro",
                name: "Hangzhou Metro Area",
                version: "1.0",
                tileCount: 8000,
                downloadedTileCount: 0,
                fileSize: 25_000_000,
                downloadedSize: 0,
                bounds: MapBounds(
                    northEast: Coordinate2D(latitude: 30.52, longitude: 120.48),
                    southWest: Coordinate2D(latitude: 30.02, longitude: 119.98)
                ),
                minZoom: 8,
                maxZoom: 16,
                mapType: .standard,
                coordinateSystem: .gcj02,
                lastUpdated: Date()
            ),
            OfflineMapInfo(
                mapId: "west_lake_district",
                name: "West Lake District",
                version: "1.0",
                tileCount: 3000,
                downloadedTileCount: 0,
                fileSize: 10_000_000,
                downloadedSize: 0,
                bounds: MapBounds(
                    northEast: Coordinate2D(latitude: 30.28, longitude: 120.18),
                    southWest: Coordinate2D(latitude: 30.22, longitude: 120.12)
                ),
                minZoom: 10,
                maxZoom: 18,
                mapType: .standard,
                coordinateSystem: .gcj02,
                lastUpdated: Date()
            ),
            OfflineMapInfo(
                mapId: "shanghai_province",
                name: "Shanghai City",
                version: "1.0",
                tileCount: 12000,
                downloadedTileCount: 0,
                fileSize: 40_000_000,
                downloadedSize: 0,
                bounds: MapBounds(
                    northEast: Coordinate2D(latitude: 31.40, longitude: 122.08),
                    southWest: Coordinate2D(latitude: 30.70, longitude: 121.08)
                ),
                minZoom: 6,
                maxZoom: 14,
                mapType: .standard,
                coordinateSystem: .gcj02,
                lastUpdated: Date()
            ),
            OfflineMapInfo(
                mapId: "beijing_city",
                name: "Beijing City",
                version: "1.0",
                tileCount: 14000,
                downloadedTileCount: 0,
                fileSize: 45_000_000,
                downloadedSize: 0,
                bounds: MapBounds(
                    northEast: Coordinate2D(latitude: 41.05, longitude: 117.50),
                    southWest: Coordinate2D(latitude: 39.45, longitude: 115.40)
                ),
                minZoom: 6,
                maxZoom: 14,
                mapType: .standard,
                coordinateSystem: .gcj02,
                lastUpdated: Date()
            )
        ]
    }
}

// MARK: - URLSessionDelegate

extension OfflineMapManager: URLSessionDataDelegate {
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let request = dataTask.originalRequest,
              let url = request.url else { return }
        
        let tileKey = url.lastPathComponent.replacingOccurrences(of: ".png", with: "")
        let components = tileKey.split(separator: "_")
        
        if components.count >= 3,
           let zoom = Int(components[0]),
           let x = Int(components[1]),
           let y = Int(components[2]) {
            let coordinate = TileCoordinate(x: x, y: y, zoom: zoom)
            
            if var task = downloadTasks[coordinate.key] {
                task.data?.append(data)
                task.bytesDownloaded += Int64(data.count)
                downloadTasks[coordinate.key] = task
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let request = task.originalRequest,
              let url = request.url else { return }
        
        let tileKey = url.lastPathComponent.replacingOccurrences(of: ".png", with: "")
        let components = tileKey.split(separator: "_")
        
        if components.count >= 3,
           let zoom = Int(components[0]),
           let x = Int(components[1]),
           let y = Int(components[2]) {
            let coordinate = TileCoordinate(x: x, y: y, zoom: zoom)
            
            if let task = downloadTasks[coordinate.key], task.state != .completed {
                downloadQueue.async { [weak self] in
                    self?.handleTileDownloadCompletion(tile: coordinate, mapId: "", data: task.data, response: nil, error: error)
                }
            }
        }
    }
}
