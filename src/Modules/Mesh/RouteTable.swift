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
    
    var allRoutes: [RouteEntry] {
        return routes
    }
    
    var enabledRoutes: [RouteEntry] {
        return routes.filter { $0.isEnabled }
    }
    
    private init() {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documentsPath.appendingPathComponent("route_table.json")
        loadRoutes()
    }
    
    func addRoute(_ route: RouteEntry) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.routes.append(route)
            self.saveRoutes()
            DispatchQueue.main.async {
                self.delegate?.routeTable(self, didUpdateRoutes: self.routes)
            }
        }
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
            print("RouteTable: Failed to save routes - \(error)")
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
            print("RouteTable: Failed to load routes - \(error)")
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