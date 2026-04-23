import Foundation
import UIKit

// MARK: - 版本信息

/// 版本信息结构
struct VersionInfo: Codable, Comparable {
    let version: String           // 如 "4.0.0"
    let buildNumber: Int          // 构建号
    let releaseDate: Date         // 发布日期
    let releaseNotes: String      // 更新说明
    let downloadURL: URL?         // 下载链接
    let miniOSVersion: String     // 最低iOS版本要求
    let isCritical: Bool          // 是否为关键更新
    
    /// 从GitHub Release解析
    static func fromGitHubRelease(_ release: GitHubRelease) -> VersionInfo? {
        // 解析版本号 (格式: v4.0.0 或 4.0.0)
        var versionString = release.tagName
        if versionString.hasPrefix("v") {
            versionString = String(versionString.dropFirst())
        }
        
        // 解析构建号 (从版本字符串或使用默认值)
        let buildNumber = extractBuildNumber(from: release.name) ?? 1
        
        return VersionInfo(
            version: versionString,
            buildNumber: buildNumber,
            releaseDate: release.publishedAt,
            releaseNotes: release.body ?? "",
            downloadURL: URL(string: release.htmlUrl),
            miniOSVersion: "15.0",
            isCritical: release.body?.contains("[CRITICAL]") ?? false
        )
    }
    
    private static func extractBuildNumber(from name: String) -> Int? {
        // 尝试从名称提取构建号 (格式: "v4.0.0 (build 123)")
        let pattern = #"build\s+(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let range = Range(match.range(at: 1), in: name) else {
            return nil
        }
        return Int(String(name[range]))
    }
    
    /// 比较版本号
    static func < (lhs: VersionInfo, rhs: VersionInfo) -> Bool {
        return compareVersions(lhs.version, rhs.version) < 0
    }
    
    static func == (lhs: VersionInfo, rhs: VersionInfo) -> Bool {
        return lhs.version == rhs.version && lhs.buildNumber == rhs.buildNumber
    }
    
    /// 版本比较辅助函数
    static func compareVersions(_ v1: String, _ v2: String) -> Int {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }
        
        for i in 0..<max(parts1.count, parts2.count) {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 < p2 { return -1 }
            if p1 > p2 { return 1 }
        }
        return 0
    }
}

/// GitHub Release API响应结构
struct GitHubRelease: Codable {
    let id: Int
    let tagName: String
    let name: String
    let body: String?
    let publishedAt: Date
    let htmlUrl: String
    let assets: [GitHubAsset]
    
    enum CodingKeys: String, CodingKey {
        case id, name, body, assets
        case tagName = "tag_name"
        case publishedAt = "published_at"
        case htmlUrl = "html_url"
    }
}

struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String
    let size: Int
    let contentType: String
    
    enum CodingKeys: String, CodingKey {
        case name, size
        case browserDownloadUrl = "browser_download_url"
        case contentType = "content_type"
    }
}

// MARK: - 更新检查结果

enum UpdateCheckResult: Equatable {
    case noUpdate           // 已是最新版本
    case updateAvailable(VersionInfo)  // 有更新
    case criticalUpdate(VersionInfo)   // 关键更新
    case error(String)      // 检查失败
    
    var hasUpdate: Bool {
        switch self {
        case .updateAvailable, .criticalUpdate:
            return true
        default:
            return false
        }
    }
    
    var versionInfo: VersionInfo? {
        switch self {
        case .updateAvailable(let v), .criticalUpdate(let v):
            return v
        default:
            return nil
        }
    }
    
    static func == (lhs: UpdateCheckResult, rhs: UpdateCheckResult) -> Bool {
        switch (lhs, rhs) {
        case (.noUpdate, .noUpdate):
            return true
        case (.updateAvailable(let lv), .updateAvailable(let rv)):
            return lv == rv
        case (.criticalUpdate(let lv), .criticalUpdate(let rv)):
            return lv == rv
        case (.error(let le), .error(let re)):
            return le == re
        default:
            return false
        }
    }
}

// MARK: - AutoUpdater

/// 自动更新管理器
final class AutoUpdater: ObservableObject {
    
    // MARK: - 单例
    
    static let shared = AutoUpdater()
    
    // MARK: - 配置
    
    struct Config {
        /// GitHub仓库 (owner/repo)
        var repository: String = "cangtianyx-coder/summer-spark"
        
        /// 检查间隔 (秒)
        var checkInterval: TimeInterval = 86400 // 24小时
        
        /// 是否自动检查
        var autoCheckEnabled: Bool = true
        
        /// 是否自动下载
        var autoDownloadEnabled: Bool = false
        
        /// 当前版本
        var currentVersion: String {
            return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        }
        
        /// 当前构建号
        var currentBuildNumber: Int {
            return Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1") ?? 1
        }
        
        init() {}
    }
    
    var config = Config()
    
    // MARK: - 发布属性
    
    @Published var isChecking: Bool = false
    @Published var lastCheckDate: Date?
    @Published var lastCheckResult: UpdateCheckResult?
    @Published var downloadProgress: Double = 0
    @Published var isDownloading: Bool = false
    
    // MARK: - 私有属性
    
    private let session: URLSession
    private var checkTimer: Timer?
    private let userDefaults = UserDefaults.standard
    
    private let lastCheckKey = "com.summerspark.autoupdater.lastcheck"
    private let skippedVersionKey = "com.summerspark.autoupdater.skipped"
    
    // MARK: - 初始化
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
        
        // 恢复上次检查时间
        if let lastCheck = userDefaults.object(forKey: lastCheckKey) as? Date {
            lastCheckDate = lastCheck
        }
    }
    
    // MARK: - 公开方法
    
    /// 启动自动检查
    func startAutoCheck() {
        guard config.autoCheckEnabled else { return }
        
        // 立即检查一次
        checkForUpdate()
        
        // 设置定时检查
        stopAutoCheck()
        checkTimer = Timer.scheduledTimer(withTimeInterval: config.checkInterval, repeats: true) { [weak self] _ in
            self?.checkForUpdate()
        }
    }
    
    /// 停止自动检查
    func stopAutoCheck() {
        checkTimer?.invalidate()
        checkTimer = nil
    }
    
    /// 检查更新
    func checkForUpdate(force: Bool = false) {
        guard !isChecking else { return }
        
        // 如果不是强制检查，且最近检查过，跳过
        if !force, let lastCheck = lastCheckDate,
           Date().timeIntervalSince(lastCheck) < 3600 { // 1小时内不重复检查
            return
        }
        
        DispatchQueue.main.async {
            self.isChecking = true
        }
        
        Task {
            do {
                let result = try await performCheck()
                await MainActor.run {
                    self.lastCheckResult = result
                    self.lastCheckDate = Date()
                    self.userDefaults.set(Date(), forKey: self.lastCheckKey)
                    self.isChecking = false
                    
                    // 通知代理
                    self.notifyUpdateResult(result)
                }
            } catch {
                await MainActor.run {
                    self.lastCheckResult = .error(error.localizedDescription)
                    self.isChecking = false
                }
            }
        }
    }
    
    /// 跳过此版本
    func skipVersion(_ version: VersionInfo) {
        userDefaults.set(version.version, forKey: skippedVersionKey)
    }
    
    /// 是否已跳过此版本
    func isVersionSkipped(_ version: VersionInfo) -> Bool {
        return userDefaults.string(forKey: skippedVersionKey) == version.version
    }
    
    /// 打开下载页面
    func openDownloadPage(for version: VersionInfo) {
        guard let url = version.downloadURL else { return }
        UIApplication.shared.open(url)
    }
    
    /// 打开GitHub Releases页面
    func openReleasesPage() {
        let url = URL(string: "https://github.com/\(config.repository)/releases")!
        UIApplication.shared.open(url)
    }
    
    // MARK: - 私有方法
    
    private func performCheck() async throws -> UpdateCheckResult {
        // 获取GitHub最新Release
        let release = try await fetchLatestRelease()
        
        // 解析版本信息
        guard let latestVersion = VersionInfo.fromGitHubRelease(release) else {
            throw AutoUpdaterError.invalidVersion
        }
        
        // 创建当前版本信息
        let currentVersion = VersionInfo(
            version: config.currentVersion,
            buildNumber: config.currentBuildNumber,
            releaseDate: Date(),
            releaseNotes: "",
            downloadURL: nil,
            miniOSVersion: "15.0",
            isCritical: false
        )
        
        // 比较版本
        if latestVersion > currentVersion {
            // 检查是否已跳过
            if isVersionSkipped(latestVersion) && !latestVersion.isCritical {
                return .noUpdate
            }
            
            // 检查iOS版本要求
            if !isiOSVersionSupported(latestVersion.miniOSVersion) {
                return .error("需要iOS \(latestVersion.miniOSVersion)或更高版本")
            }
            
            return latestVersion.isCritical ? .criticalUpdate(latestVersion) : .updateAvailable(latestVersion)
        }
        
        return .noUpdate
    }
    
    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(config.repository)/releases/latest")!
        
        var request = URLRequest(url: url)
        request.addValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.addValue("SummerSpark/\(config.currentVersion)", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AutoUpdaterError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(GitHubRelease.self, from: data)
        case 404:
            throw AutoUpdaterError.noReleaseFound
        case 403:
            throw AutoUpdaterError.rateLimited
        default:
            throw AutoUpdaterError.httpError(httpResponse.statusCode)
        }
    }
    
    private func isiOSVersionSupported(_ requiredVersion: String) -> Bool {
        let currentSystemVersion = UIDevice.current.systemVersion
        return VersionInfo.compareVersions(currentSystemVersion, requiredVersion) >= 0
    }
    
    private func notifyUpdateResult(_ result: UpdateCheckResult) {
        switch result {
        case .criticalUpdate(let version):
            NotificationCenter.default.post(
                name: .criticalUpdateAvailable,
                object: nil,
                userInfo: ["version": version]
            )
        case .updateAvailable(let version):
            NotificationCenter.default.post(
                name: .updateAvailable,
                object: nil,
                userInfo: ["version": version]
            )
        default:
            break
        }
    }
    
    // MARK: - 清理
    
    deinit {
        stopAutoCheck()
    }
}

// MARK: - 错误类型

enum AutoUpdaterError: Error, LocalizedError {
    case invalidVersion
    case invalidResponse
    case noReleaseFound
    case rateLimited
    case httpError(Int)
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .invalidVersion:
            return "无效的版本格式"
        case .invalidResponse:
            return "服务器响应无效"
        case .noReleaseFound:
            return "未找到发布版本"
        case .rateLimited:
            return "GitHub API请求频率限制，请稍后重试"
        case .httpError(let code):
            return "网络错误: \(code)"
        case .networkError:
            return "网络连接失败"
        }
    }
}

// MARK: - 通知名称

extension Notification.Name {
    static let updateAvailable = Notification.Name("com.summerspark.update.available")
    static let criticalUpdateAvailable = Notification.Name("com.summerspark.update.critical")
}
