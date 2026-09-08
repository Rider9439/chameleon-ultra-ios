import SwiftUI
import MapKit

/// 电子围栏页：进入/离开地理区域自动切换卡槽
struct FenceView: View {
    @EnvironmentObject var appState: AppState

    @State private var showAddSheet = false
    @State private var newName = ""
    @State private var newLat = "39.9042"
    @State private var newLon = "116.4074"
    @State private var newRadius = 100.0
    @State private var newSlot = 1
    @State private var newFallbackSlot = 8

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusCard
                    fencesList
                }
                .padding()
            }
            .navigationTitle("电子围栏")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Label("添加", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) { addFenceSheet }
        }
    }

    private var statusCard: some View {
        PanelCard(title: "监控状态", icon: "location.circle") {
            VStack(spacing: 12) {
                HStack {
                    StatusBadge(
                        text: appState.geofence.isAuthorized ? "定位已授权" : "未授权定位",
                        color: appState.geofence.isAuthorized ? .green : .red
                    )
                    StatusBadge(
                        text: appState.geofence.isMonitoring ? "监控中" : "已暂停",
                        color: appState.geofence.isMonitoring ? .blue : .gray
                    )
                    Spacer()
                }
                if let last = appState.geofence.lastEvent {
                    Text(last)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button("开启监控") { appState.geofence.startAll() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!appState.geofence.isAuthorized)
                    Button("暂停") { appState.geofence.stopAll() }
                        .buttonStyle(.bordered)
                    if !appState.geofence.isAuthorized {
                        Button("授权定位") { appState.geofence.requestAuthorization() }
                            .buttonStyle(.bordered)
                    }
                }
                Text("进入围栏自动切换到指定卡位，离开时切回备用卡位。后台需开启「始终允许」定位权限。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fencesList: some View {
        PanelCard(title: "围栏列表（\(appState.geofence.fences.count)）", icon: "mappin.and.ellipse") {
            if appState.geofence.fences.isEmpty {
                Text("暂无围栏，点击右上角「+」添加")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.geofence.fences) { fence in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fence.name).font(.subheadline)
                            Text(String(format: "%.4f, %.4f  半径 %.0fm", fence.latitude, fence.longitude, fence.radius))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("进入 → 卡位 \(fence.slotIndex + 1)" + (fence.fallbackSlotIndex.map { "，离开 → 卡位 \($0 + 1)" } ?? ""))
                                .font(.caption)
                                .foregroundStyle(.teal)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            appState.geofence.removeFence(id: fence.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var addFenceSheet: some View {
        NavigationStack {
            Form {
                Section("围栏信息") {
                    TextField("名称", text: $newName)
                    TextField("纬度", text: $newLat)
                        .keyboardType(.decimalPad)
                    TextField("经度", text: $newLon)
                        .keyboardType(.decimalPad)
                    Stepper("半径: \(Int(newRadius)) 米", value: $newRadius, in: 25...1000, step: 25)
                }
                Section("自动切换") {
                    Picker("进入时切换卡位", selection: $newSlot) {
                        ForEach(1...16, id: \.self) { Text("卡位 \($0)").tag($0) }
                    }
                    Picker("离开时切回", selection: $newFallbackSlot) {
                        Text("不切换").tag(0)
                        ForEach(1...16, id: \.self) { Text("卡位 \($0)").tag($0) }
                    }
                }
                Section {
                    Button("保存围栏") {
                        guard let lat = Double(newLat), let lon = Double(newLon), !newName.isEmpty else {
                            appState.report("请填写名称与有效的经纬度")
                            return
                        }
                        let entry = GeofenceEntry(
                            name: newName,
                            latitude: lat,
                            longitude: lon,
                            radius: newRadius,
                            slotIndex: newSlot - 1,
                            fallbackSlotIndex: newFallbackSlot > 0 ? newFallbackSlot - 1 : nil
                        )
                        appState.geofence.addFence(entry: entry)
                        showAddSheet = false
                        newName = ""
                    }
                }
            }
            .navigationTitle("添加围栏")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showAddSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
