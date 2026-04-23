import Foundation

struct RouteEntry: Codable, Equatable {
    let destination: String
    let subnetMask: String
    let gateway: String
    let interface: String
    let metric: Int
    let isEnabled: Bool
    let createdAt: Date
    
    init(destination: String, subnetMask: String, gateway: String, interface: String, metric: Int = 100, isEnabled: Bool = true) {
        self.destination = destination
        self.subnetMask = subnetMask
        self.gateway = gateway
        self.interface = interface
        self.metric = metric
        self.isEnabled = isEnabled
        self.createdAt = Date()
    }
}

// MARK: - Route Validation Error

enum RouteValidationError: Error, LocalizedError {
    case invalidMetric(Int, max: Int)
    case destinationIsLocalNode(String)
    case unknownGateway(String)
    case invalidDestinationFormat(String)
    case invalidGatewayFormat(String)
    case invalidSubnetMaskFormat(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidMetric(let metric, let max):
            return "Invalid metric \(metric): must be between 0 and \(max)"
        case .destinationIsLocalNode(let destination):
            return "Destination \(destination) cannot be the local node"
        case .unknownGateway(let gateway):
            return "Gateway \(gateway) is not a known node"
        case .invalidDestinationFormat(let destination):
            return "Invalid destination IP format: \(destination)"
        case .invalidGatewayFormat(let gateway):
            return "Invalid gateway IP format: \(gateway)"
        case .invalidSubnetMaskFormat(let mask):
            return "Invalid subnet mask format: \(mask)"
        }
    }
}

protocol RouteTableDelegate: AnyObject {
    func routeTable(_ table: RouteTable, didUpdateRoutes routes: [RouteEntry])
}

final class RouteTable {
    
    static let shared = RouteTable()
    
    weak var delegate: RouteTableDelegate?
    
    private var routes: [RouteEntry] = []
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.mesh.routetable", qos: .utility)
    private let fileManager = FileManager.default
    
    // MARK: - Route Validation Configuration
    
    /// Maximum allowed metric value for routes
    static let maxMetric: Int = 255
    
    /// Set of known node identifiers (gateways must be in this set)
    private var knownNodes: Set<String> = []
    
    /// Local node identifier - destination cannot be this value
    private var localNodeId: String?
    
    var allRoutes: [RouteEntry] {
        return routes
    }
    
    var enabledRoutes: [RouteEntry] {
        return routes.filter { $0.isEnabled }
    }
    
    // MARK: - Known Nodes Management
    
    /// Register a known node that can be used as a gateway
    func registerKnownNode(_ nodeId: String) {
        queue.async { [weak self] in
            self?.knownNodes.insert(nodeId)
        }
    }
    
    /// Unregister a known node
    func unregisterKnownNode(_ nodeId: String) {
        queue.async { [weak self] in
            self?.knownNodes.remove(nodeId)
        }
    }
    
    /// Set the local node identifier
    func setLocalNodeId(_ nodeId: String) {
        queue.async { [weak self] in
            self?.localNodeId = nodeId
        }
    }
    
    /// Check if a node is known
    func isKnownNode(_ nodeId: String) -> Bool {
        return knownNodes.contains(nodeId)
    }
    
    // MARK: - Route Validation
    
    /// Validates a route entry before adding it to the table
    /// - Parameter route: The route to validate
    /// - Returns: true if valid, false otherwise
    /// - Throws: RouteValidationError with specific validation failure reason
    func validateRoute(_ route: RouteEntry) throws -> Bool {
        // 1. Validate metric is within acceptable range
        guard route.metric >= 0 && route.metric <= RouteTable.maxMetric else {
            throw RouteValidationError.invalidMetric(route.metric, max: RouteTable.maxMetric)
        }
        
        // 2. Validate destination is not the local node
        if let localId = localNodeId, route.destination == localId {
            throw RouteValidationError.destinationIsLocalNode(route.destination)
        }
        
        // 3. Validate gateway is a known node (if known nodes are tracked)
        // Skip this check if no known nodes are registered (for backward compatibility)
        if !knownNodes.isEmpty && !knownNodes.contains(route.gateway) {
            throw RouteValidationError.unknownGateway(route.gateway)
        }
        
        // 4. Validate IP address formats
        if !isValidIPAddress(route.destination) {
            throw RouteValidationError.invalidDestinationFormat(route.destination)
        }
        
        if !isValidIPAddress(route.gateway) {
            throw RouteValidationError.invalidGatewayFormat(route.gateway)
        }
        
        if !isValidSubnetMask(route.subnetMask) {
            throw RouteValidationError.invalidSubnetMaskFormat(route.subnetMask)
        }
        
        return true
    }
    
    /// Validates a route without throwing, returning nil if valid or error if invalid
    func validateRouteSilently(_ route: RouteEntry) -> RouteValidationError? {
        do {
            _ = try validateRoute(route)
            return nil
        } catch let error as RouteValidationError {
            return error
        } catch {
            return nil
        }
    }
    
    // MARK: - IP Address Validation Helpers
    
    private func isValidIPAddress(_ ip: String) -> Bool {
        let components = ip.split(separator: ".")
        guard components.count == 4 else { return false }
        
        for component in components {
            guard let value = Int(component), value >= 0 && value <= 255 else {
                return false
            }
        }
        return true
    }
    
    private func isValidSubnetMask(_ mask: String) -> Bool {
        // Validate it's a valid IP format first
        guard isValidIPAddress(mask) else { return false }
        
        // Validate it's a valid subnet mask (contiguous 1s followed by 0s)
        guard let maskValue = ipToUInt32(mask) else { return false }
        
        // A valid subnet mask has all 1s on the left and all 0s on the right
        // Check by verifying that (mask & -mask) + mask is all 1s (0xFFFFFFFF)
        // or mask is 0 or 0xFFFFFFFF
        if maskValue == 0 || maskValue == 0xFFFFFFFF {
            return true
        }
        
        // For UInt32, use bitwise NOT + 1 to get the negative equivalent
        let complement = ~maskValue
        let lowestBit = complement & (~complement &+ 1)
        return (complement + lowestBit) == 0
    }
    
    private init() {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documentsPath.appendingPathComponent("route_table.json")
        loadRoutes()
    }
    
    func addRoute(_ route: RouteEntry) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // Validate route before adding
            if let error = self.validateRouteSilently(route) {
                Logger.shared.error("RouteTable: Route validation failed - \(error.localizedDescription)")
                return
            }
            
            self.routes.append(route)
            self.saveRoutes()
            DispatchQueue.main.async {
                self.delegate?.routeTable(self, didUpdateRoutes: self.routes)
            }
        }
    }
    
    /// Add a route with validation, returning the result
    /// - Parameter route: The route to add
    /// - Returns: true if added successfully, false if validation failed
    @discardableResult
    func addRouteWithValidation(_ route: RouteEntry) -> Result<RouteEntry, RouteValidationError> {
        // Validate route before adding
        do {
            _ = try validateRoute(route)
        } catch let error as RouteValidationError {
            Logger.shared.error("RouteTable: Route validation failed - \(error.localizedDescription)")
            return .failure(error)
        } catch {
            return .failure(.unknownGateway(route.gateway))
        }
        
        // Add the route
        queue.async { [weak self] in
            guard let self = self else { return }
            self.routes.append(route)
            self.saveRoutes()
            DispatchQueue.main.async {
                self.delegate?.routeTable(self, didUpdateRoutes: self.routes)
            }
        }
        
        return .success(route)
    }
    
    func removeRoute(at index: Int) {
        queue.async { [weak self] in
            guard let self = self, index < self.routes.count else { return }
            self.routes.remove(at: index)
            self.saveRoutes()
            DispatchQueue.main.async {
                self.delegate?.routeTable(self, didUpdateRoutes: self.routes)
            }
        }
    }
    
    func removeRoute(destination: String, subnetMask: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.routes.removeAll { $0.destination == destination && $0.subnetMask == subnetMask }
            self.saveRoutes()
            DispatchQueue.main.async {
                self.delegate?.routeTable(self, didUpdateRoutes: self.routes)
            }
        }
    }
    
    func updateRoute(at index: Int, with route: RouteEntry) {
        queue.async { [weak self] in
            guard let self = self, index < self.routes.count else { return }
            self.routes[index] = route
            self.saveRoutes()
            DispatchQueue.main.async {
                self.delegate?.routeTable(self, didUpdateRoutes: self.routes)
            }
        }
    }
    
    func enableRoute(at index: Int) {
        guard index < routes.count else { return }
        var route = routes[index]
        route = RouteEntry(destination: route.destination, subnetMask: route.subnetMask, gateway: route.gateway, interface: route.interface, metric: route.metric, isEnabled: true)
        updateRoute(at: index, with: route)
    }
    
    func disableRoute(at index: Int) {
        guard index < routes.count else { return }
        var route = routes[index]
        route = RouteEntry(destination: route.destination, subnetMask: route.subnetMask, gateway: route.gateway, interface: route.interface, metric: route.metric, isEnabled: false)
        updateRoute(at: index, with: route)
    }
    
    func findBestRoute(for destination: String) -> RouteEntry? {
        let sortedRoutes = enabledRoutes.sorted { $0.metric < $1.metric }
        
        for route in sortedRoutes {
            if matchesRoute(destination: destination, route: route) {
                return route
            }
        }
        
        return nil
    }
    
    private func matchesRoute(destination: String, route: RouteEntry) -> Bool {
        guard let destIP = ipToUInt32(destination),
              let routeDest = ipToUInt32(route.destination),
              let mask = ipToUInt32(route.subnetMask) else {
            return false
        }
        
        return (destIP & mask) == (routeDest & mask)
    }
    
    private func ipToUInt32(_ ip: String) -> UInt32? {
        let components = ip.split(separator: ".").compactMap { UInt8($0) }
        guard components.count == 4 else { return nil }
        
        return UInt32(components[0]) << 24 |
               UInt32(components[1]) << 16 |
               UInt32(components[2]) << 8 |
               UInt32(components[3])
    }
    
    private func saveRoutes() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(routes)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Logger.shared.error("RouteTable: Failed to save routes - \(error)")
        }
    }
    
    private func loadRoutes() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            routes = try decoder.decode([RouteEntry].self, from: data)
        } catch {
            Logger.shared.error("RouteTable: Failed to load routes - \(error)")
            routes = []
        }
    }
    
    func clearAllRoutes() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.routes.removeAll()
            self.saveRoutes()
            DispatchQueue.main.async {
                self.delegate?.routeTable(self, didUpdateRoutes: self.routes)
            }
        }
    }
    
    func reloadFromDisk() {
        queue.async { [weak self] in
            self?.loadRoutes()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.delegate?.routeTable(self, didUpdateRoutes: self.routes)
            }
        }
    }
}