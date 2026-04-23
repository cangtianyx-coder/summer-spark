import Foundation
import Combine

// MARK: - App Language Enum

/// 支持的语言类型
enum AppLanguage: String, CaseIterable {
    case chinese = "zh-Hans"
    case english = "en"
    
    /// 显示名称
    var displayName: String {
        switch self {
        case .chinese:
            return "中文"
        case .english:
            return "English"
        }
    }
    
    /// 本地化显示名称
    var localizedDisplayName: String {
        switch self {
        case .chinese:
            return "settings_chinese".localized
        case .english:
            return "settings_english".localized
        }
    }
}

// MARK: - Language Manager

/// 语言管理器 - 单例模式，负责应用内语言切换
class LanguageManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = LanguageManager()
    
    // MARK: - Published Properties
    
    /// 当前语言
    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: Keys.selectedLanguage)
        }
    }
    
    // MARK: - Constants
    
    private enum Keys {
        static let selectedLanguage = "com.summerspark.selectedLanguage"
    }
    
    // MARK: - Initialization
    
    private init() {
        // 从 UserDefaults 读取保存的语言设置
        if let savedLanguage = UserDefaults.standard.string(forKey: Keys.selectedLanguage),
           let language = AppLanguage(rawValue: savedLanguage) {
            self.currentLanguage = language
        } else {
            // 默认跟随系统语言
            self.currentLanguage = Self.getSystemLanguage()
        }
    }
    
    // MARK: - Public Methods
    
    /// 获取本地化字符串
    /// - Parameter key: 本地化键
    /// - Returns: 本地化后的字符串
    func localizedString(key: String) -> String {
        let bundle = Bundle.main
        
        // 尝试从当前语言的 bundle 中获取本地化字符串
        if let path = bundle.path(forResource: currentLanguage.rawValue, ofType: "lproj"),
           let languageBundle = Bundle(path: path) {
            return languageBundle.localizedString(forKey: key, value: nil, table: nil)
        }
        
        // 如果找不到，尝试从主 bundle 获取
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
    
    /// 设置语言
    /// - Parameter language: 目标语言
    func setLanguage(_ language: AppLanguage) {
        guard currentLanguage != language else { return }
        
        currentLanguage = language
        
        // 发送语言切换通知
        NotificationCenter.default.post(
            name: .languageDidChange,
            object: nil,
            userInfo: ["language": language.rawValue]
        )
    }
    
    /// 获取所有支持的语言
    func availableLanguages() -> [AppLanguage] {
        return AppLanguage.allCases
    }
    
    // MARK: - Private Methods
    
    /// 获取系统语言
    private static func getSystemLanguage() -> AppLanguage {
        let preferredLanguage = Locale.preferredLanguages.first ?? "en"
        
        if preferredLanguage.hasPrefix("zh") {
            return .chinese
        } else {
            return .english
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// 语言切换通知
    static let languageDidChange = Notification.Name("languageDidChange")
}
