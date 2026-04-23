import Foundation
import Network
import Combine

enum WiFiServiceError: Error {
    case connectionFailed
    case listenerFailed
    case invalidConfiguration
    case notConnected
}

protocol WiFiServiceDelegate: AnyObject {
    func wifiService(_ service: WiFiService, didReceiveData data: Data, from endpoint: NWEndpoint)
    func wifiService(_ service: WiFiService, didChangeState state: NWConnection.State)
    func wifiService(_ service: WiFiService, didEncounterError error: WiFiServiceError)
}

final class WiFiService {
    static let shared = WiFiService()

    
    weak var delegate: WiFiServiceDelegate?
    
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.mesh.wifi.service", qos: .userInitiated)
    
    private let host: String
    private let port: UInt16
    
    var connectionState: NWConnection.State = .cancelled
    
    init(host: String = "0.0.0.0", port: UInt16 = 8080) {
        self.host = host
        self.port = port
    }

    func configure() {
        // Configuration placeholder - actual setup deferred to startListening
    }

    func startListening() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        
        listener?.stateUpdateHandler = { [weak self] state in
            self?.handleListenerState(state)
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        
        listener?.start(queue: queue)
    }
    
    func stopListening() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
    }
    
    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            Logger.shared.info("WiFiService: Listener ready on port \(port)")
        case .failed(let error):
            Logger.shared.error("WiFiService: Listener failed with error: \(error)")
            delegate?.wifiService(self, didEncounterError: .listenerFailed)
        case .cancelled:
            Logger.shared.debug("WiFiService: Listener cancelled")
        default:
            break
        }
    }
    
    // P1-FIX: 连接认证状态
    private var authenticatedConnections: Set<ObjectIdentifier> = []
    private let authTimeout: TimeInterval = 10.0
    
    private func handleNewConnection(_ connection: NWConnection) {
        // P1-FIX: 不直接接受连接，先进行认证握手
        connection.stateUpdateHandler = { [weak self] state in
            self?.handleConnectionState(state, connection: connection)
        }
        
        connection.start(queue: queue)
        
        // 发送认证挑战
        sendAuthChallenge(to: connection)
    }
    
    // P1-FIX: 发送认证挑战
    private func sendAuthChallenge(to connection: NWConnection) {
        let challenge = AuthChallenge(
            timestamp: Date().timeIntervalSince1970,
            nonce: UUID().uuidString
        )
        
        guard let challengeData = try? JSONEncoder().encode(challenge) else { return }
        
        var packet = Data()
        packet.append(UInt8(0x01)) // 认证挑战类型
        packet.append(challengeData)
        
        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            if let error = error {
                Logger.shared.error("WiFiService: Auth challenge failed - \(error)")
                connection.cancel()
                return
            }
            // 等待认证响应
            self?.waitForAuthResponse(from: connection, challenge: challenge)
        })
    }
    
    // P1-FIX: 等待认证响应
    private func waitForAuthResponse(from connection: NWConnection, challenge: AuthChallenge) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let data = data, !data.isEmpty {
                if self.verifyAuthResponse(data, challenge: challenge, connection: connection) {
                    // 认证成功，添加到连接列表
                    self.connections.append(connection)
                    self.authenticatedConnections.insert(ObjectIdentifier(connection))
                    Logger.shared.info("WiFiService: Connection authenticated")
                    self.receiveData(on: connection)
                } else {
                    Logger.shared.warn("WiFiService: Authentication failed, rejecting connection")
                    connection.cancel()
                }
            }
            
            if isComplete || error != nil {
                connection.cancel()
            }
        }
    }
    
    // P1-FIX: 验证认证响应
    private func verifyAuthResponse(_ data: Data, challenge: AuthChallenge, connection: NWConnection) -> Bool {
        guard data.count > 1, data[0] == 0x02 else { return false }
        
        let responseData = data.dropFirst()
        guard let response = try? JSONDecoder().decode(AuthResponse.self, from: responseData) else {
            return false
        }
        
        // 验证时间戳在合理范围内
        let now = Date().timeIntervalSince1970
        guard abs(response.timestamp - now) < 60 else { return false }
        
        // 验证挑战nonce匹配
        guard response.challengeNonce == challenge.nonce else { return false }
        
        // 验证签名（如果有节点公钥）
        if let nodeId = response.nodeId,
           let publicKey = IdentityManager.shared.getPublicKey(for: nodeId) {
            let signedData = "\(response.challengeNonce):\(response.timestamp)".data(using: .utf8) ?? Data()
            return CryptoEngine.shared.verify(
                signature: response.signature,
                data: signedData,
                publicKey: publicKey
            )
        }
        
        // 无签名时，仅验证基本信息（降级模式）
        return response.timestamp > 0
    }
    
    // P1-FIX: 认证协议结构
    struct AuthChallenge: Codable {
        let timestamp: TimeInterval
        let nonce: String
    }
    
    struct AuthResponse: Codable {
        let timestamp: TimeInterval
        let challengeNonce: String
        let nodeId: String?
        let signature: Data
    }
    
    private func handleConnectionState(_ state: NWConnection.State, connection: NWConnection) {
        switch state {
        case .ready:
            receiveData(on: connection)
        case .failed(let error):
            Logger.shared.error("WiFiService: Connection failed - \(error)")
            removeConnection(connection)
        case .cancelled:
            removeConnection(connection)
        default:
            break
        }
        
        connectionState = state
        delegate?.wifiService(self, didChangeState: state)
    }
    
    private func receiveData(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let data = data, !data.isEmpty {
                self.delegate?.wifiService(self, didReceiveData: data, from: connection.endpoint)
            }
            
            if let error = error {
                Logger.shared.error("WiFiService: Receive error - \(error)")
                return
            }
            
            if isComplete {
                connection.cancel()
            } else {
                self.receiveData(on: connection)
            }
        }
    }
    
    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
    }
    
    func send(data: Data, to endpoint: NWEndpoint, completion: @escaping (Error?) -> Void) {
        guard let connection = connections.first(where: { $0.endpoint == endpoint }) else {
            completion(WiFiServiceError.notConnected)
            return
        }
        
        connection.send(content: data, completion: .contentProcessed { error in
            completion(error)
        })
    }
    
    func broadcast(data: Data) {
        for connection in connections {
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    Logger.shared.error("WiFiService: Broadcast error - \(error)")
                }
            })
        }
    }
    
    func createOutgoingConnection(to endpoint: NWEndpoint) -> NWConnection {
        let connection = NWConnection(to: endpoint, using: .tcp)
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            self.connectionState = state
            self.delegate?.wifiService(self, didChangeState: state)
        }
        
        connection.start(queue: queue)
        connections.append(connection)
        
        return connection
    }
    
    deinit {
        // 确保所有连接都被取消
        connections.forEach { $0.cancel() }
        connections.removeAll()
        listener?.cancel()
        listener = nil
    }
}