import Foundation
import CoreBluetooth

/// 逻辑卡位（App 恒展示 32 卡位 = 16 IC + 16 ID）
struct LogicalSlot: Identifiable, Equatable {
    enum Bank: String, CaseIterable, Identifiable {
        case ic = "IC"
        case id = "ID"
        var id: String { rawValue }
        var displayName: String { rawValue }
    }

    var bank: Bank
    var number: Int          // 0..<16
    var physicalSlot: Int    // number % slotCount（与固件槽数映射）
    var available: Bool      // number < slotCount

    var id: String { "\(bank.rawValue)-\(number)" }
    var displayName: String { "\(bank.rawValue)卡位 \(number + 1)" }
}

/// 固件探测结果
struct DeviceCapabilities {
    var slotCount = 8                 // 官方固件 8 槽；轮询版/大龙版 16 槽
    var modelName = "ChameleonUltra"
    var firmwareVersion = "unknown"
    var batteryPercent: Int? = nil
    var supportsGen1a = false
    var supportsGen2 = false
    var supportsNtag = false
}

/// 设备层：BLE 连接 + 协议命令 + 槽映射 + 卡数据读写
/// 所有命令均经 BleConnection 串行管线发送，返回帧解析结果。
@MainActor
final class ChameleonDevice: ObservableObject {

    // MARK: - 状态

    @Published var capabilities = DeviceCapabilities()
    @Published var activeSlot = 0
    @Published var enabledSlots: [Bool] = []      // 物理槽索引 → 是否启用
    @Published var slotTypes: [TagType] = []
    @Published var slotNicks: [String] = []
    @Published var lastError: String?
    @Published var batteryLevel: Int?
    @Published var firmwareVersion: String?
    @Published var deviceModel: String?
    @Published var connectionState = "未连接"

    let ble = BleConnection()

    // MARK: - 逻辑卡位

    /// 恒 32 逻辑卡位（16 IC + 16 ID）
    var logicalSlots: [LogicalSlot] {
        let count = capabilities.slotCount
        var out: [LogicalSlot] = []
        for n in 0..<16 {
            out.append(LogicalSlot(bank: .ic, number: n, physicalSlot: n % count, available: n < count))
        }
        for n in 0..<16 {
            out.append(LogicalSlot(bank: .id, number: n, physicalSlot: n % count, available: n < count))
        }
        return out
    }

    // MARK: - 连接

    func startScan() {
        connectionState = "扫描中…"
        ble.startScan()
    }

    func connect(_ peripheral: CBPeripheral) async {
        connectionState = "连接中…"
        await ble.connect(peripheral)
        if ble.isConnected {
            connectionState = "已连接"
            _ = await probeDevice()
        } else {
            connectionState = "连接失败"
        }
    }

    func disconnect() {
        ble.disconnect()
        connectionState = "未连接"
    }

    // MARK: - 设备探测

    /// 探测设备型号/能力/槽数
    func probeDevice() async -> Bool {
        guard ble.isConnected else { return false }

        if let r = await ble.send(.getDeviceType) {
            deviceModel = String(bytes: r.data, encoding: .utf8) ?? "未知"
            capabilities.modelName = deviceModel ?? "ChameleonUltra"
        }
        if let r = await ble.send(.getGitVersion) {
            firmwareVersion = String(bytes: r.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            capabilities.firmwareVersion = firmwareVersion ?? "unknown"
        }
        if let r = await ble.send(.getDeviceCapabilities) {
            parseCapabilities(r.data)
        }
        if let r = await ble.send(.getBatteryCharge), r.data.count >= 3 {
            let v = (UInt16(r.data[0]) << 8) | UInt16(r.data[1])
            let pct = Int(r.data[2])
            batteryLevel = pct
            capabilities.batteryPercent = pct
            _ = v
        }
        _ = await refreshSlots()
        return true
    }

    private func parseCapabilities(_ data: [UInt8]) {
        // 常见固件返回位图：第 0 字节含槽数/双频位
        if data.count >= 1 {
            let b0 = data[0]
            if b0 & 0x02 != 0 || data.count >= 2 && data[1] & 0x02 != 0 {
                capabilities.slotCount = 16
            }
        }
        if data.count >= 1 {
            capabilities.supportsGen1a = data[0] & 0x04 != 0
            capabilities.supportsGen2 = data[0] & 0x08 != 0
        }
        if data.count >= 2 {
            capabilities.supportsNtag = data[1] & 0x01 != 0
        }
    }

    // MARK: - 卡槽管理（32 逻辑卡位 → 物理槽）

    /// 刷新槽信息与启用状态
    func refreshSlots() async -> Bool {
        guard ble.isConnected else { return false }
        let count = capabilities.slotCount

        var enabled = [Bool](repeating: false, count: count)
        var types = [TagType](repeating: .unknown, count: count)
        var nicks = [String](repeating: "", count: count)

        if let r = await ble.send(.getEnabledSlots) {
            // 8 槽 → 16 字节；16 槽 → 32 字节
            let per = r.data.count / count
            for i in 0..<min(count, r.data.count / max(1, per)) {
                if per >= 2 {
                    enabled[i] = (r.data[i * per] != 0) || (r.data[i * per + 1] != 0)
                } else if per == 1 {
                    enabled[i] = r.data[i] != 0
                }
            }
        }
        if let r = await ble.send(.getSlotInfo) {
            // 每槽 4 字节：hf[2] | lf[2]
            for i in 0..<min(count, r.data.count / 4) {
                let hf = (UInt16(r.data[i * 4]) << 8) | UInt16(r.data[i * 4 + 1])
                let lf = (UInt16(r.data[i * 4 + 2]) << 8) | UInt16(r.data[i * 4 + 3])
                if hf != 0 { types[i] = TagType(rawValue: hf) ?? .unknown }
                if enabled[i] == false, hf != 0 || lf != 0 { enabled[i] = true }
            }
        }
        if let r = await ble.send(.getAllSlotNicks) {
            parseNicks(r.data, into: &nicks, slotCount: count)
        }
        if let r = await ble.send(.getActiveSlot), !r.data.isEmpty {
            activeSlot = Int(r.data[0])
        }

        enabledSlots = enabled
        slotTypes = types
        slotNicks = nicks
        return true
    }

    private func parseNicks(_ data: [UInt8], into nicks: inout [String], slotCount: Int) {
        var i = 0
        var slot = 0
        while i + 2 <= data.count && slot < slotCount {
            let hfLen = Int(data[i])
            let hfData = i + 1 + hfLen <= data.count ? Array(data[i + 1..<i + 1 + hfLen]) : []
            let lfLenStart = i + 1 + hfLen
            guard lfLenStart < data.count else { break }
            let lfLen = Int(data[lfLenStart])
            let lfData = lfLenStart + 1 + lfLen <= data.count ? Array(data[lfLenStart + 1..<lfLenStart + 1 + lfLen]) : []
            if let s = String(bytes: hfData, encoding: .utf8), !s.isEmpty { nicks[slot] = s }
            else if let s = String(bytes: lfData, encoding: .utf8), !s.isEmpty { nicks[slot] = s }
            i = lfLenStart + 1 + lfLen
            slot += 1
        }
    }

    /// 激活逻辑卡位（bank + number → 物理槽；对可用性做校验）
    func activateSlot(bank: LogicalSlot.Bank, number: Int) async -> Bool {
        let slot = number % capabilities.slotCount
        let ok = await ble.send(.setActiveSlot, data: Payload.setActiveSlot(slot))
        if ok?.status == 0x00 || ok?.status == 0x68 {
            activeSlot = slot
            return true
        }
        lastError = "激活失败: status=\(ok?.status ?? 0xFF)"
        return false
    }

    /// 设置逻辑卡位频率类型（IC → HF / ID → LF）
    func setSlotType(bank: LogicalSlot.Bank, number: Int, type: TagType) async -> Bool {
        let slot = number % capabilities.slotCount
        let r = await ble.send(.setSlotTagType, data: Payload.setSlotTagType(slot: slot, type: type))
        if r?.status == 0x00 || r?.status == 0x68 {
            slotTypes[slot] = type
            return true
        }
        lastError = "设置卡类型失败"
        return false
    }

    /// 启用/停用物理槽的 HF/LF 面
    func setSlotEnable(physicalSlot: Int, frequency: TagFrequency, enable: Bool) async -> Bool {
        let r = await ble.send(.setSlotEnable, data: Payload.setSlotEnable(slot: physicalSlot, frequency: frequency, enable: enable))
        return r?.status == 0x00 || r?.status == 0x68
    }

    func setSlotNick(physicalSlot: Int, frequency: TagFrequency, name: String) async -> Bool {
        let r = await ble.send(.setSlotTagNick, data: Payload.setSlotTagNick(index: physicalSlot, frequency: frequency, name: name))
        return r?.status == 0x00 || r?.status == 0x68
    }

    func saveSlotNicks() async -> Bool {
        let r = await ble.send(.saveSlotNicks)
        return r?.status == 0x00 || r?.status == 0x68
    }

    // MARK: - 卡片读写（IC：Mifare Classic）

    /// 扫描 14A 卡片
    func scan14A() async -> (uid: [UInt8], atqa: [UInt8], sak: UInt8)? {
        guard let r = await ble.send(.scan14ATag, data: []) else { return nil }
        guard r.status == 0x00, r.data.count >= 5 else {
            lastError = r.status == 0x01 ? "未发现卡片" : "扫描失败"
            return nil
        }
        let uidLen = Int(r.data[0])
        let uid = Array(r.data[1..<min(1 + uidLen, r.data.count)])
        var atqa: [UInt8] = []
        var sak: UInt8 = 0
        if 1 + uidLen + 2 <= r.data.count {
            atqa = Array(r.data[1 + uidLen..<1 + uidLen + 2])
        }
        if 1 + uidLen + 2 < r.data.count {
            sak = r.data[1 + uidLen + 2]
        }
        return (uid, atqa, sak)
    }

    /// 尝试认证并读取块数据
    func readBlock(block: Int, keyType: UInt8, key: [UInt8]) async -> (data: [UInt8], ok: Bool) {
        guard let r = await ble.send(.mf1ReadBlock, data: Payload.mf1CheckKey(block: block, keyType: keyType, key: key)) else {
            return ([], false)
        }
        if r.status == 0x00 || r.status == 0x68 {
            return (r.data, true)
        }
        lastError = "读块失败 status=\(r.status)"
        return ([], false)
    }

    /// 写块
    func writeBlock(block: Int, keyType: UInt8, key: [UInt8], data: [UInt8]) async -> Bool {
        var payload = Payload.mf1CheckKey(block: block, keyType: keyType, key: key)
        var padded = data
        while padded.count < 16 { padded.append(0) }
        payload.append(contentsOf: padded.prefix(16))
        let r = await ble.send(.mf1WriteBlock, data: payload)
        return r?.status == 0x00 || r?.status == 0x68
    }

    /// 扫描 EM410X（ID 卡）
    func scanEM410X() async -> (uid: [UInt8], ok: Bool) {
        guard let r = await ble.send(.scanEM410Xtag, data: []) else { return ([], false) }
        if r.status == 0x40 || r.status == 0x68 {
            return (r.data, true)
        }
        lastError = r.status == 0x41 ? "未发现 ID 卡" : "扫描失败"
        return ([], false)
    }

    /// 写入 T5577（EM410X 等 LF 卡克隆）
    func writeEM410XToT5577(uid: [UInt8]) async -> Bool {
        let r = await ble.send(.writeEM410XtoT5577, data: uid)
        return r?.status == 0x40 || r?.status == 0x68
    }

    // MARK: - 嗅探

    func startHfSniff(timeoutMs: UInt16) async -> (data: [UInt8], ok: Bool) {
        let payload = [UInt8(timeoutMs >> 8), UInt8(timeoutMs & 0xFF)]
        let r = await ble.send(.hf14aSniff, data: payload, timeout: Double(timeoutMs) / 1000.0 + 5)
        if r?.status == 0x68 || r?.status == 0x00 {
            return (r?.data ?? [], true)
        }
        return ([], false)
    }

    func startLfSniff(timeoutMs: UInt16) async -> (data: [UInt8], ok: Bool) {
        let payload = [UInt8(timeoutMs >> 8), UInt8(timeoutMs & 0xFF)]
        let r = await ble.send(.lfSniff, data: payload, timeout: Double(timeoutMs) / 1000.0 + 5)
        if r?.status == 0x40 || r?.status == 0x68 {
            return (r?.data ?? [], true)
        }
        return ([], false)
    }
}
