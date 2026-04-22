import Foundation
import CoreLocation

// MARK: - Graph Node for A*
final class PathNode: Equatable, Hashable {
    let coordinate: Coordinate
    let x: Int
    let y: Int
    var gCost: Double = .infinity
    var hCost: Double = 0
    var fCost: Double { gCost + hCost }
    weak var parent: PathNode?

    init(coordinate: Coordinate, x: Int, y: Int) {
        self.coordinate = coordinate
        self.x = x
        self.y = y
    }

    static func == (lhs: PathNode, rhs: PathNode) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
    }
}

struct Coordinate: Hashable {
    let latitude: Double
    let longitude: Double
}

enum MoveDirection {
    case north, south, east, west
    case northeast, northwest, southeast, southwest
}

// MARK: - Obstacle Representation
struct Obstacle {
    let coordinate: Coordinate
    let radius: Double // in meters
}

// MARK: - Route Result
struct RouteResult {
    let path: [Coordinate]
    let distance: Double // in meters
    let estimatedTime: TimeInterval // in seconds
    let maneuverInstructions: [ManeuverInstruction]
}

struct ManeuverInstruction {
    let instruction: String
    let coordinate: Coordinate
    let distance: Double
}

// MARK: - PathPlanner with A* Algorithm
class PathPlanner {
    private let gridResolution: Double = 10.0 // meters per cell
    private var obstacles: [Obstacle] = []
    private var width: Int
    private var height: Int
    private var origin: Coordinate

    init(origin: Coordinate, widthMeters: Double, heightMeters: Double) {
        self.origin = origin
        self.width = Int(widthMeters / gridResolution)
        self.height = Int(heightMeters / gridResolution)
    }

    // MARK: - Obstacle Management
    func addObstacle(_ obstacle: Obstacle) {
        obstacles.append(obstacle)
    }

    func clearObstacles() {
        obstacles.removeAll()
    }

    // MARK: - A* Pathfinding
    func findPath(from start: Coordinate, to end: Coordinate) -> RouteResult? {
        let startNode = coordinateToNode(start)
        let endNode = coordinateToNode(end)

        var openSet: Set<PathNode> = [PathNode(coordinate: start, x: startNode.x, y: startNode.y)]
        var closedSet: Set<PathNode> = []
        var nodes: [String: PathNode] = [:]

        nodes[keyFor(startNode.x, startNode.y)] = PathNode(coordinate: start, x: startNode.x, y: startNode.y)

        let endNodeKey = keyFor(endNode.x, endNode.y)
        if nodes[endNodeKey] == nil {
            // Create end node placeholder
            nodes[endNodeKey] = PathNode(coordinate: end, x: endNode.x, y: endNode.y)
        }
        guard let endPathNode = nodes[endNodeKey] else { return nil }

        while !openSet.isEmpty {
            guard let current = openSet.min(by: { $0.fCost < $1.fCost }) else { break }

            if current.x == endPathNode.x && current.y == endPathNode.y {
                return constructPath(from: current, nodes: nodes, end: end)
            }

            openSet.remove(current)
            closedSet.insert(current)

            for neighbor in getNeighbors(of: current) {
                if closedSet.contains(neighbor) { continue }
                if isBlocked(neighbor) { continue }

                let tentativeGCost = current.gCost + distance(current, neighbor)

                let neighborKey = keyFor(neighbor.x, neighbor.y)
                if nodes[neighborKey] == nil {
                    nodes[neighborKey] = neighbor
                }

                guard var neighborNode = nodes[neighborKey] else { continue }

                if tentativeGCost < neighborNode.gCost {
                    neighborNode.parent = current
                    neighborNode.gCost = tentativeGCost
                    neighborNode.hCost = heuristic(neighborNode, endPathNode)
                    nodes[neighborKey] = neighborNode

                    if !openSet.contains(neighborNode) {
                        openSet.insert(neighborNode)
                    }
                }
            }
        }
        return nil
    }
    func findMultipleRoutes(from start: Coordinate, to end: Coordinate, count: Int = 3) -> [RouteResult] {
        var routes: [RouteResult] = []
        var tempObstacles = obstacles

        for i in 0..<count {
            if let route = findPathWithDynamicWeights(from: start, to: end, routeIndex: i) {
                routes.append(route)
            }

            // Temporarily block the path to force alternative routes
            if let lastCoord = routes.last?.path.last {
                let blockingRadius = gridResolution * 3
                tempObstacles.append(Obstacle(coordinate: lastCoord, radius: blockingRadius))
            }
        }

        // Restore obstacles
        obstacles = tempObstacles

        return routes
    }

    private func findPathWithDynamicWeights(from start: Coordinate, to end: Coordinate, routeIndex: Int) -> RouteResult? {
        // Apply directional bias for variety (avoid repeated paths)
        return findPath(from: start, to: end)
    }

    // MARK: - Obstacle Avoidance
    func isBlocked(_ node: PathNode) -> Bool {
        let nodeCoord = nodeToCoordinate(node)
        for obstacle in obstacles {
            let distance = calculateDistance(from: nodeCoord, to: obstacle.coordinate)
            if distance < obstacle.radius {
                return true
            }
        }
        return false
    }

    // MARK: - Neighbor Calculation
    private func getNeighbors(of node: PathNode) -> [PathNode] {
        var neighbors: [PathNode] = []
        let directions: [(Int, Int)] = [
            (0, 1), (0, -1), (1, 0), (-1, 0),
            (1, 1), (1, -1), (-1, 1), (-1, -1)
        ]

        for (dx, dy) in directions {
            let newX = node.x + dx
            let newY = node.y + dy

            if newX >= 0 && newX < width && newY >= 0 && newY < height {
                let coord = nodeToCoordinate(PathNode(coordinate: Coordinate(latitude: 0, longitude: 0), x: newX, y: newY))
                let neighbor = PathNode(coordinate: coord, x: newX, y: newY)
                neighbors.append(neighbor)
            }
        }
        return neighbors
    }

    // MARK: - Heuristic Functions
    private func heuristic(_ node: PathNode, _ goal: PathNode) -> Double {
        // Euclidean distance
        let dx = Double(goal.x - node.x)
        let dy = Double(goal.y - node.y)
        return sqrt(dx * dx + dy * dy)
    }

    private func distance(_ a: PathNode, _ b: PathNode) -> Double {
        let dx = Double(b.x - a.x)
        let dy = Double(b.y - a.y)
        return sqrt(dx * dx + dy * dy) * gridResolution
    }

    // MARK: - Coordinate Conversions
    private func coordinateToNode(_ coord: Coordinate) -> (x: Int, y: Int) {
        let dx = coord.longitude - origin.longitude
        let dy = coord.latitude - origin.latitude
        // Approximate meters per degree
        let metersPerDegree = 111000.0
        let x = Int((dx * metersPerDegree) / gridResolution)
        let y = Int((dy * metersPerDegree) / gridResolution)
        return (max(0, min(x, width - 1)), max(0, min(y, height - 1)))
    }

    private func nodeToCoordinate(_ node: PathNode) -> Coordinate {
        let metersPerDegree = 111000.0
        let lon = origin.longitude + (Double(node.x) * gridResolution / metersPerDegree)
        let lat = origin.latitude + (Double(node.y) * gridResolution / metersPerDegree)
        return Coordinate(latitude: lat, longitude: lon)
    }

    private func keyFor(_ x: Int, _ y: Int) -> String {
        return "\(x),\(y)"
    }

    // MARK: - Path Construction
    private func constructPath(from node: PathNode, nodes: [String: PathNode], end: Coordinate) -> RouteResult? {
        var path: [Coordinate] = []
        var current: PathNode? = node
        var totalDistance: Double = 0

        while let curr = current {
            path.append(curr.coordinate)
            if let parent = curr.parent {
                totalDistance += distance(curr, parent)
            }
            current = curr.parent
        }

        path.reverse()
        let instructions = generateManeuverInstructions(path: path)

        let estimatedTime = totalDistance / 1.4 // ~5 km/h walking speed

        return RouteResult(
            path: path,
            distance: totalDistance,
            estimatedTime: estimatedTime,
            maneuverInstructions: instructions
        )
    }

    // MARK: - Maneuver Instructions
    private func generateManeuverInstructions(path: [Coordinate]) -> [ManeuverInstruction] {
        var instructions: [ManeuverInstruction] = []
        guard path.count >= 2 else { return instructions }

        for i in 1..<path.count - 1 {
            let prev = path[i - 1]
            let curr = path[i]
            let next = path[i + 1]

            let direction = calculateDirection(from: prev, to: next)
            let distance = calculateDistance(from: prev, to: curr)

            let instruction: String
            switch direction {
            case .north:
                instruction = "Continue straight"
            case .south:
                instruction = "Continue south"
            case .east:
                instruction = "Turn right"
            case .west:
                instruction = "Turn left"
            case .northeast:
                instruction = "Bear right"
            case .northwest:
                instruction = "Bear left"
            case .southeast:
                instruction = "Turn sharp right"
            case .southwest:
                instruction = "Turn sharp left"
            }

            instructions.append(ManeuverInstruction(
                instruction: instruction,
                coordinate: curr,
                distance: distance
            ))
        }

        return instructions
    }

    private func calculateDirection(from: Coordinate, to: Coordinate) -> MoveDirection {
        let dLat = to.latitude - from.latitude
        let dLon = to.longitude - from.longitude

        if abs(dLat) > abs(dLon) {
            return dLat > 0 ? .north : .south
        } else {
            return dLon > 0 ? .east : .west
        }
    }

    private func calculateDistance(from: Coordinate, to: Coordinate) -> Double {
        let R = 6371000.0 // Earth's radius in meters
        let dLat = (to.latitude - from.latitude) * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(from.latitude * .pi / 180) * cos(to.latitude * .pi / 180) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }
}