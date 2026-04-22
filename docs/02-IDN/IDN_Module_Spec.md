# IDN_Module_Spec — Identity Module Specification

## 1. Module Overview

**Module Name:** Identity  
**Type:** Core Infrastructure Module  
**Purpose:** Manage user identity, device authentication, and cryptographic key lifecycle  
**Dependencies:** Storage (Keychain/SQLite), Crypto  
**Depended By:** Mesh, Voice, Map, Points

### 1.1 Core Responsibilities

- Generate and manage globally unique identifiers (UIDs)
- Generate and store ECDH P-256 elliptic curve key pairs
- Provide secure key storage using iOS Keychain / Secure Enclave
- Handle identity凭证 (credentials) management
- Export public keys for peer-to-peer communication

---

## 2. Functionality Specification

### 2.1 UID Generation

- **Algorithm:** UUID v4 + device hardware identifier hash
- **Format:** 36-character string (8-4-4-4-12, e.g., `A1B2C3D4-E5F6-7890-ABCD-EF1234567890`)
- **Uniqueness:** Collision-resistant across mesh network
- **Stability:** UID remains constant for device lifetime (stored in Keychain)

### 2.2 Key Pair Generation

- **Algorithm:** ECDH P-256 (secp256r1)
- **Library:** Apple CryptoKit
- **Private Key Storage:** Secure Enclave when available, Keychain fallback
- **Public Key Export:** X9.63 uncompressed point format (65 bytes)

### 2.3 Keychain Operations

- **Service Identifier:** `com.summerspark.identity`
- **Access Control:** `.whenUnlockedThisDeviceOnly`
- **Key Format:** kSecAttrKeyTypeECSECPrimeRandom
- **Key Size:** 256-bit

### 2.4 Identity Storage Schema

| Field | Type | Description |
|-------|------|-------------|
| uid | TEXT PRIMARY KEY | Global unique identifier |
| public_key | BLOB | X9.63 formatted EC public key |
| created_at | INTEGER | Unix timestamp |
| device_name | TEXT | User-assigned device name |
| last_seen | INTEGER | Last activity timestamp |

---

## 3. Interface Specification

### 3.1 Core API

```swift
// Generate or retrieve UID
func getOrCreateUID() -> String

// Generate new key pair (overwrites existing)
func generateKeyPair() -> (publicKey: Data, privateKey: Data)

// Store data in Keychain
func storeInKeychain(key: String, value: Data) -> Bool

// Retrieve data from Keychain
func retrieveFromKeychain(key: String) -> Data?

// Get public key for peer
func getPublicKey(uid: String) -> Data?

// Verify identity signature
func verifySignature(data: Data, signature: Data, publicKey: Data) -> Bool
```

### 3.2 Data Structures

```swift
struct IdentityCredential {
    let uid: String
    let publicKey: Data
    let privateKeyRef: SecKey
    let createdAt: Date
    let deviceName: String?
}

struct PeerIdentity {
    let uid: String
    let publicKey: Data
    let lastSeen: Date
}
```

---

## 4. User Interactions and Flows

### 4.1 First Launch Flow

```
App Launch
    ↓
Check Keychain for existing UID
    ↓（not found）
Generate UID using UUID v4 + device hash
    ↓
Generate ECDH P-256 key pair
    ↓
Store private key in Secure Enclave / Keychain
    ↓
Export public key (for mesh distribution)
    ↓
Store peer-facing identity in SQLite
```

### 4.2 Peer Identity Resolution

```
Request peer public key
    ↓
Check local SQLite cache
    ↓（cache miss）
Query mesh network for peer public key
    ↓
Cache result in SQLite
    ↓
Return public key for Crypto operations
```

---

## 5. Edge Cases and Error Handling

| Scenario | Handling |
|----------|----------|
| Keychain unavailable | Return error, prompt user to restart app |
| Secure Enclave not available | Fall back to software keychain |
| Duplicate UID detected | Regenerate new UID |
| Corrupted key data | Re-generate key pair, notify user |
| Public key not found | Return nil, trigger mesh discovery |

---

## 6. Security Considerations

- Private keys never leave Secure Enclave
- Keychain items use `.whenUnlockedThisDeviceOnly` access control
- UID generation uses cryptographically secure random source
- Public key distribution via mesh is integrity-checked via signatures
- No sensitive data in UserDefaults (only preferences)

---

## 7. File Structure

```
src/
├── Identity/
│   ├── IdentityManager.swift       # Main entry point
│   ├── UIDGenerator.swift          # UID generation logic
│   ├── KeychainManager.swift       # Keychain CRUD operations
│   ├── IdentityStorage.swift       # SQLite identity storage
│   └── Models/
│       ├── IdentityCredential.swift
│       └── PeerIdentity.swift
```

---

## 8. Dependencies

| Module | Purpose |
|--------|---------|
| Storage | SQLite for identity cache, Keychain for secrets |
| Crypto | Key pair usage in E2E encryption |

---

*本文档为《夏日萤火》Identity 模块规格说明 · V1.0*
*更新日期：2026-04-22*