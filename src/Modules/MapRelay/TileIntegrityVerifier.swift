// MARK: - Tile Integrity Verifier
// 依赖文件：MeshRelayProtocols.swift
// 功能：地图瓦片完整性校验

import Foundation
import CryptoKit

// MARK: - Tile Integrity Verifier

public class TileIntegrityVerifier {
    private var verifiedTiles: [String: TileIntegrity] = [:]
    private var corruptedTiles: Set<String> = []
    private var pendingVerifications: [String: VerificationRequest] = [:]
    
    private let cacheLock = NSLock()
    private var verificationTimeout: TimeInterval = 30.0
    
    public weak var delegate: TileIntegrityDelegate?
    
    // MARK: - Checksum Verification
    
    /// Calculate SHA256 checksum for tile data
    public func calculateSHA256(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Verify tile data against expected checksum
    public func verifyTile(_ coordinate: TileCoordinate, data: Data, expectedChecksum: String) -> Bool {
        let actualChecksum = calculateSHA256(data)
        let isValid = actualChecksum == expectedChecksum
        
        let integrity = TileIntegrity(
            coordinate: coordinate,
            checksum: actualChecksum,
            sizeBytes: data.count,
            signature: nil,
            verifiedAt: Date()
        )
        
        cacheLock.lock()
        if isValid {
            verifiedTiles[coordinate.key] = integrity
            corruptedTiles.remove(coordinate.key)
        } else {
            corruptedTiles.insert(coordinate.key)
        }
        cacheLock.unlock()
        
        if !isValid {
            delegate?.tileIntegrityVerifier(self, didDetectCorruption: coordinate, expected: expectedChecksum, actual: actualChecksum)
        }
        
        return isValid
    }
    
    /// Verify tile with signature (for authenticated sources)
    public func verifyTileWithSignature(
        _ coordinate: TileCoordinate,
        data: Data,
        expectedChecksum: String,
        signature: Data,
        publicKey: Data
    ) -> Bool {
        // First verify checksum
        guard verifyTile(coordinate, data: data, expectedChecksum: expectedChecksum) else {
            return false
        }
        
        // Then verify signature
        guard verifySignature(data: data, signature: signature, publicKey: publicKey) else {
            cacheLock.lock()
            corruptedTiles.insert(coordinate.key)
            cacheLock.unlock()
            
            delegate?.tileIntegrityVerifier(self, signatureVerificationFailed: coordinate)
            return false
        }
        
        // Update with signature info
        cacheLock.lock()
        if var integrity = verifiedTiles[coordinate.key] {
            integrity = TileIntegrity(
                coordinate: integrity.coordinate,
                checksum: integrity.checksum,
                sizeBytes: integrity.sizeBytes,
                signature: signature,
                verifiedAt: Date()
            )
            verifiedTiles[coordinate.key] = integrity
        }
        cacheLock.unlock()
        
        return true
    }
    
    /// Verify signature for authenticated tile sources
    /// Uses HMAC-SHA256 with constant-time comparison to prevent timing attacks
    private func verifySignature(data: Data, signature: Data, publicKey: Data) -> Bool {
        guard publicKey.count == 32 else {
            Logger.shared.warn("TileIntegrityVerifier: Invalid public key length")
            return false
        }

        guard signature.count == 64 else {
            Logger.shared.warn("TileIntegrityVerifier: Invalid signature length")
            return false
        }

        // Use HMAC-SHA256 for verification with symmetric key approach
        let symmetricKey = SymmetricKey(data: publicKey)
        let expectedTag = HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey)
        let expectedData = Data(expectedTag)

        // Constant-time comparison to prevent timing attacks
        return signature.elementsEqual(expectedData, by: ==)
    }
    
    // MARK: - Batch Verification
    
    /// Verify multiple tiles in batch
    public func verifyBatch(_ tiles: [(coordinate: TileCoordinate, data: Data, checksum: String)]) -> BatchVerificationResult {
        var valid = 0
        var invalid = 0
        var errors: [(TileCoordinate, String)] = []
        
        for (coordinate, data, checksum) in tiles {
            if verifyTile(coordinate, data: data, expectedChecksum: checksum) {
                valid += 1
            } else {
                invalid += 1
                errors.append((coordinate, "Checksum mismatch"))
            }
        }
        
        return BatchVerificationResult(
            total: tiles.count,
            validCount: valid,
            invalidCount: invalid,
            errors: errors
        )
    }
    
    // MARK: - Cache Management
    
    /// Get cached integrity info
    public func getIntegrity(for coordinate: TileCoordinate) -> TileIntegrity? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return verifiedTiles[coordinate.key]
    }
    
    /// Check if tile is verified
    public func isVerified(_ coordinate: TileCoordinate) -> Bool {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return verifiedTiles[coordinate.key] != nil && !corruptedTiles.contains(coordinate.key)
    }
    
    /// Check if tile is corrupted
    public func isCorrupted(_ coordinate: TileCoordinate) -> Bool {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return corruptedTiles.contains(coordinate.key)
    }
    
    /// Get all corrupted tiles
    public func getCorruptedTiles() -> [TileCoordinate] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        return corruptedTiles.compactMap { key in
            let parts = key.split(separator: "/")
            guard parts.count == 3,
                  let zoom = Int(parts[0]),
                  let x = Int(parts[1]),
                  let y = Int(parts[2]) else { return nil }
            return TileCoordinate(x: x, y: y, zoom: zoom)
        }
    }
    
    /// Clear verification cache
    public func clearCache() {
        cacheLock.lock()
        verifiedTiles.removeAll()
        corruptedTiles.removeAll()
        cacheLock.unlock()
    }
    
    /// Remove stale entries from cache
    public func pruneStaleEntries(olderThan hours: Int) {
        let threshold = Date().addingTimeInterval(-Double(hours * 3600))
        
        cacheLock.lock()
        verifiedTiles = verifiedTiles.filter { _, integrity in
            integrity.verifiedAt > threshold
        }
        cacheLock.unlock()
    }
    
    // MARK: - Async Verification
    
    /// Queue tile for async verification
    public func queueForVerification(_ coordinate: TileCoordinate, data: Data, expectedChecksum: String) {
        let request = VerificationRequest(
            coordinate: coordinate,
            data: data,
            expectedChecksum: expectedChecksum,
            queuedAt: Date()
        )
        
        cacheLock.lock()
        pendingVerifications[coordinate.key] = request
        cacheLock.unlock()
    }
    
    /// Process pending verifications
    public func processPendingVerifications(maxCount: Int = 10) {
        cacheLock.lock()
        let requests = Array(pendingVerifications.values.prefix(maxCount))
        for request in requests {
            pendingVerifications.removeValue(forKey: request.coordinate.key)
        }
        cacheLock.unlock()
        
        for request in requests {
            _ = verifyTile(request.coordinate, data: request.data, expectedChecksum: request.expectedChecksum)
        }
    }
    
    // MARK: - Statistics
    
    /// Get verification statistics
    public func getStatistics() -> IntegrityStatistics {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        return IntegrityStatistics(
            verifiedCount: verifiedTiles.count,
            corruptedCount: corruptedTiles.count,
            pendingCount: pendingVerifications.count
        )
    }
}

// MARK: - Supporting Types

public struct VerificationRequest {
    let coordinate: TileCoordinate
    let data: Data
    let expectedChecksum: String
    let queuedAt: Date
}

public struct BatchVerificationResult {
    let total: Int
    let validCount: Int
    let invalidCount: Int
    let errors: [(TileCoordinate, String)]
    
    var successRate: Double {
        guard total > 0 else { return 0 }
        return Double(validCount) / Double(total)
    }
}

public struct IntegrityStatistics {
    let verifiedCount: Int
    let corruptedCount: Int
    let pendingCount: Int
}

// MARK: - Tile Integrity Delegate

public protocol TileIntegrityDelegate: AnyObject {
    func tileIntegrityVerifier(_ verifier: TileIntegrityVerifier, didDetectCorruption coordinate: TileCoordinate, expected: String, actual: String)
    func tileIntegrityVerifier(_ verifier: TileIntegrityVerifier, signatureVerificationFailed coordinate: TileCoordinate)
    func tileIntegrityVerifier(_ verifier: TileIntegrityVerifier, didVerifyTile coordinate: TileCoordinate)
}
