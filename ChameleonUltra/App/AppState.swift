import Foundation
import SwiftUI
import CoreBluetooth

/// 全局应用状态：设备、卡槽、围栏、轮询、卡库
@MainActor
final class AppState: ObservableObject {

    @Published var device = ChameleonDevice()
    @Published var library = CardLibrary()
    @Published var geofence = GeofenceManager()
    @Published var polling = PollingManager()

    @Published var selectedTab = 0
    @Published var showError = false
    @Published var errorMessage = ""

    init() {
        // 围栏切换卡槽 → 设备
        geofence.onSwitchSlot = { [weak self] logicalIndex in
            Task { @MainActor in
                // logicalIndex 0..<16 表示 IC 卡位（与 ID 共用物理槽）
                _ = await self?.device.activateSlot(bank: .ic, number: logicalIndex)
            }
        }
        // 轮询出卡 → 设备
        polling.onActivateSlot = { [weak self] logicalIndex in
            Task { @MainActor in
                _ = await self?.device.activateSlot(bank: .ic, number: logicalIndex)
            }
        }
    }

    // MARK: - 便捷错误处理

    func report(_ message: String) {
        errorMessage = message
        showError = true
    }

    // MARK: - 蓝牙扫描 / 自动连接

    func startScan() {
        device.startScan()
    }

    func stopScan() {
        device.ble.stopScan()
    }

    /// 进入前台自动扫描 + 自动连接上次设备（蓝牙未就绪则等待重试）
    func autoConnect() {
        guard !device.ble.isConnected, !device.ble.isScanning else { return }
        // 等待蓝牙就绪（CBCentralManager 状态异步）
        Task { @MainActor in
            for _ in 0..<10 {
                if device.ble.isConnected { return }
                device.startScan()
                try? await Task.sleep(nanoseconds: 300_000_000)
                if device.ble.isConnected || device.ble.discoveredPeripherals.contains(where: { $0.peripheral.identifier == BleConnection.lastConnectedID }) {
                    return
                }
            }
        }
    }
}
