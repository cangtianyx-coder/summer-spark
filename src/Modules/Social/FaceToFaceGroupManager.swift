import Foundation
import CryptoKit

// MARK: - FaceToFace Group Manager

/// 面对面建群管理器
/// 负责创建和管理面对面建群流程
final class FaceToFaceGroupManager {
    static let shared = FaceToFaceGroupManager()
    
    // MARK: - Private Properties
    
    /// 当前邀请（如果正在等待加入）
    private var currentInvite: FaceToFaceInvite?
    
    /// 当前群组（如果已创建）
    private var currentGroup: Group?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// 创建面对面群组
    /// - Parameter name: 群组名称
    /// - Returns: (群组, 邀请信息) 或 nil（失败）
    func createFaceToFaceGroup(name: String) -> (Group, FaceToFaceInvite)? {
        // 创建群组（面对面建群免费）
        guard let group = GroupStore.shared.createGroup(name: name) else {
            Logger.shared.error("FaceToFace: Failed to create group")
            return nil
        }
        
        // 生成邀请信息
        let invite = FaceToFaceInvite(groupId: group.id, groupName: group.name)
        
        // 保存当前状态
        currentGroup = group
        currentInvite = invite
        
        Logger.shared.info("FaceToFace: Created group \(group.id) with invite code \(invite.numericCode)")
        
        return (group, invite)
    }
    
    /// 加入面对面群组
    /// - Parameter invite: 邀请信息
    /// - Returns: 是否成功
    @discardableResult
    func joinGroup(with invite: FaceToFaceInvite) -> Result<Group, FaceToFaceGroupError> {
        // 检查是否已过期
        if invite.isExpired {
            Logger.shared.warn("FaceToFace: Invite \(invite.groupId) has expired")
            return .failure(.inviteExpired)
        }
        
        // 检查群组是否存在
        guard let group = GroupStore.shared.getGroup(id: invite.groupId) else {
            Logger.shared.warn("FaceToFace: Group \(invite.groupId) not found")
            return .failure(.groupNotFound)
        }
        
        // 获取当前用户UID
        guard let currentUid = IdentityManager.shared.uid else {
            Logger.shared.error("FaceToFace: Current user UID not found")
            return .failure(.unknown)
        }
        
        // 检查是否已是成员
        if GroupStore.shared.isMember(groupId: invite.groupId, uid: currentUid) {
            Logger.shared.info("FaceToFace: User \(currentUid) is already a member of group \(invite.groupId)")
            return .failure(.alreadyMember)
        }
        
        // 添加用户到群组（绕过权限检查，面对面建群邀请码验证即授权）
        let success = GroupStore.shared.addMemberWithoutPermission(groupId: invite.groupId, uid: currentUid, role: .member)

        if success {
            Logger.shared.info("FaceToFace: User \(currentUid) joined group \(invite.groupId)")
            return .success(group)
        } else {
            Logger.shared.error("FaceToFace: Failed to add user \(currentUid) to group \(invite.groupId)")
            return .failure(.unknown)
        }
    }

    /// 加入群组（通过数字码）
    /// - Parameter code: 6位数字邀请码
    /// - Returns: 是否成功
    @discardableResult
    func joinGroup(withNumericCode code: String) -> Result<Group, FaceToFaceGroupError> {
        // 尝试从数字码反向解码获取groupId前缀
        guard let prefix = FaceToFaceInvite.decodeGroupIdPrefix(from: code) else {
            Logger.shared.warn("FaceToFace: Failed to decode numeric code \(code)")
            return .failure(.invalidInvite)
        }
        
        // 通过前缀在本地查找匹配的群组
        // 由于数字码只编码了groupId的前4字节，需要遍历查找
        guard let currentUid = IdentityManager.shared.uid else {
            return .failure(.unknown)
        }
        
        // 获取用户所在的所有群组
        let userGroups = GroupStore.shared.getMyGroups()
        
        // 查找与前缀匹配的群组
        var matchedGroup: Group?
        for group in userGroups {
            let cleanedId = group.id.filter { $0.isLetter || $0.isNumber }
            let groupPrefix = String(cleanedId.prefix(8))
            let groupCode = FaceToFaceInvite.generateNumericCode(for: group.id)
            
            if groupCode == code && groupPrefix.hasPrefix(String(prefix.prefix(4))) {
                matchedGroup = group
                break
            }
        }
        
        guard let group = matchedGroup else {
            return .failure(.groupNotFound)
        }
        
        // P0-FIX: Add expiry check for numeric code join (security fix)
        // The invite stored in currentInvite has expiresAt - check if expired
        if let invite = currentInvite, invite.isExpired {
            Logger.shared.warn("FaceToFace: Invite via numeric code has expired")
            return .failure(.inviteExpired)
        }
        
        // 检查是否已是成员
        if GroupStore.shared.isMember(groupId: group.id, uid: currentUid) {
            return .failure(.alreadyMember)
        }
        
        // 添加用户到群组（绕过权限检查，面对面建群邀请码验证即授权）
        let success = GroupStore.shared.addMemberWithoutPermission(groupId: group.id, uid: currentUid, role: .member)

        if success {
            Logger.shared.info("FaceToFace: User \(currentUid) joined group \(group.id) via numeric code")
            return .success(group)
        } else {
            return .failure(.unknown)
        }
    }

    /// 解析二维码内容
    /// - Parameter content: 二维码扫描结果
    /// - Returns: 邀请信息或nil
    func parseQRCode(_ content: String) -> FaceToFaceInvite? {
        return FaceToFaceInvite(jsonString: content)
    }
    
    /// 解析数字邀请码
    /// - Parameters:
    ///   - code: 6位数字码
    ///   - groupId: 群组ID
    /// - Returns: 是否有效
    func validateNumericCode(_ code: String, for groupId: String) -> Bool {
        return FaceToFaceInvite.validateNumericCode(code, for: groupId)
    }
    
    /// 获取当前邀请
    func getCurrentInvite() -> FaceToFaceInvite? {
        return currentInvite
    }
    
    /// 获取当前群组
    func getCurrentGroup() -> Group? {
        return currentGroup
    }
    
    /// 清除当前状态
    func clearCurrentState() {
        currentInvite = nil
        currentGroup = nil
    }
}

// MARK: - QR Code Generation Extension

extension FaceToFaceGroupManager {
    
    /// 生成群组邀请二维码
    /// - Parameter invite: 邀请信息
    /// - Returns: UIImage二维码
    func generateQRCode(for invite: FaceToFaceInvite) -> UIImage? {
        guard let jsonString = invite.toJSONString() else {
            Logger.shared.error("FaceToFace: Failed to serialize invite for QR code")
            return nil
        }
        
        return generateQRCodeImage(from: jsonString)
    }
    
    /// 生成二维码图片
    /// - Parameter string: 要编码的字符串
    /// - Returns: UIImage二维码
    private func generateQRCodeImage(from string: String) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let scale = 10.0 / outputImage.extent.width
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Import UIKit for UIImage

import UIKit
