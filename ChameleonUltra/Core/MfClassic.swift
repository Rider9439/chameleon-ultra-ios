import Foundation

/// Mifare Classic 存储布局（1K/4K）与值块编解码
enum MfClassic {

    /// 扇区起始块号（1K 卡每扇区 4 块；4K 卡扇区 32-39 每扇区 16 块）
    static func firstBlock(ofSector sector: Int) -> Int {
        if sector < 32 { return sector * 4 }
        return 128 + (sector - 32) * 16
    }

    /// 扇区包含的块数
    static func blockCount(ofSector sector: Int) -> Int {
        sector < 32 ? 4 : 16
    }

    /// 块所属扇区
    static func sector(ofBlock block: Int) -> Int {
        if block < 128 { return block / 4 }
        return 32 + (block - 128) / 16
    }

    /// 扇区尾块（存放密钥 A/访问位/密钥 B）
    static func isTrailer(block: Int) -> Bool {
        if block < 128 { return block % 4 == 3 }
        return (block - 128) % 16 == 15
    }

    /// 数据块（非尾块）
    static func isDataBlock(block: Int) -> Bool { !isTrailer(block: block) }

    /// 1K 卡块总数
    static let totalBlocks1K = 64

    /// 4K 卡块总数
    static let totalBlocks4K = 256

    // MARK: - 值块（ManipulateValueBlock 语义）

    /// 校验值块是否合法：值两次正码一次反码、地址三次一致
    static func isValidValueBlock(_ data: [UInt8]) -> Bool {
        guard data.count == 16 else { return false }
        let v0 = u32(data, 0)
        let v1 = u32(data, 4)
        let v2 = u32(data, 8)
        let inv = ~v0 & 0xFFFFFFFF
        let addr = data[12]
        let addrInv = data[13]
        return v0 == v2 && v1 == inv && addr == data[14] && addrInv == data[15] && addrInv == addr ^ 0xFF
    }

    /// 读取值块中的数值
    static func valueBlockValue(_ data: [UInt8]) -> Int32? {
        guard isValidValueBlock(data) else { return nil }
        return Int32(bitPattern: u32(data, 0))
    }

    /// 构造值块（Mifare 标准布局：v | ~v | v | addr | ~addr | addr | ~addr）
    static func makeValueBlock(value: Int32, address: UInt8) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 16)
        let v = UInt32(bitPattern: value)
        let inv = ~v
        out.replaceSubrange(0..<4, with: v.beBytes)
        out.replaceSubrange(4..<8, with: inv.beBytes)
        out.replaceSubrange(8..<12, with: v.beBytes)
        out[12] = address
        out[13] = address ^ 0xFF
        out[14] = address
        out[15] = address ^ 0xFF
        return out
    }

    /// 值块加法（加减操作）
    static func addToValueBlock(_ data: [UInt8], delta: Int32) -> [UInt8]? {
        guard let v = valueBlockValue(data) else { return nil }
        let addr = data[12]
        return makeValueBlock(value: v + delta, address: addr)
    }

    private static func u32(_ d: [UInt8], _ off: Int) -> UInt32 {
        UInt32(d[off]) << 24 | UInt32(d[off + 1]) << 16 | UInt32(d[off + 2]) << 8 | UInt32(d[off + 3])
    }
}
