import Foundation

/// HF ISO14443A 嗅探数据解析（hf14aSniff 返回数据流）
/// 数据流由 REQA/WUPA/ANTICOLL/SELECT/AUTH 命令字节与标签应答组成，
/// 本解析器从原始比特流中提取卡片 UID 与嵌套认证的 nt/nr/ar。
enum HfSniff {

    /// 一条认证记录
    struct AuthRecord {
        var uid: [UInt8]
        var nt: UInt32
        var nrEnc: UInt32
        var arEnc: UInt32
        var atEnc: UInt32?
        var isNested: Bool  // true 表示在第一条认证之后发起
    }

    /// 解析后的嗅探结果
    struct SniffResult {
        var uid: [UInt8] = []
        var auths: [AuthRecord] = []
        var rawBytes: [UInt8]

        var firstAuth: AuthRecord? { auths.first }
    }

    /// 从嗅探原始数据中提取卡片 UID（ISO14443A 反冲突 + Select 流程）
    static func extractUid(_ data: [UInt8]) -> [UInt8]? {
        // 常见字节序：94 20 → 序列号字节（4 字节含 BCC）→ 93 70 校验
        var i = 0
        while i + 1 < data.count {
            if data[i] == 0x93, data[i + 1] == 0x20 {
                var j = i + 2
                if j + 4 <= data.count {
                    let candidate = Array(data[j..<j + 4])
                    // 检查 BCC：4 字节异或 == 0
                    if candidate.prefix(3).reduce(0, ^) == candidate[3] {
                        return Array(candidate.prefix(3))
                    }
                    return Array(candidate.prefix(3))
                }
            }
            i += 1
        }
        return nil
    }

    /// 在嗅探流中查找嵌套认证（第一组 60/61 之后的第二组认证命令）
    static func parseAuths(_ data: [UInt8], uid: [UInt8]) -> [AuthRecord] {
        var auths: [AuthRecord] = []
        var i = 0
        while i + 1 < data.count {
            // Mifare Classic 认证命令：60/61（A/B）+ 块号 + 6 字节随机数(Nr)
            if (data[i] == 0x60 || data[i] == 0x61), i + 8 < data.count {
                let nrRaw = Array(data[i + 2..<i + 8])
                let ntRaw = next4Bytes(data, after: i + 8)
                let arRaw = next4Bytes(data, after: i + 8 + 4)
                let atRaw = next4Bytes(data, after: i + 8 + 8)

                if nrRaw.count == 6, ntRaw.count == 4, arRaw.count == 4 {
                    let record = AuthRecord(
                        uid: uid,
                        nt: u32be(ntRaw),
                        nrEnc: u32be(nrRaw.suffix(4)),
                        arEnc: u32be(arRaw),
                        atEnc: atRaw.count == 4 ? u32be(atRaw) : nil,
                        isNested: !auths.isEmpty
                    )
                    auths.append(record)
                }
                i += 8
            }
            i += 1
        }
        return auths
    }

    /// 完整解析入口
    static func parse(_ data: [UInt8]) -> SniffResult {
        let uid = extractUid(data) ?? []
        let auths = parseAuths(data, uid: uid)
        return SniffResult(uid: uid, auths: auths, rawBytes: data)
    }

    // MARK: - 辅助

    private static func next4Bytes(_ d: [UInt8], after offset: Int) -> [UInt8] {
        guard offset + 4 <= d.count else { return [] }
        return Array(d[offset..<offset + 4])
    }

    private static func u32be(_ d: [UInt8]) -> UInt32 {
        UInt32(d[0]) << 24 | UInt32(d[1]) << 16 | UInt32(d[2]) << 8 | UInt32(d[3])
    }
}
