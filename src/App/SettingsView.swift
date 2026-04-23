import SwiftUI

// MARK: - Settings View

/// 设置视图 - 包含语言切换等功能
@available(iOS 13.0, *)
struct SettingsView: View {
    
    @ObservedObject private var languageManager = LanguageManager.shared
    @State private var showLanguagePicker = false
    
    var body: some View {
        NavigationView {
            List {
                // 语言设置 Section
                Section(header: Text("settings_language".localized)) {
                    // 当前语言
                    HStack {
                        Text("settings_current_language".localized)
                        Spacer()
                        Text(languageManager.currentLanguage.localizedDisplayName)
                            .foregroundColor(.secondary)
                    }
                    
                    // 语言选择按钮
                    Button(action: {
                        showLanguagePicker = true
                    }) {
                        HStack {
                            Text("language_select_title".localized)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // 关于 Section
                Section(header: Text("settings_about".localized)) {
                    // 版本信息
                    HStack {
                        Text("settings_version".localized)
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }
                    
                    // 隐私政策
                    NavigationLink(destination: PrivacyPolicyView()) {
                        Text("settings_privacy".localized)
                    }
                    
                    // 关于页面
                    NavigationLink(destination: AboutView()) {
                        Text("settings_about".localized)
                    }
                }
            }
            .navigationTitle("tab_settings".localized)
            .sheet(isPresented: $showLanguagePicker) {
                LanguagePickerView()
            }
        }
    }
    
    // 获取应用版本
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - Language Picker View

/// 语言选择视图
@available(iOS 13.0, *)
struct LanguagePickerView: View {
    
    @ObservedObject private var languageManager = LanguageManager.shared
    @Environment(\.presentationMode) var presentationMode
    @State private var showRestartAlert = false
    
    var body: some View {
        NavigationView {
            List {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Button(action: {
                        selectLanguage(language)
                    }) {
                        HStack {
                            Text(language.displayName)
                                .foregroundColor(.primary)
                            Spacer()
                            if languageManager.currentLanguage == language {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("language_select_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("btn_disconnect".localized) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .alert(isPresented: $showRestartAlert) {
                Alert(
                    title: Text("language_select_title".localized),
                    message: Text("language_restart_hint".localized),
                    dismissButton: .default(Text("btn_start".localized)) {
                        presentationMode.wrappedValue.dismiss()
                    }
                )
            }
        }
    }
    
    private func selectLanguage(_ language: AppLanguage) {
        guard languageManager.currentLanguage != language else { return }
        
        languageManager.setLanguage(language)
        showRestartAlert = true
    }
}

// MARK: - Privacy Policy View

/// 隐私政策视图
@available(iOS 13.0, *)
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("settings_privacy".localized)
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Summer Spark 隐私政策")
                    .font(.headline)
                
                Text("""
                我们重视您的隐私。Summer Spark 是一款离线优先的通信应用，您的数据安全是我们的首要任务。
                
                数据收集：
                • 我们不收集个人身份信息
                • 位置数据仅存储在您的设备上
                • 通信数据通过端到端加密保护
                
                数据存储：
                • 所有数据存储在您的设备本地
                • 使用加密存储保护敏感信息
                • 您可以随时清除所有数据
                
                第三方服务：
                • 地图数据来自 OpenStreetMap
                • 不使用任何第三方分析服务
                """)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .navigationTitle("settings_privacy".localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - About View

/// 关于视图
@available(iOS 13.0, *)
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // App 图标
                Image(systemName: "ant.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                    .padding(.top, 40)
                
                // App 名称
                Text("app_name".localized)
                    .font(.title)
                    .fontWeight(.bold)
                
                // 版本
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // 描述
                Text("离线优先的网格通信应用")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Spacer()
            }
        }
        .navigationTitle("settings_about".localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 13.0, *)
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
#endif
