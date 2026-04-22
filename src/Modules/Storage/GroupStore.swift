import Foundation
import CryptoKit
final class GroupStore {
    static let shared = GroupStore()



    // MARK: - Private Constants

    private let groupsKey = "groups.store"
    private let userGroupsKey = "groups.userGroups" // Maps uid -> [groupId]

    // MARK: - Private Properties

    private var groups: [String: Group] = [:]
    private var userGroupsMap: [String: Set<String>] = [:] // uid -> Set<groupId>

    // MARK: - Initialization

    private init() {
        loadGroups()
    }

    // MARK: - Setup

    func load() {
        loadGroups()
    }

    // MARK: - Persistence

    private func loadGroups() {
        // Load groups dictionary
        if let data = UserDefaults.standard.data(forKey: groupsKey),
           let decoded = try? JSONDecoder().decode([String: Group].self, from: data) {
            groups = decoded
        }

        // Load user-groups mapping
        if let data = UserDefaults.standard.data(forKey: userGroupsKey),
           let decoded = try? JSONDecoder().decode([String: Set<String>].self, from: data) {
            userGroupsMap = decoded
        }
    }

    private func saveGroups() {
        if let data = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(data, forKey: groupsKey)
        }

        if let data = try? JSONEncoder().encode(userGroupsMap) {
            UserDefaults.standard.set(data, forKey: userGroupsKey)
        }
    }

    // MARK: - Group CRUD

    /// Create a new group with the current user as owner
    func createGroup(name: String) -> Group? {
        guard let currentUid = IdentityManager.shared.uid else { return nil }

        var group = Group(name: name, ownerUid: currentUid)

        // Generate group symmetric key for message encryption
        let symmetricKey = SymmetricKey(size: .bits256)
        group.groupKey = symmetricKey.withUnsafeBytes { Data($0) }

        groups[group.id] = group
        addUserToGroupMapping(uid: currentUid, groupId: group.id)
        saveGroups()

        return group
    }

    /// Get a group by its ID
    func getGroup(id: String) -> Group? {
        return groups[id]
    }

    /// Update group name
    func updateGroupName(groupId: String, newName: String) -> Bool {
        guard var group = groups[groupId] else { return false }

        group.name = newName
        group.updatedAt = Date()
        groups[groupId] = group
        saveGroups()

        return true
    }

    /// Delete a group (only owner can delete)
    func deleteGroup(groupId: String) -> Bool {
        guard let group = groups[groupId] else { return false }
        guard let currentUid = IdentityManager.shared.uid else { return false }

        // Only owner can delete
        guard group.ownerUid == currentUid else { return false }

        // Remove all user mappings
        for member in group.members {
            userGroupsMap[member.uid]?.remove(groupId)
        }

        groups.removeValue(forKey: groupId)
        saveGroups()

        return true
    }

    /// List all groups the current user is a member of
    func getMyGroups() -> [Group] {
        guard let currentUid = IdentityManager.shared.uid else { return [] }

        let groupIds = userGroupsMap[currentUid] ?? []
        return groupIds.compactMap { groups[$0] }
    }

    /// List all groups (admin function)
    func getAllGroups() -> [Group] {
        return Array(groups.values)
    }

    // MARK: - Member Management

    /// Add a member to a group (owner or admin only)
    func addMember(groupId: String, uid: String, role: GroupMember.GroupRole = .member) -> Bool {
        guard var group = groups[groupId] else { return false }
        guard let currentUid = IdentityManager.shared.uid else { return false }

        // Check permission: only owner or admin can add members
        guard let currentMember = group.members.first(where: { $0.uid == currentUid }),
              currentMember.role == .owner || currentMember.role == .admin else {
            return false
        }

        // Check if member already exists
        if group.members.contains(where: { $0.uid == uid }) {
            return false
        }

        let newMember = GroupMember(uid: uid, role: role, joinedAt: Date())
        group.members.append(newMember)
        group.updatedAt = Date()

        groups[groupId] = group
        addUserToGroupMapping(uid: uid, groupId: groupId)
        saveGroups()

        return true
    }

    /// Remove a member from a group
    func removeMember(groupId: String, targetUid: String) -> Bool {
        guard var group = groups[groupId] else { return false }
        guard let currentUid = IdentityManager.shared.uid else { return false }

        // Cannot remove owner
        if targetUid == group.ownerUid {
            return false
        }

        // Check permission
        guard let currentMember = group.members.first(where: { $0.uid == currentUid }),
              currentMember.role == .owner || currentMember.role == .admin else {
            return false
        }

        // Remove member
        group.members.removeAll { $0.uid == targetUid }
        group.updatedAt = Date()

        groups[groupId] = group
        userGroupsMap[targetUid]?.remove(groupId)
        saveGroups()

        return true
    }

    /// Update member role (owner or admin only)
    func updateMemberRole(groupId: String, targetUid: String, newRole: GroupMember.GroupRole) -> Bool {
        guard var group = groups[groupId] else { return false }
        guard let currentUid = IdentityManager.shared.uid else { return false }

        // Cannot change owner role
        if targetUid == group.ownerUid && newRole != .owner {
            return false
        }

        // Check permission
        guard let currentMember = group.members.first(where: { $0.uid == currentUid }),
              currentMember.role == .owner else {
            return false
        }

        guard let index = group.members.firstIndex(where: { $0.uid == targetUid }) else {
            return false
        }

        group.members[index].role = newRole
        group.updatedAt = Date()

        groups[groupId] = group
        saveGroups()

        return true
    }

    /// Leave a group (member or admin leaving themselves)
    func leaveGroup(groupId: String) -> Bool {
        guard let currentUid = IdentityManager.shared.uid else { return false }
        guard var group = groups[groupId] else { return false }

        // Owner cannot leave, must delete or transfer ownership
        if group.ownerUid == currentUid {
            return false
        }

        guard let memberIndex = group.members.firstIndex(where: { $0.uid == currentUid }) else {
            return false
        }

        group.members.remove(at: memberIndex)
        group.updatedAt = Date()

        groups[groupId] = group
        userGroupsMap[currentUid]?.remove(groupId)
        saveGroups()

        return true
    }

    /// Get all members of a group
    func getGroupMembers(groupId: String) -> [GroupMember] {
        return groups[groupId]?.members ?? []
    }

    /// Check if a user is a member of a group
    func isMember(groupId: String, uid: String) -> Bool {
        return groups[groupId]?.members.contains { $0.uid == uid } ?? false
    }

    /// Get user's role in a group
    func getMemberRole(groupId: String, uid: String) -> GroupMember.GroupRole? {
        return groups[groupId]?.members.first { $0.uid == uid }?.role
    }

    // MARK: - Group Keys

    /// Get the group symmetric key (only owner or admin)
    func getGroupKey(groupId: String) -> Data? {
        guard let group = groups[groupId] else { return nil }
        guard let currentUid = IdentityManager.shared.uid else { return nil }

        // Check permission
        guard let currentMember = group.members.first(where: { $0.uid == currentUid }),
              currentMember.role == .owner || currentMember.role == .admin else {
            return nil
        }

        return group.groupKey
    }

    /// Re-generate group key and get it encrypted for a specific member
    func regenerateGroupKey(groupId: String) -> Data? {
        guard var group = groups[groupId] else { return nil }
        guard let currentUid = IdentityManager.shared.uid else { return nil }

        // Only owner can regenerate key
        guard group.ownerUid == currentUid else { return nil }

        let newKey = SymmetricKey(size: .bits256)
        group.groupKey = newKey.withUnsafeBytes { Data($0) }
        group.updatedAt = Date()

        groups[groupId] = group
        saveGroups()

        return group.groupKey
    }

    /// Encrypt group key for a specific member (using their public key)
    func encryptGroupKeyForMember(groupId: String, targetUid: String) -> Data? {
        guard let group = groups[groupId],
              let groupKey = group.groupKey else { return nil }

        // Find member's public key from IdentityManager
        // This would typically involve looking up the member's public key
        // For now, return the raw group key (in real app, encrypt with member's public key)
        return groupKey
    }

    // MARK: - Helper Methods

    private func addUserToGroupMapping(uid: String, groupId: String) {
        if userGroupsMap[uid] == nil {
            userGroupsMap[uid] = []
        }
        userGroupsMap[uid]?.insert(groupId)
    }

    // MARK: - Search & Filter

    /// Search groups by name
    func searchGroups(query: String) -> [Group] {
        guard !query.isEmpty else { return getMyGroups() }

        let lowercasedQuery = query.lowercased()
        return getMyGroups().filter { $0.name.lowercased().contains(lowercasedQuery) }
    }

    /// Get groups where user has a specific role
    func getGroupsByRole(_ role: GroupMember.GroupRole) -> [Group] {
        guard let currentUid = IdentityManager.shared.uid else { return [] }

        return getMyGroups().filter { group in
            group.members.first { $0.uid == currentUid }?.role == role
        }
    }

    // MARK: - Reset

    /// Clear all group data
    func clearAllGroups() {
        groups.removeAll()
        userGroupsMap.removeAll()
        saveGroups()
    }

    /// Remove user from all groups (used when identity is reset)
    func removeUserFromAllGroups(uid: String) {
        guard let groupIds = userGroupsMap[uid] else { return }

        for groupId in groupIds {
            if var group = groups[groupId] {
                group.members.removeAll { $0.uid == uid }
                group.updatedAt = Date()
                groups[groupId] = group
            }
        }

        userGroupsMap.removeValue(forKey: uid)
        saveGroups()
    }
}

// MARK: - Convenience Extensions

extension GroupStore {

    /// Check if current user is owner of a group
    func isOwner(groupId: String) -> Bool {
        guard let group = groups[groupId],
              let currentUid = IdentityManager.shared.uid else { return false }
        return group.ownerUid == currentUid
    }

    /// Check if current user is admin or owner of a group
    func isAdminOrOwner(groupId: String) -> Bool {
        guard let currentUid = IdentityManager.shared.uid,
              let role = getMemberRole(groupId: groupId, uid: currentUid) else { return false }
        return role == .owner || role == .admin
    }

    /// Get count of members in a group
    func memberCount(groupId: String) -> Int {
        return groups[groupId]?.members.count ?? 0
    }

    /// Get groups sorted by last update time
    func getRecentGroups(limit: Int = 10) -> [Group] {
        return getMyGroups()
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }
}