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
    
    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)
        
        connection.stateUpdateHandler = { [weak self] state in
            self?.handleConnectionState(state, connection: connection)
        }
        
        connection.start(queue: queue)
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
            if let data = data, !data.isEmpty {
                self?.delegate?.wifiService(self!, didReceiveData: data, from: connection.endpoint)
            }
            
            if let error = error {
                Logger.shared.error("WiFiService: Receive error - \(error)")
                return
            }
            
            if isComplete {
                connection.cancel()
            } else {
                self?.receiveData(on: connection)
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
            self?.connectionState = state
            self?.delegate?.wifiService(self!, didChangeState: state)
        }
        
        connection.start(queue: queue)
        connections.append(connection)
        
        return connection
    }
    
    deinit {
        stopListening()
    }
}