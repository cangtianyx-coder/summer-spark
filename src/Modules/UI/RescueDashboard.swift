import SwiftUI

// MARK: - Rescue Dashboard

/// 救援态势仪表盘
struct RescueDashboard: View {
    @State private var statistics: RescueStatistics?
    @State private var activeTasks: [RescueTask] = []
    @State private var victimMarkers: [VictimMarker] = []
    @State private var evacuationStats: EvacuationStatistics?
    
    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 统计概览
                    StatisticsOverview(statistics: statistics, evacuationStats: evacuationStats)
                    
                    // 紧急任务
                    UrgentTasksSection(tasks: activeTasks)
                    
                    // 伤员标记
                    VictimMarkersSection(markers: victimMarkers)
                    
                    // 快速操作
                    QuickActionsSection()
                }
                .padding()
            }
            .navigationTitle("救援态势")
            .refreshable {
                refreshData()
            }
            .onReceive(refreshTimer) { _ in
                refreshData()
            }
            .onAppear {
                refreshData()
            }
        }
    }
    
    private func refreshData() {
        statistics = RescueCoordinator.shared.getStatistics()
        activeTasks = RescueCoordinator.shared.getUrgentTasks()
        victimMarkers = VictimMarkerManager.shared.getAllMarkers()
        evacuationStats = EvacuationPlanner.shared.getStatistics()
    }
}

// MARK: - Statistics Overview

struct StatisticsOverview: View {
    let statistics: RescueStatistics?
    let evacuationStats: EvacuationStatistics?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("救援统计")
                .font(.headline)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(title: "救援队", value: "\(statistics?.totalTeams ?? 0)", subtitle: "可用: \(statistics?.availableTeams ?? 0)", color: .blue)
                StatCard(title: "任务", value: "\(statistics?.totalTasks ?? 0)", subtitle: "进行中: \(statistics?.inProgressTasks ?? 0)", color: .orange)
                StatCard(title: "撤离点", value: "\(evacuationStats?.totalPoints ?? 0)", subtitle: "容量: \(evacuationStats?.currentOccupancy ?? 0)/\(evacuationStats?.totalCapacity ?? 0)", color: .green)
                StatCard(title: "搜索区域", value: "\(statistics?.searchAreas ?? 0)", subtitle: "", color: .purple)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

// MARK: - Urgent Tasks Section

struct UrgentTasksSection: View {
    let tasks: [RescueTask]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("紧急任务")
                    .font(.headline)
                Spacer()
                Text("\(tasks.count) 个")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if tasks.isEmpty {
                Text("暂无紧急任务")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(tasks.prefix(5)) { task in
                    TaskRow(task: task)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct TaskRow: View {
    let task: RescueTask
    
    var body: some View {
        HStack {
            Image(systemName: taskIcon)
                .foregroundColor(taskColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(task.type.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(task.status.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            PriorityBadge(priority: task.priority)
        }
        .padding(.vertical, 4)
    }
    
    var taskIcon: String {
        switch task.type {
        case .search: return "magnifyingglass"
        case .rescue: return "cross.case"
        case .evacuate: return "figure.walk"
        case .supply: return "box.truck"
        case .medical: return "cross.vial"
        case .reconnaissance: return "binoculars"
        }
    }
    
    var taskColor: Color {
        switch task.priority {
        case 1: return .red
        case 2: return .orange
        default: return .blue
        }
    }
}

struct PriorityBadge: View {
    let priority: Int
    
    var body: some View {
        Text("P\(priority)")
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(priorityColor.opacity(0.2))
            .foregroundColor(priorityColor)
            .cornerRadius(4)
    }
    
    var priorityColor: Color {
        switch priority {
        case 1: return .red
        case 2: return .orange
        default: return .gray
        }
    }
}

// MARK: - Victim Markers Section

struct VictimMarkersSection: View {
    let markers: [VictimMarker]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("伤员标记")
                    .font(.headline)
                Spacer()
                Text("\(markers.count) 个")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if markers.isEmpty {
                Text("暂无伤员标记")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(markers.prefix(5)) { marker in
                    VictimRow(marker: marker)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct VictimRow: View {
    let marker: VictimMarker
    
    var body: some View {
        HStack {
            SeverityIndicator(severity: marker.severity)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(marker.severity.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(marker.status.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if let responder = marker.assignedResponder {
                Image(systemName: "person.badge.checkmark")
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SeverityIndicator: View {
    let severity: Severity
    
    var body: some View {
        Circle()
            .fill(severityColor)
            .frame(width: 12, height: 12)
    }
    
    var severityColor: Color {
        switch severity {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .green
        }
    }
}

// MARK: - Quick Actions Section

struct QuickActionsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快速操作")
                .font(.headline)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                QuickActionButton(title: "创建救援队", icon: "person.3.fill", color: .blue) {
                    // TODO: 创建救援队界面
                }
                
                QuickActionButton(title: "标记伤员", icon: "cross.case.fill", color: .red) {
                    // TODO: 标记伤员界面
                }
                
                QuickActionButton(title: "撤离点", icon: "location.fill", color: .green) {
                    // TODO: 创建撤离点界面
                }
                
                QuickActionButton(title: "紧急通道", icon: "antenna.radiowaves.left.and.right", color: .orange) {
                    // TODO: 紧急通道界面
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(8)
        }
    }
}

// MARK: - Preview

#Preview {
    RescueDashboard()
}
