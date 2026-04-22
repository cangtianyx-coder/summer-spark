import Foundation

// MARK: - Observer Protocol for Cross-Module Communication

/// Generic observer protocol for publish-subscribe pattern
protocol ObserverProtocol: AnyObject {
    func didReceiveNotification(name: Notification.Name, userInfo: [String: Any]?)
}

/// Subject for managing observers and posting notifications
final class ObserverCenter {
    static let shared = ObserverCenter()

    private var observers: [ObjectIdentifier: WeakObserver] = [:]
    private let queue = DispatchQueue(label: "com.summerspark.observerCenter", attributes: .concurrent)

    private class WeakObserver {
        weak var observer: ObserverProtocol?
        let token: UUID

        init(_ observer: ObserverProtocol) {
            self.observer = observer
            self.token = UUID()
        }
    }

    private init() {}

    func addObserver(_ observer: ObserverProtocol) {
        queue.async(flags: .barrier) {
            let id = ObjectIdentifier(observer)
            self.observers[id] = WeakObserver(observer)
        }
    }

    func removeObserver(_ observer: ObserverProtocol) {
        queue.async(flags: .barrier) {
            let id = ObjectIdentifier(observer)
            self.observers.removeValue(forKey: id)
        }
    }

    func postNotification(name: Notification.Name, userInfo: [String: Any]? = nil) {
        queue.async {
            var expiredKeys: [ObjectIdentifier] = []

            for (id, weakObserver) in self.observers {
                if let observer = weakObserver.observer {
                    DispatchQueue.main.async {
                        observer.didReceiveNotification(name: name, userInfo: userInfo)
                    }
                } else {
                    expiredKeys.append(id)
                }
            }

            if !expiredKeys.isEmpty {
                self.queue.async(flags: .barrier) {
                    for key in expiredKeys {
                        self.observers.removeValue(forKey: key)
                    }
                }
            }
        }
    }

    func cleanup() {
        queue.async(flags: .barrier) {
            self.observers.removeAll()
        }
    }
}

// MARK: - Mode Observer

protocol ModeObserverDelegate: AnyObject {
    func appModeDidChange(from oldMode: AppMode, to newMode: AppMode)
    func connectivityStatusDidChange(to status: ConnectivityStatus)
}

extension ModeObserverDelegate {
    func appModeDidChange(from oldMode: AppMode, to newMode: AppMode) {}
    func connectivityStatusDidChange(to status: ConnectivityStatus) {}
}

// MARK: - Credit Observer

protocol CreditObserverDelegate: AnyObject {
    func creditBalanceDidChange(balance: Double)
    func creditTierDidChange(from oldTier: CreditAccount.CreditTier, to newTier: CreditAccount.CreditTier)
    func creditEventOccurred(event: CreditEvent)
}

extension CreditObserverDelegate {
    func creditBalanceDidChange(balance: Double) {}
    func creditTierDidChange(from oldTier: CreditAccount.CreditTier, to newTier: CreditAccount.CreditTier) {}
    func creditEventOccurred(event: CreditEvent) {}
}

// MARK: - Mesh Observer

protocol MeshObserverDelegate: AnyObject {
    func meshNodeDiscovered(node: MeshNode)
    func meshNodeLost(nodeId: UUID)
    func meshMessageReceived(message: MeshMessage, from node: MeshNode)
    func meshRouteDidUpdate(decision: RoutingDecision)
}

extension MeshObserverDelegate {
    func meshNodeDiscovered(node: MeshNode) {}
    func meshNodeLost(nodeId: UUID) {}
    func meshMessageReceived(message: MeshMessage, from node: MeshNode) {}
    func meshRouteDidUpdate(decision: RoutingDecision) {}
}

// MARK: - Group Observer

protocol GroupObserverDelegate: AnyObject {
    func groupCreated(group: Group)
    func groupUpdated(group: Group)
    func groupDeleted(groupId: String)
    func groupMemberAdded(groupId: String, member: GroupMember)
    func groupMemberRemoved(groupId: String, memberUid: String)
    func groupMemberRoleChanged(groupId: String, memberUid: String, newRole: GroupMember.GroupRole)
}

extension GroupObserverDelegate {
    func groupCreated(group: Group) {}
    func groupUpdated(group: Group) {}
    func groupDeleted(groupId: String) {}
    func groupMemberAdded(groupId: String, member: GroupMember) {}
    func groupMemberRemoved(groupId: String, memberUid: String) {}
    func groupMemberRoleChanged(groupId: String, memberUid: String, newRole: GroupMember.GroupRole) {}
}

// MARK: - Identity Observer

protocol IdentityObserverDelegate: AnyObject {
    func identityDidChange(uid: String?)
    func usernameDidChange(username: String?)
    func publicKeyDidRotate()
}

extension IdentityObserverDelegate {
    func identityDidChange(uid: String?) {}
    func usernameDidChange(username: String?) {}
    func publicKeyDidRotate() {}
}

// MARK: - Voice Observer

protocol VoiceObserverDelegate: AnyObject {
    func voiceSessionDidStart()
    func voiceSessionDidEnd()
    func voiceAudioLevelDidChange(level: Float)
    func voicePushToTalkStateChanged(isPressed: Bool)
}

extension VoiceObserverDelegate {
    func voiceSessionDidStart() {}
    func voiceSessionDidEnd() {}
    func voiceAudioLevelDidChange(level: Float) {}
    func voicePushToTalkStateChanged(isPressed: Bool) {}
}

// MARK: - Location Observer

protocol LocationObserverDelegate: AnyObject {
    func locationDidUpdate(location: LocationData)
    func locationAuthorizationDidChange(status: CLAuthorizationStatus)
    func locationErrorOccurred(error: Error)
}

extension LocationObserverDelegate {
    func locationDidUpdate(location: LocationData) {}
    func locationAuthorizationDidChange(status: CLAuthorizationStatus) {}
    func locationErrorOccurred(error: Error) {}
}

// MARK: - Sync Observer

protocol SyncObserverDelegate: AnyObject {
    func syncStateDidChange(state: SyncState)
    func syncDidComplete()
    func syncDidFail(error: Error)
}

extension SyncObserverDelegate {
    func syncStateDidChange(state: SyncState) {}
    func syncDidComplete() {}
    func syncDidFail(error: Error) {}
}

// MARK: - Storage Observer

protocol StorageObserverDelegate: AnyObject {
    func storageDidBecomeFull()
    func storageDidRecoverSpace(bytes: Int64)
}

extension StorageObserverDelegate {
    func storageDidBecomeFull() {}
    func storageDidRecoverSpace(bytes: Int64) {}
}

// MARK: - Network Observer

protocol NetworkObserverDelegate: AnyObject {
    func networkStatusDidChange(isOnline: Bool)
    func networkLatencyDidChange(latency: TimeInterval)
    func networkErrorOccurred(error: Error)
}

extension NetworkObserverDelegate {
    func networkStatusDidChange(isOnline: Bool) {}
    func networkLatencyDidChange(latency: TimeInterval) {}
    func networkErrorOccurred(error: Error) {}
}

// MARK: - ObserverRegistry

/// Central registry for all observers with typed delegates
final class ObserverRegistry {
    static let shared = ObserverRegistry()

    private var modeObservers: [ObjectIdentifier: WeakRef] = [:]
    private var creditObservers: [ObjectIdentifier: WeakRef] = [:]
    private var meshObservers: [ObjectIdentifier: WeakRef] = [:]
    private var groupObservers: [ObjectIdentifier: WeakRef] = [:]
    private var identityObservers: [ObjectIdentifier: WeakRef] = [:]
    private var voiceObservers: [ObjectIdentifier: WeakRef] = [:]
    private var locationObservers: [ObjectIdentifier: WeakRef] = [:]
    private var syncObservers: [ObjectIdentifier: WeakRef] = [:]

    private let queue = DispatchQueue(label: "com.summerspark.observerRegistry")

    private class WeakRef {
        weak var value: AnyObject?
        init(_ value: AnyObject) {
            self.value = value
        }
    }

    private init() {}

    // MARK: - Mode Observers

    func addModeObserver(_ observer: ModeObserverDelegate) {
        queue.async {
            let id = ObjectIdentifier(observer as AnyObject)
            self.modeObservers[id] = WeakRef(observer as AnyObject)
        }
    }

    func removeModeObserver(_ observer: ModeObserverDelegate) {
        queue.async {
            let id = ObjectIdentifier(observer as AnyObject)
            self.modeObservers.removeValue(forKey: id)
        }
    }

    func notifyModeObservers(oldMode: AppMode, newMode: AppMode) {
        queue.async {
            let observers = self.modeObservers.values.compactMap { $0.value as? ModeObserverDelegate }
            DispatchQueue.main.async {
                observers.forEach { $0.appModeDidChange(from: oldMode, to: newMode) }
            }
        }
    }

    // MARK: - Credit Observers

    func addCreditObserver(_ observer: CreditObserverDelegate) {
        queue.async {
            let id = ObjectIdentifier(observer as AnyObject)
            self.creditObservers[id] = WeakRef(observer as AnyObject)
        }
    }

    func removeCreditObserver(_ observer: CreditObserverDelegate) {
        queue.async {
            let id = ObjectIdentifier(observer as AnyObject)
            self.creditObservers.removeValue(forKey: id)
        }
    }

    func notifyCreditObservers(balance: Double) {
        queue.async {
            let observers = self.creditObservers.values.compactMap { $0.value as? CreditObserverDelegate }
            DispatchQueue.main.async {
                observers.forEach { $0.creditBalanceDidChange(balance: balance) }
            }
        }
    }

    func notifyCreditTierObservers(oldTier: CreditAccount.CreditTier, newTier: CreditAccount.CreditTier) {
        queue.async {
            let observers = self.creditObservers.values.compactMap { $0.value as? CreditObserverDelegate }
            DispatchQueue.main.async {
                observers.forEach { $0.creditTierDidChange(from: oldTier, to: newTier) }
            }
        }
    }

    // MARK: - Mesh Observers

    func addMeshObserver(_ observer: MeshObserverDelegate) {
        queue.async {
            let id = ObjectIdentifier(observer as AnyObject)
            self.meshObservers[id] = WeakRef(observer as AnyObject)
        }
    }

    func removeMeshObserver(_ observer: MeshObserverDelegate) {
        queue.async {
            let id = ObjectIdentifier(observer as AnyObject)
            self.meshObservers.removeValue(forKey: id)
        }
    }

    func notifyMeshNodeDiscovered(node: MeshNode) {
        queue.async {
            let observers = self.meshObservers.values.compactMap { $0.value as? MeshObserverDelegate }
            DispatchQueue.main.async {
                observers.forEach { $0.meshNodeDiscovered(node: node) }
            }
        }
    }

    func notifyMeshNodeLost(nodeId: UUID) {
        queue.async {
            let observers = self.meshObservers.values.compactMap { $0.value as? MeshObserverDelegate }
            DispatchQueue.main.async {
                observers.forEach { $0.meshNodeLost(nodeId: nodeId) }
            }
        }
    }

    // MARK: - Group Observers

    func addGroupObserver(_ observer: GroupObserverDelegate) {
        queue.async {
            let id = ObjectIdentifier(observer as AnyObject)
            self.groupObservers[id] = WeakRef(observer as AnyObject)
        }
    }

    func removeGroupObserver(_ observer: GroupObserverDelegate) {
        queue.async {
            let id = ObjectIdentifier(observer as AnyObject)
            self.groupObservers.removeValue(forKey: id)
        }
    }

    func notifyGroupCreated(group: Group) {
        queue.async {
            let observers = self.groupObservers.values.compactMap { $0.value as? GroupObserverDelegate }
            DispatchQueue.main.async {
                observers.forEach { $0.groupCreated(group: group) }
            }
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        queue.async {
            self.modeObservers.removeAll()
            self.creditObservers.removeAll()
            self.meshObservers.removeAll()
            self.groupObservers.removeAll()
            self.identityObservers.removeAll()
            self.voiceObservers.removeAll()
            self.locationObservers.removeAll()
            self.syncObservers.removeAll()
        }
    }
}

// MARK: - CLAuthorizationStatus Import

import CoreLocation