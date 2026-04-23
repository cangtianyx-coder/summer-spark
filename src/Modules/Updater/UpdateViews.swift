import SwiftUI

// MARK: - 更新提示视图

/// 更新提示弹窗
struct UpdateAlertView: View {
    let version: VersionInfo
    let isCritical: Bool
    
    @State private var showingReleaseNotes = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // 图标
            Image(systemName: isCritical ? "exclamationmark.triangle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(isCritical ? .red : .blue)
            
            // 标题
            Text(isCritical ? "critical_update".localized : "update_available".localized)
                .font(.headline)
                .foregroundColor(isCritical ? .red : .primary)
            
            // 版本信息
            VStack(spacing: 8) {
                Text("version".localized + ": \(version.version)")
                    .font(.subheadline)
                
                Text("released".localized + ": \(formatDate(version.releaseDate))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // 更新说明预览
            if !version.releaseNotes.isEmpty {
                Button {
                    showingReleaseNotes = true
                } label: {
                    HStack {
                        Text("view_release_notes".localized)
                            .font(.subheadline)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                }
                .sheet(isPresented: $showingReleaseNotes) {
                    ReleaseNotesView(version: version)
                }
            }
            
            // 按钮
            VStack(spacing: 12) {
                // 更新按钮
                Button {
                    AutoUpdater.shared.openDownloadPage(for: version)
                    dismiss()
                } label: {
                    Text("update_now".localized)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                
                // 跳过按钮 (非关键更新)
                if !isCritical {
                    Button {
                        AutoUpdater.shared.skipVersion(version)
                        dismiss()
                    } label: {
                        Text("skip_this_version".localized)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                
                // 稍后提醒
                Button {
                    dismiss()
                } label: {
                    Text("remind_later".localized)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(24)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 10)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - 更新说明视图

struct ReleaseNotesView: View {
    let version: VersionInfo
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 版本标题
                    HStack {
                        Text("v\(version.version)")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        if version.isCritical {
                            Text("critical".localized)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.2))
                                .foregroundColor(.red)
                                .cornerRadius(4)
                        }
                    }
                    
                    Divider()
                    
                    // 发布日期
                    HStack {
                        Image(systemName: "calendar")
                        Text(formatDate(version.releaseDate))
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    
                    // 更新说明
                    Text(parseMarkdown(version.releaseNotes))
                        .font(.body)
                }
                .padding()
            }
            .navigationTitle("release_notes".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("close".localized) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
    
    private func parseMarkdown(_ text: String) -> AttributedString {
        // 简单的Markdown解析
        do {
            return try AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            return AttributedString(text)
        }
    }
}

// MARK: - 设置中的更新检查视图

struct UpdateCheckView: View {
    @StateObject private var updater = AutoUpdater.shared
    @State private var showingUpdateAlert = false
    @State private var showingNoUpdate = false
    
    var body: some View {
        VStack(spacing: 16) {
            // 当前版本
            HStack {
                Text("current_version".localized)
                Spacer()
                Text(updater.config.currentVersion)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // 检查更新按钮
            Button {
                updater.checkForUpdate(force: true)
            } label: {
                HStack {
                    if updater.isChecking {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("check_for_update".localized)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .disabled(updater.isChecking)
            
            // 上次检查时间
            if let lastCheck = updater.lastCheckDate {
                HStack {
                    Text("last_checked".localized)
                    Spacer()
                    Text(formatRelativeTime(lastCheck))
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            
            // 自动检查开关
            Toggle("auto_check_update".localized, isOn: Binding(
                get: { updater.config.autoCheckEnabled },
                set: { 
                    updater.config.autoCheckEnabled = $0
                    if $0 {
                        updater.startAutoCheck()
                    } else {
                        updater.stopAutoCheck()
                    }
                }
            ))
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(10)
        .onChange(of: updater.lastCheckResult) { result in
            handleCheckResult(result)
        }
        .alert("no_update_available".localized, isPresented: $showingNoUpdate) {
            Button("ok".localized, role: .cancel) {}
        }
        .sheet(item: Binding(
            get: { updater.lastCheckResult?.versionInfo.map { UpdateInfoWrapper(version: $0, isCritical: updater.lastCheckResult?.hasUpdate == true && (updater.lastCheckResult?.versionInfo?.isCritical ?? false)) } },
            set: { _ in }
        )) { wrapper in
            UpdateAlertView(version: wrapper.version, isCritical: wrapper.isCritical)
        }
    }
    
    private func handleCheckResult(_ result: UpdateCheckResult?) {
        guard let result = result else { return }
        
        switch result {
        case .noUpdate:
            showingNoUpdate = true
        case .updateAvailable, .criticalUpdate:
            showingUpdateAlert = true
        default:
            break
        }
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - 辅助类型

struct UpdateInfoWrapper: Identifiable {
    let id = UUID()
    let version: VersionInfo
    let isCritical: Bool
}

// MARK: - 预览

#if DEBUG
@available(iOS 13.0, *)
struct UpdateAlertView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.opacity(0.3)
            UpdateAlertView(
                version: VersionInfo(
                    version: "4.1.0",
                    buildNumber: 100,
                    releaseDate: Date(),
                    releaseNotes: "## 新功能\n- 添加自动更新\n- 修复若干问题",
                    downloadURL: URL(string: "https://github.com"),
                    miniOSVersion: "15.0",
                    isCritical: false
                ),
                isCritical: false
            )
        }
    }
}

@available(iOS 13.0, *)
struct CriticalUpdateView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.opacity(0.3)
            UpdateAlertView(
                version: VersionInfo(
                    version: "5.0.0",
                    buildNumber: 200,
                    releaseDate: Date(),
                    releaseNotes: "[CRITICAL]\n## 安全更新\n- 修复严重安全漏洞",
                    downloadURL: URL(string: "https://github.com"),
                    miniOSVersion: "15.0",
                    isCritical: true
                ),
                isCritical: true
            )
        }
    }
}
#endif
