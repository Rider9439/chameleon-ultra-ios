import Foundation

/// 变色龙 Ultra BLE 二进制帧协议
/// 帧 = SOF(0x11) | LRC1 | CMD[U16BE] | STATUS[U16BE] | LEN[U16BE] | LRC2 | DATA[LEN] | LRC3
/// LRC = (0x100 - (Σbytes & 0xFF)) & 0xFF
/// LRC1 = LRC([SOF]) ；LRC2 = LRC([CMD,STATUS,LEN]) ；LRC3 = LRC(整帧已发部分)
enum ChameleonFrame {
    static let sof: UInt8 = 0x11
    static let maxDataLength = 4096

    static func lrc(_ bytes: [UInt8]) -> UInt8 {
        var sum: UInt8 = 0
        for b in bytes { sum = sum &+ b }
        return UInt8((0x100 - Int(sum)) & 0xFF)
    }

    /// 构造一帧
    static func makeFrame(command: UInt16, status: UInt16, data: [UInt8]?) -> [UInt8] {
        var frame: [UInt8] = []
        frame.append(sof)
        frame.append(lrc([sof]))
        frame.append(contentsOf: UInt16(command).beBytes)
        frame.append(contentsOf: UInt16(status).beBytes)
        frame.append(contentsOf: UInt16(data?.count ?? 0).beBytes)
        frame.append(lrc(Array(frame[2..<8])))
        if let data, !data.isEmpty {
            frame.append(contentsOf: data)
        }
        frame.append(lrc(frame))
        return frame
    }

    /// 完整帧解析（严格校验 LRC，返回 nil 表示无效）
    static func parse(_ bytes: [UInt8]) -> (command: UInt16, status: UInt16, data: [UInt8])? {
        guard bytes.count >= 9 else { return nil }
        guard bytes[0] == sof else { return nil }
        guard bytes[1] == lrc([bytes[0]]) else { return nil }
        guard bytes[8] == lrc(Array(bytes[2..<8])) else { return nil }
        let len = Int(bytes[6]) << 8 | Int(bytes[7])
        guard len <= maxDataLength else { return nil }
        guard bytes.count == 9 + len + 1 else { return nil }
        guard bytes[9 + len] == lrc(Array(bytes[0..<(9 + len)])) else { return nil }
        let command = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        let status = UInt16(bytes[4]) << 8 | UInt16(bytes[5])
        let data = Array(bytes[9..<(9 + len)])
        return (command, status, data)
    }
}

/// 状态码（对齐 app_status.h）
enum ChameleonStatus {
    static let hfOk: UInt16 = 0x00          // HF 操作正常
    static let mfAuthError: UInt16 = 0x06   // Mifare 认证失败
    static let lfOk: UInt16 = 0x40          // LF 操作正常
    static let lfNoTag: UInt16 = 0x41       // LF 无卡
    static let generalSuccess: UInt16 = 0x68 // 一般成功（嗅探等）
    static let invalidSlotType: UInt16 = 0x72 // 无效槽类型
}

// MARK: - 字节工具

extension UInt16 {
    var beBytes: [UInt8] { [UInt8(self >> 8 & 0xFF), UInt8(self & 0xFF)] }
    init(beBytes b: [UInt8]) { self = UInt16(b[0]) << 8 | UInt16(b[1]) }
}

extension UInt32 {
    var beBytes: [UInt8] { [UInt8(self >> 24 & 0xFF), UInt8(self >> 16 & 0xFF), UInt8(self >> 8 & 0xFF), UInt8(self & 0xFF)] }
    init(beBytes b: [UInt8]) { self = UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]) }
}

extension UInt64 {
    var beBytes: [UInt8] {
        var r: [UInt8] = []
        for i in stride(from: 56, through: 0, by: -8) { r.append(UInt8((self >> UInt64(i)) & 0xFF)) }
        return r
    }
}

extension Array where Element == UInt8 {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
    var hexSpaced: String { map { String(format: "%02x", $0) }.joined(separator: " ") }
    var u16BE: UInt16 { UInt16(beBytes: Array(self.prefix(2))) }
    var u32BE: UInt32 { UInt32(beBytes: Array(self.prefix(4))) }
    var u64BE: UInt64 {
        var v: UInt64 = 0
        for b in prefix(8) { v = (v << 8) | UInt64(b) }
        return v
    }
}
