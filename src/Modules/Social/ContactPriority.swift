import Foundation

// MARK: - Contact Priority

/// 紧急联系人管理器
final class ContactPriority {
    static let shared = ContactPriority()
    
    private var contacts: [UUID: EmergencyContact] = [:]
    private let queue = DispatchQueue(label: "com.summerspark.contactpriority", attributes: .concurrent)
    
    private let storageKey = "emergency.contacts"
    
    weak var delegate: ContactPriorityDelegate?
    
    private init() {
        loadContacts()
    }
    
    // MARK: - Contact Management
    
    /// 添加紧急联系人
    func addContact(contactId: String, priority: Int = 1, alias: String? = nil) -> EmergencyContact? {
        guard let uid = IdentityManager.shared.uid else { return nil }
        
        // 检查是否已存在
        if let existing = getContactByUserId(contactId) {
            Logger.shared.info("ContactPriority: Contact \(contactId) already exists")
            return existing
        }
        
        let contact = EmergencyContact(userId: uid, contactId: contactId, priority: priority, alias: alias)
        
        queue.sync(flags: .barrier) {
            contacts[contact.id] = contact
        }
        
        saveContacts()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.contactPriority(self, didAddContact: contact)
        }
        
        Logger.shared.info("ContactPriority: Added emergency contact \(contactId) with priority \(priority)")
        return contact
    }
    
    /// 移除紧急联系人
    func removeContact(_ contactId: UUID) -> Bool {
        var removed: EmergencyContact?
        
        queue.sync(flags: .barrier) {
            removed = contacts.removeValue(forKey: contactId)
        }
        
        if removed != nil {
            saveContacts()
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let contact = removed else { return }
                self.delegate?.contactPriority(self, didRemoveContact: contact)
            }
            
            Logger.shared.info("ContactPriority: Removed contact \(contactId)")
            return true
        }
        
        return false
    }
    
    /// 更新联系人优先级
    func updatePriority(_ contactId: UUID, priority: Int) -> Bool {
        return queue.sync(flags: .barrier) {
            guard var contact = contacts[contactId] else { return false }
            
            contact.priority = priority
            contacts[contactId] = contact
            return true
        }
    }
    
    /// 更新联系人别名
    func updateAlias(_ contactId: UUID, alias: String?) -> Bool {
        return queue.sync(flags: .barrier) {
            guard var contact = contacts[contactId] else { return false }
            
            contact.alias = alias
            contacts[contactId] = contact
            return true
        }
    }
    
    /// 设置紧急通知开关
    func setNotifyOnEmergency(_ contactId: UUID, notify: Bool) -> Bool {
        return queue.sync(flags: .barrier) {
            guard var contact = contacts[contactId] else { return false }
            
            contact.notifyOnEmergency = notify
            contacts[contactId] = contact
            return true
        }
    }
    
    // MARK: - Query
    
    /// 获取所有紧急联系人
    func getEmergencyContacts() -> [EmergencyContact] {
        return queue.sync {
            Array(contacts.values).sorted { $0.priority < $1.priority }
        }
    }
    
    /// 根据用户ID获取联系人
    func getContactByUserId(_ userId: String) -> EmergencyContact? {
        return queue.sync {
            contacts.values.first { $0.contactId == userId }
        }
    }
    
    /// 获取最高优先级联系人
    func getTopPriorityContact() -> EmergencyContact? {
        return queue.sync {
            contacts.values.min { $0.priority < $1.priority }
        }
    }
    
    /// 获取应该通知紧急情况的联系人
    func getContactsToNotifyOnEmergency() -> [EmergencyContact] {
        return queue.sync {
            contacts.values
                .filter { $0.notifyOnEmergency }
                .sorted { $0.priority < $1.priority }
        }
    }
    
    /// 紧急联系人数量
    func contactCount() -> Int {
        return queue.sync { contacts.count }
    }
    
    // MARK: - Quick Actions
    
    /// 一键呼叫最高优先级联系人
    func callTopPriorityContact() {
        guard let contact = getTopPriorityContact() else {
            Logger.shared.warn("ContactPriority: No emergency contacts configured")
            return
        }
        
        // 发起语音呼叫
        VoiceService.shared.startP2PCall(with: contact.contactId)
        
        Logger.shared.info("ContactPriority: Calling top priority contact \(contact.contactId)")
    }
    
    /// 通知所有紧急联系人
    func notifyAllEmergencyContacts(message: String) {
        let contactsToNotify = getContactsToNotifyOnEmergency()
        
        for contact in contactsToNotify {
            // 发送紧急消息
            guard let messageData = message.data(using: .utf8) else { continue }
            
            let meshMessage = MeshMessage(
                source: IdentityManager.shared.uid.flatMap { UUID(uuidString: $0) } ?? UUID(),
                destination: UUID(uuidString: contact.contactId),
                payload: messageData,
                ttl: 64,
                messageType: .emergency
            )
            
            MeshService.shared.sendEmergencyMessage(meshMessage)
        }
        
        Logger.shared.info("ContactPriority: Notified \(contactsToNotify.count) emergency contacts")
    }
    
    // MARK: - Persistence
    
    private func saveContacts() {
        let contactList = queue.sync { Array(contacts.values) }
        
        guard let data = try? JSONEncoder().encode(contactList) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
    
    private func loadContacts() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let contactList = try? JSONDecoder().decode([EmergencyContact].self, from: data) else {
            return
        }
        
        queue.sync(flags: .barrier) {
            for contact in contactList {
                contacts[contact.id] = contact
            }
        }
    }
}

// MARK: - Delegate

protocol ContactPriorityDelegate: AnyObject {
    func contactPriority(_ manager: ContactPriority, didAddContact contact: EmergencyContact)
    func contactPriority(_ manager: ContactPriority, didRemoveContact contact: EmergencyContact)
    func contactPriority(_ manager: ContactPriority, didUpdateContact contact: EmergencyContact)
}
