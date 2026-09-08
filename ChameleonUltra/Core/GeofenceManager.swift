import Foundation
import CoreLocation

/// 电子围栏：进入/离开地理区域时自动切换指定卡槽
/// 与 ChameleonDevice 协作：CLCircularRegion 进入 → 激活配置的卡槽。
@MainActor
final class GeofenceManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    @Published var fences: [GeofenceEntry] = []
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isMonitoring = false
    @Published var lastEvent: String?

    var onSwitchSlot: ((Int) -> Void)?

    private let locationManager = CLLocationManager()
    private var enteredRegions: Set<String> = []

    override init() {
        super.init()
        locationManager.delegate = self
        loadFences()
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    /// 请求定位权限
    func requestAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    /// 添加围栏
    func addFence(entry: GeofenceEntry) {
        fences.append(entry)
        saveFences()
        if isAuthorized {
            startMonitoring(entry)
        }
    }

    /// 删除围栏
    func removeFence(id: UUID) {
        guard let entry = fences.first(where: { $0.id == id }) else { return }
        if let region = entry.region {
            locationManager.stopMonitoring(for: region)
        }
        fences.removeAll { $0.id == id }
        enteredRegions.remove(entry.id.uuidString)
        saveFences()
    }

    /// 开始监控所有围栏
    func startAll() {
        guard isAuthorized else {
            requestAuthorization()
            return
        }
        for entry in fences {
            startMonitoring(entry)
        }
        isMonitoring = true
    }

    /// 停止所有围栏
    func stopAll() {
        for entry in fences where entry.region != nil {
            locationManager.stopMonitoring(for: entry.region!)
        }
        isMonitoring = false
    }

    /// 供 AppState 在状态恢复时调用
    func resumeMonitoring() {
        if isMonitoring { startAll() }
    }

    private func startMonitoring(_ entry: GeofenceEntry) {
        guard let region = entry.region else { return }
        locationManager.startMonitoring(for: region)
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                self.startAll()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        handle(region, entered: true)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        handle(region, entered: false)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        Task { @MainActor in
            self.lastEvent = "监控失败: \(error.localizedDescription)"
        }
    }

    private func handle(_ region: CLRegion, entered: Bool) {
        Task { @MainActor in
            guard let entry = self.fences.first(where: { $0.id.uuidString == region.identifier }) else { return }
            if entered {
                self.enteredRegions.insert(entry.id.uuidString)
                self.lastEvent = "进入「\(entry.name)」→ 切换卡槽 \(entry.slotIndex + 1)"
                self.onSwitchSlot?(entry.slotIndex)
            } else {
                self.enteredRegions.remove(entry.id.uuidString)
                self.lastEvent = "离开「\(entry.name)」"
                if let fallback = entry.fallbackSlotIndex {
                    self.onSwitchSlot?(fallback)
                }
            }
        }
    }

    // MARK: - 持久化

    private static let storageKey = "geofence_entries_v1"

    private func saveFences() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(fences) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func loadFences() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([GeofenceEntry].self, from: data) else { return }
        fences = decoded
    }
}

/// 单个围栏条目（Codable 以便持久化）
struct GeofenceEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var radius: Double = 100.0
    /// 进入时切换的卡槽（逻辑卡位 0..<16）
    var slotIndex: Int
    /// 离开时切换的卡槽（可选）
    var fallbackSlotIndex: Int?

    var region: CLCircularRegion? {
        let r = CLCircularRegion(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                 radius: radius,
                                 identifier: id.uuidString)
        r.notifyOnEntry = true
        r.notifyOnExit = fallbackSlotIndex != nil
        return r
    }

    /// 是否为电子围栏场景中的"实验室"预设（UI 展示用）
    var isPreset: Bool { name.hasPrefix("预设") }
}
