import Foundation
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

    /// Generate a UID from timestamp (ms) + MAC address, hashed with SHA256
    /// Returns the first 16 hex characters (32 bits)
    func generateUID() -> String {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let macAddress = getMACAddress() ?? "00:00:00:00:00:00"

        let input = "\(timestamp):\(macAddress)"
        guard let data = input.data(using: .utf8) else {
            return generateFallbackUID()
        }

        let hash = SHA256.hash(data: data)
        let hexString = hash.map { String(format: "%02x", $0) }.joined()

        return String(hexString.prefix(16))
    }

    /// Fallback UID generation using only timestamp when MAC unavailable
    private func generateFallbackUID() -> String {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        guard let data = "\(timestamp)".data(using: .utf8) else {
            return String(format: "%016lx", arc4random())
        }

        let hash = SHA256.hash(data: data)
        let hexString = hash.map { String(format: "%02x", $0) }.joined()

        return String(hexString.prefix(16))
    }

    /// Generate a raw SHA256 hash of the input string
    func sha256(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
