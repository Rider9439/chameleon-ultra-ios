import SwiftUI
import CoreBluetooth

/// 设备页：连接 / 断开 / 设备信息 / 电量
struct DeviceView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    connectionCard
                    if appState.device.ble.isConnected {
                        deviceInfoCard
                    }
                }
                .padding()
            }
            .navigationTitle("设备")
        }
    }

    // MARK: 连接卡片

    private var connectionCard: some View {
        PanelCard(title: "蓝牙连接", icon: "antenna.radiowaves.left.and.right") {
            VStack(spacing: 12) {
                HStack {
                    StatusBadge(
                        text: appState.device.connectionState,
                        color: appState.device.ble.isConnected ? .green : (appState.device.ble.isScanning ? .orange : .gray)
                    )
                    Spacer()
                    if appState.device.ble.isScanning {
                        ProgressView().controlSize(.small)
                    }
                }

                if appState.device.ble.isConnected {
                    if let peripheral = appState.device.ble.connectedPeripheral {
                        Label(peripheral.name ?? "ChameleonUltra", systemImage: "circle.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                    }
                    Button(role: .destructive) {
                        appState.device.disconnect()
                    } label: {
                        Label("断开连接", systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    scanList
                    Button {
                        if appState.device.ble.isScanning {
                            appState.stopScan()
                        } else {
                            appState.startScan()
                        }
                    } label: {
                        Label(appState.device.ble.isScanning ? "停止扫描" : "扫描设备",
                              systemImage: appState.device.ble.isScanning ? "stop.fill" : "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var scanList: some View {
        VStack(spacing: 8) {
            ForEach(Array(appState.device.ble.discoveredPeripherals.enumerated()), id: \.element.peripheral.identifier.uuidString) { _, item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.peripheral.name ?? "未命名设备")
                            .font(.body)
                        Text("RSSI: \(item.rssi) dBm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("连接") {
                        Task { await appState.device.connect(item.peripheral) }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(10)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            }
            if appState.device.ble.discoveredPeripherals.isEmpty {
                Text("点击「扫描设备」查找变色龙")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 设备信息

    private var deviceInfoCard: some View {
        PanelCard(title: "设备信息", icon: "info.circle") {
            VStack(spacing: 10) {
                infoRow("型号", appState.device.capabilities.modelName)
                infoRow("固件版本", appState.device.capabilities.firmwareVersion)
                infoRow("卡槽数", "\(appState.device.capabilities.slotCount) 物理槽")
                if let battery = appState.device.batteryLevel {
                    HStack {
                        Text("电量")
                        Spacer()
                        HStack(spacing: 6) {
                            Gauge(value: Double(battery), in: 0...100) { EmptyView() }
                                .gaugeStyle(.accessoryLinear)
                                .frame(width: 80)
                            Text("\(battery)%")
                                .monospacedDigit()
                        }
                    }
                }
                infoRow("Gen1a 支持", appState.device.capabilities.supportsGen1a ? "是" : "否")
                infoRow("Gen2 支持", appState.device.capabilities.supportsGen2 ? "是" : "否")
                infoRow("NTAG 支持", appState.device.capabilities.supportsNtag ? "是" : "否")
            }
        }
    }

    private func infoRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v).fontWeight(.medium)
        }
        .font(.subheadline)
    }
}
