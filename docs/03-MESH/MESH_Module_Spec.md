# MESH_Module_Spec — Mesh Network Module Specification

## 1. Module Overview

**Module Name:** Mesh  
**Type:** Network Infrastructure Module  
**Purpose:** Enable peer-to-peer communication via Bluetooth/WiFi P2P, support multi-hop relay and node discovery  
**Dependencies:** Identity (UID), Crypto (E2E encryption), Storage (routing table cache)  
**Depended By:** Voice, Map, Points

### 1.1 Core Responsibilities

- Discover neighboring nodes via Bluetooth LE and WiFi Direct
- Maintain routing table for multi-hop communication
- Relay data packets across mesh network
- Monitor node connectivity and link quality
- Handle network topology changes

---

## 2. Functionality Specification

### 2.1 Bluetooth Service

- **Protocol:** Bluetooth LE (4.0+)
- **Role:** Peripheral + Central (dual mode)
- **Discovery:** Background scanning every 5 seconds
- **Advertised Data:** UID + capability flags + signal strength
- **Connection Timeout:** 10 seconds
- **MTU:** 512 bytes (iOS limit)

### 2.2 WiFi P2P Service

- **Protocol:** WiFi Direct (Apple's MultipeerConnectivity)
- **Role:** Inviter + Invitee
- **Discovery:** On-demand, battery-conscious
- **Data Channel:** Reliable, ordered delivery
- **Fallback:** When Bluetooth unavailable

### 2.3 Node Discovery

| Method | Interval | Data Exchanged |
|--------|----------|----------------|
| Bluetooth LE Scan | 5s | UID, capability, RSSI |
| WiFi P2P Browse | 10s | UID, service type |
| Mesh Broadcast | 30s | Topology diff |

### 2.4 Routing Table

- **Algorithm:** Modified DSDV (Destination-Sequence Distance Vector)
- **Max Hops:** 8
- **Sequence Numbers:** Prevent routing loops
- **Stale Entry Timeout:** 120 seconds
- **Storage:** SQLite `routing_table` table

### 2.5 Relay Service

- **Protocol:** Custom binary protocol
- **Packet Format:** `[version:1][ttl:1][srcUID:16][dstUID:16][seq:4][payload:N]`
- **TTL:** Decrement per hop, drop at 0
- **Acknowledgment:** Optional, via return path

---

## 3. Interface Specification

### 3.1 Core API

```swift
// Start Bluetooth scanning for nearby nodes
func startBluetoothScan() -> [DiscoveredNode]

// Start WiFi P2P discovery
func startWiFiP2P() -> [DiscoveredNode]

// Build route to destination UID
func buildRoute(from: UID, to: UID) -> Route?

// Relay data through mesh
func relay(data: Data, via: Route) -> Bool

// Register node discovery callback
func onNodeDiscovered(handler: (DiscoveredNode) -> Void)

// Send data directly to peer
func send(data: Data, to: UID) -> Bool

// Receive data callback
func onDataReceived(handler: (Data, UID) -> Void)

// Get current mesh topology
func getTopology() -> MeshTopology

// Stop all services
func stop()
```

### 3.2 Data Structures

```swift
struct DiscoveredNode {
    let uid: String
    let publicKey: Data
    let rssi: Int              // Signal strength
    let capability: UInt8      // 0x01=Bluetooth, 0x02=WiFi, 0x04=Relay
    let lastSeen: Date
}

struct Route {
    let destination: UID
    let nextHop: UID
    let hopCount: Int
    let sequenceNumber: UInt32
    let metric: Float          // Link quality 0-1
    let expiresAt: Date
}

struct MeshTopology {
    let nodes: [MeshNode]
    let edges: [(UID, UID, Float)]  // Source, Dest, Quality
}

struct MeshNode {
    let uid: String
    let isOnline: Bool
    let capabilities: UInt8
    let lastSeen: Date
}
```

### 3.3 Routing Table Schema

| Field | Type | Description |
|-------|------|-------------|
| destination | TEXT PRIMARY KEY | Target UID |
| next_hop | TEXT | Next hop UID |
| hop_count | INTEGER | Number of hops |
| sequence_num | INTEGER | DSDV sequence number |
| metric | REAL | Link quality (0-1) |
| last_updated | INTEGER | Unix timestamp |
| expires_at | INTEGER | Expiration timestamp |

---

## 4. User Interactions and Flows

### 4.1 Node Discovery Flow

```
User enables Mesh
    ↓
Start Bluetooth LE scanning
    ↓
Receive advertising packets
    ↓
Parse UID + capability + RSSI
    ↓
Update neighbor table
    ↓
Invoke onNodeDiscovered callback
    ↓
Attempt connection if relay capable
```

### 4.2 Multi-hop Relay Flow

```
App wants to send data to remote UID
    ↓
Check routing table for route
    ↓（route exists）
Increment TTL, prepend route header
    ↓
Send to next_hop via Bluetooth/WiFi
    ↓
Next hop receives, checks TTL>0
    ↓
Decrement TTL, forward to its next_hop
    ↓
... repeat until TTL=0 or destination reached
```

### 4.3 Route Discovery Flow

```
Route to destination not in table
    ↓
Initiate route discovery (RREQ broadcast)
    ↓
Wait for RREP (route reply)
    ↓
Update routing table with new route
    ↓
Cache route with expiration timer
```

---

## 5. Edge Cases and Error Handling

| Scenario | Handling |
|----------|----------|
| Bluetooth unavailable | Fall back to WiFi P2P only |
| WiFi P2P fails | Return error, notify app layer |
| No route to destination | Return nil, trigger RREQ |
| Node goes offline | Mark route as stale, remove after timeout |
| TTL exceeds max (8) | Drop packet, send ICMP-like error |
| Duplicate RREP received | Ignore (sequence number check) |
| Secure Enclave unavailable for pairing | Use fallback symmetric key exchange |

---

## 6. Security Considerations

- All relay data is E2E encrypted via Crypto module
- Node authentication via signature verification
- Anti-replay protection via sequence numbers
- Mesh broadcast uses incremental sequence to prevent injection
- No plaintext UID broadcast in public advertising (use hash)

---

## 7. File Structure

```
src/
├── Mesh/
│   ├── MeshService.swift            # Main entry point
│   ├── BluetoothService.swift       # BLE scanning & connection
│   ├── WiFiP2PService.swift        # MultipeerConnectivity wrapper
│   ├── RoutingTable.swift           # DSDV routing implementation
│   ├── RelayEngine.swift            # Packet forwarding logic
│   ├── NodeDiscovery.swift          # Discovery protocols
│   └── Models/
│       ├── DiscoveredNode.swift
│       ├── Route.swift
│       └── MeshTopology.swift
```

---

## 8. Dependencies

| Module | Purpose |
|--------|---------|
| Identity | UID generation, peer identification |
| Crypto | E2E encryption for relayed data |
| Storage | Routing table persistence |

---

## 9. State Machine

```
[Idle] --start--> [Scanning]
[Scanning] --node found--> [Connecting]
[Connecting] --connected--> [Connected]
[Connected] --data rx/tx--> [Connected]
[Connected] --node lost--> [Scanning]
[Any] --stop--> [Idle]
```

---

*本文档为《夏日萤火》Mesh 模块规格说明 · V1.0*
*更新日期：2026-04-22*