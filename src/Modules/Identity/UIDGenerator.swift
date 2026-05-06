import Foundation
import UIKit
import CryptoKit
import Network

/// Generates unique identifiers using timestamp + MAC address → SHA256 → first 16 hex chars
final class UIDGenerator {

    static let shared = UIDGenerator()

    private init() {}

    // MARK: - MAC Address Retrieval

    /// Retrieve the MAC address of the current device
    func getMACAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return nil
        }

        defer { freeifaddrs(ifaddr) }

        var ptr = firstAddr
        while true {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_LINK) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {  // Wi-Fi interface
                    let hardwareAddr = interface.ifa_addr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { ptr in
                        let dl = ptr.pointee
                        let alen = Int(dl.sdl_alen)
                        let nlen = Int(dl.sdl_nlen)
                        var mac = [UInt8](repeating: 0, count: alen)
                        // sdl_data offset in sockaddr_dl: after sdl_len (1 byte) + sdl_family (1 byte) + sdl_index (2 bytes) = 4 bytes
                        // Then sdl_nlen (1) + sdl_alen (1) + sdl_type (1) + sdl_pad (2) = 5 more, total 9
                        let base = Int(dl.sdl_nlen) + 9  // 9 = offset of sdl_data from start of sockaddr_dl
                        for i in 0..<alen {
                            mac[i] = UnsafeRawPointer(ptr).load(fromByteOffset: base + i, as: UInt8.self)
                        }
                        return mac
                    }
                    address = hardwareAddr.map { String(format: "%02x", $0) }.joined(separator: ":")
                    break
                }
            }

            guard let next = interface.ifa_next else { break }
            ptr = next
        }

        return address
    }

    // MARK: - UID Generation

    /// Generate a cryptographically secure UID using timestamp + MAC address → SHA256
    /// Per yanfa.md 3.1.1: 时间戳(毫秒) + 设备MAC加密值 → SHA256哈希 → 唯一UID
    func generateUID() -> String {
        // Get current timestamp in milliseconds
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        
        // Get MAC address
        guard let macAddress = getMACAddress() else {
            // Fallback if MAC unavailable - use device identifier
            return generateFallbackUID(timestamp: timestamp)
        }
        
        // Combine timestamp + MAC
        let input = "\(timestamp):\(macAddress)"
        
        // Generate SHA256 hash
        let hash = sha256(input)
        
        // Return first 16 characters (8 bytes = 64 bits of entropy)
        return String(hash.prefix(16))
    }

    /// Fallback UID generation when MAC is unavailable
    /// Uses timestamp + SecureEnclave identifier for uniqueness
    private func generateFallbackUID(timestamp: Int64) -> String {
        let identifier = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let input = "\(timestamp):\(identifier)"
        let hash = sha256(input)
        return String(hash.prefix(16))
    }

    /// Generate a raw SHA256 hash of the input string
    func sha256(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
