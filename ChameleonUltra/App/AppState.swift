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

    // MARK: - 蓝牙扫描

    func startScan() {
        device.startScan()
    }

    func stopScan() {
        device.ble.stopScan()
    }
}
