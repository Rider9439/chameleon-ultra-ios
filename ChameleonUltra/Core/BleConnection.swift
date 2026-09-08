import Foundation
import CoreBluetooth
import Combine

/// BLE 连接层（Nordic UART 服务，已按官方 GUI 源码逐字核对 UUID）
final class BleConnection: NSObject, ObservableObject {
    // Nordic UART（官方 GUI serial_ble.dart 确认）
    static let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let writeUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    static let notifyUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    // DFU 服务（仅扫描过滤辅助）
    static let dfuUUID = CBUUID(string: "FE59")

    @Published var isScanning = false
    @Published var discoveredPeripherals: [(peripheral: CBPeripheral, rssi: Int)] = []
    @Published var connectedPeripheral: CBPeripheral?
    @Published var isConnected = false
    @Published var lastError: String?

    private var manager: CBCentralManager!
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    /// 串行命令管线
    private let pipeline = DispatchQueue(label: "com.chameleon.ble.pipeline")
    private var pendingContinuation: CheckedContinuation<ChameleonResponse?, Never>?
    private var pendingCommand: UInt16?
    private var pendingTimeoutWork: DispatchWorkItem?

    private var rxBuffer: [UInt8] = []

    override init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - 扫描 / 连接

    func startScan() {
        guard manager.state == .poweredOn else {
            lastError = "蓝牙未开启"
            return
        }
        isScanning = true
        discoveredPeripherals = []
        manager.scanForPeripherals(withServices: [Self.serviceUUID, Self.dfuUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        isScanning = false
        manager.stopScan()
    }

    func connect(_ peripheral: CBPeripheral) {
        stopScan()
        manager.connect(peripheral, options: nil)
    }

    func disconnect() {
        if let p = connectedPeripheral {
            manager.cancelPeripheralConnection(p)
        }
    }

    // MARK: - 发送

    /// 发送命令并等待响应（串行、带超时）。响应为 nil 表示超时。
    func send(_ cmd: ChameleonCmd, data: [UInt8]? = nil, timeout: TimeInterval = 10) async -> ChameleonResponse? {
        await withCheckedContinuation { continuation in
            pipeline.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                self.pendingContinuation = continuation
                self.pendingCommand = cmd.rawValue

                let frame = ChameleonFrame.makeFrame(command: cmd.rawValue, status: 0, data: data)
                guard let characteristic = self.writeCharacteristic, let peripheral = self.connectedPeripheral else {
                    self.failPending(nil)
                    return
                }
                // 分包发送（每包 ≤ 160 字节，withResponse）
                let chunk = 160
                var i = 0
                while i < frame.count {
                    let end = min(i + chunk, frame.count)
                    let part = Data(frame[i..<end])
                    peripheral.writeValue(part, for: characteristic, type: .withResponse)
                    i = end
                }

                let work = DispatchWorkItem { [weak self] in
                    self?.failPending(nil)
                }
                self.pendingTimeoutWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
            }
        }
    }

    /// 发送但不等响应（如进入 Bootloader）
    func sendNoResponse(_ cmd: ChameleonCmd, data: [UInt8]? = nil) {
        pipeline.async { [weak self] in
            guard let self, let characteristic = self.writeCharacteristic, let peripheral = self.connectedPeripheral else { return }
            let frame = ChameleonFrame.makeFrame(command: cmd.rawValue, status: 0, data: data)
            let chunk = 160
            var i = 0
            while i < frame.count {
                let end = min(i + chunk, frame.count)
                peripheral.writeValue(Data(frame[i..<end]), for: characteristic, type: .withResponse)
                i = end
            }
        }
    }

    private func failPending(_ response: ChameleonResponse?) {
        pendingTimeoutWork?.cancel()
        pendingTimeoutWork = nil
        pendingCommand = nil
        pendingContinuation?.resume(returning: response)
        pendingContinuation = nil
    }

    /// 清空接收缓冲（切换设备时）
    func resetRx() {
        rxBuffer = []
    }
}

extension BleConnection: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            lastError = nil
        case .poweredOff:
            lastError = "蓝牙已关闭"
            isConnected = false
        case .unauthorized:
            lastError = "未获得蓝牙权限"
        case .unsupported:
            lastError = "设备不支持蓝牙"
        default:
            lastError = "蓝牙状态异常"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if !discoveredPeripherals.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
            discoveredPeripherals.append((peripheral, RSSI.intValue))
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        isConnected = true
        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral.identifier == connectedPeripheral?.identifier {
            connectedPeripheral = nil
            isConnected = false
            writeCharacteristic = nil
            notifyCharacteristic = nil
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        lastError = "连接失败：\(error?.localizedDescription ?? "未知错误")"
        isConnected = false
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics([Self.writeUUID, Self.notifyUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for c in chars {
            if c.uuid == Self.writeUUID { writeCharacteristic = c }
            if c.uuid == Self.notifyUUID {
                notifyCharacteristic = c
                peripheral.setNotifyValue(true, for: c)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.notifyUUID, let value = characteristic.value else { return }
        rxBuffer.append(contentsOf: value)

        // 组帧解析：尝试按当前缓冲取完整帧
        while let parsed = tryConsumeFrame() {
            let resp = ChameleonResponse(command: parsed.command, status: parsed.status, data: parsed.data)
            if let cmd = pendingCommand, cmd == resp.command {
                failPending(resp)
            }
            // 命令不匹配的帧丢弃（可能是后台通知）
        }
    }

    /// 从缓冲中消费一个完整帧；不完整则返回 nil 等待更多数据
    private func tryConsumeFrame() -> (command: UInt16, status: UInt16, data: [UInt8])? {
        guard rxBuffer.count >= 9 else { return nil }
        guard rxBuffer[0] == ChameleonFrame.sof else {
            // 失步：滑窗找 SOF
            if let idx = rxBuffer.firstIndex(of: ChameleonFrame.sof), idx > 0 {
                rxBuffer.removeFirst(idx)
                return tryConsumeFrame()
            }
            rxBuffer.removeAll()
            return nil
        }
        let len = Int(rxBuffer[6]) << 8 | Int(rxBuffer[7])
        guard len <= ChameleonFrame.maxDataLength else {
            rxBuffer.removeAll()
            return nil
        }
        let total = 9 + len + 1
        guard rxBuffer.count >= total else { return nil }
        let frame = Array(rxBuffer.prefix(total))
        rxBuffer.removeFirst(total)
        guard let parsed = ChameleonFrame.parse(frame) else {
            // LRC 校验失败：丢弃整帧
            return tryConsumeFrame()
        }
        return parsed
    }
}

/// 命令响应
struct ChameleonResponse {
    let command: UInt16
    let status: UInt16
    let data: [UInt8]
}
