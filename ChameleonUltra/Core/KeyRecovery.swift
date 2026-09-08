import Foundation

/// Mifare Classic 密钥恢复（mfkey32 / mfkey64 / nested / darkside）
/// 算法与 pm3 tools/mfc/card_reader/*.c 及 client/src/mifare/mfkey.c 一致，
/// 底层原语（recovery/rollback/prng/crypto1）已用官方参考代码逐项验证。
enum KeyRecovery {

    /// mfkey32：两个不同 nonce 的两次认证应答恢复密钥
    /// - Parameters:
    ///   - uid: 卡片 UID
    ///   - nt0, nt1: 两次认证的标签挑战（已知明文）
    ///   - nr0Enc, ar0Enc: 第一次认证的加密读器挑战/应答
    ///   - nr1Enc, ar1Enc: 第二次认证的加密读器挑战/应答
    /// - Returns: 48 位密钥（UInt64 低 48 位有效）；失败返回 nil
    static func mfkey32(uid: UInt32, nt0: UInt32, nr0Enc: UInt32, ar0Enc: UInt32,
                        nt1: UInt32, nr1Enc: UInt32, ar1Enc: UInt32) -> UInt64? {
        let p64 = Crypto1.prngSuccessor(nt0, 64)
        let p64b = Crypto1.prngSuccessor(nt1, 64)
        let states = LfsrRecovery.recovery32(ks2: ar0Enc ^ p64, in: 0)

        for var state in states {
            _ = LfsrRecovery.rollbackWord(&state, inWord: 0, fb: 0)
            _ = LfsrRecovery.rollbackWord(&state, inWord: nr0Enc, fb: 1)
            _ = LfsrRecovery.rollbackWord(&state, inWord: uid ^ nt0, fb: 0)
            let key = Crypto1.getLFSR(state)

            // 用第二段会话验证
            var cs = Crypto1.initState(key)
            _ = Crypto1.wordForward(&cs, inWord: uid ^ nt1, isEncrypted: 0)
            _ = Crypto1.wordForward(&cs, inWord: nr1Enc, isEncrypted: 1)
            let check = Crypto1.wordForward(&cs, inWord: 0, isEncrypted: 0)
            if check ^ p64b == ar1Enc {
                return key
            }
        }
        return nil
    }

    /// mfkey64：单次完整认证（含标签应答 {at}）恢复密钥
    /// - Parameters:
    ///   - uid: 卡片 UID
    ///   - nt: 标签挑战（已知明文）
    ///   - nrEnc: 加密读器挑战
    ///   - arEnc: 加密读器应答
    ///   - atEnc: 加密标签应答
    static func mfkey64(uid: UInt32, nt: UInt32, nrEnc: UInt32, arEnc: UInt32, atEnc: UInt32) -> UInt64? {
        let p64 = Crypto1.prngSuccessor(nt, 64)
        let ks2 = arEnc ^ p64
        let ks3 = atEnc ^ Crypto1.prngSuccessor(p64, 32)

        let states = LfsrRecovery.recovery64(ks2: ks2, ks3: ks3)
        guard !states.isEmpty else { return nil }

        var state = states[0]
        if state.odd == 0 && state.even == 0 { return nil }
        _ = LfsrRecovery.rollbackWord(&state, inWord: 0, fb: 0)
        _ = LfsrRecovery.rollbackWord(&state, inWord: 0, fb: 0)
        _ = LfsrRecovery.rollbackWord(&state, inWord: nrEnc, fb: 1)
        _ = LfsrRecovery.rollbackWord(&state, inWord: uid ^ nt, fb: 0)
        let key = Crypto1.getLFSR(state)

        // 校验：用密钥重放认证并比对 ar
        var cs = Crypto1.initState(key)
        _ = Crypto1.wordForward(&cs, inWord: uid ^ nt, isEncrypted: 0)
        _ = Crypto1.wordForward(&cs, inWord: nrEnc, isEncrypted: 1)
        let check = Crypto1.wordForward(&cs, inWord: 0, isEncrypted: 0)
        if check == ks2 {
            return key
        }
        return nil
    }

    /// nested：已知密钥会话 + 目标会话（可仅知 nt 的高 16 位）恢复目标密钥
    /// - Parameters:
    ///   - uid: 卡片 UID
    ///   - nt: 目标会话的标签挑战（完整 32 位，弱 nonce 可由高 16 位重建）
    ///   - ntEnc: 目标会话的加密标签挑战
    ///   - nrEnc: 目标会话的加密读器挑战（固件未采集时传 0，跳过校验）
    ///   - arEnc: 目标会话的加密读器应答（固件未采集时传 0，跳过校验）
    static func nested(uid: UInt32, nt: UInt32, ntEnc: UInt32, nrEnc: UInt32, arEnc: UInt32) -> UInt64? {
        // 标准 nested 攻击（pm3 mfkey32nested）：
        // {nt} = ks1 ^ nt → ks1 = ntEnc ^ nt；ar 明文 = prng64(nt) → ar 密钥流 ks2 = arEnc ^ ar
        let ks0 = ntEnc ^ nt
        let ks2 = arEnc ^ Crypto1.prngSuccessor(nt, 64)
        // recovery32(ks1, in=uid^nt) 恢复出「{nt} 加密之后、nr 加密之前」的 LFSR 状态
        let states = LfsrRecovery.recovery32(ks2: ks0, in: uid ^ nt)
        for var state in states {
            // 前向：nr 词（fb=1，输入密文自解密）→ ar 词密钥流比对
            _ = Crypto1.wordForward(&state, inWord: nrEnc, isEncrypted: 1)
            guard Crypto1.wordForward(&state, inWord: 0, isEncrypted: 0) == ks2 else { continue }
            // 回滚 ar / nr / uid^nt 三个词回到初始状态即密钥
            _ = LfsrRecovery.rollbackWord(&state, inWord: 0, fb: 0)
            _ = LfsrRecovery.rollbackWord(&state, inWord: nrEnc, fb: 1)
            _ = LfsrRecovery.rollbackWord(&state, inWord: uid ^ nt, fb: 0)
            return Crypto1.getLFSR(state)
        }
        return nil
    }

    /// darkside：一次认证（含 {nt} 奇偶校验位）恢复密钥
    /// - Parameters:
    ///   - uid: 卡片 UID
    ///   - nt: 标签挑战（弱 nonce）
    ///   - nr: 读器挑战（darkside 中 nr 低 3 位被重置为 0）
    ///   - ar: 读器应答
    ///   - par: 32 位奇偶校验位（{nt} 每字节的校验位，按非零字节聚合）
    ///   - ks: 32 位密钥流（加密 NACK 的密钥流，每字节取低 4 位）
    /// - Returns: 候选密钥列表
    static func darkside(uid: UInt32, nt: UInt32, nr: UInt32, ar: UInt32, par: UInt64, ks: UInt64) -> [UInt64] {
        let nrFixed = nr & 0xFFFFFF1F

        var ks3x = [UInt8](repeating: 0, count: 8)
        var parMatrix = [[UInt8]](repeating: [UInt8](repeating: 0, count: 8), count: 8)
        for pos in 0..<8 {
            ks3x[7 - pos] = UInt8((ks >> (pos * 8)) & 0x0F)
            let bt = UInt8((par >> (pos * 8)) & 0xFF)
            for b in 0..<8 {
                parMatrix[7 - pos][b] = (bt >> b) & 1
            }
        }

        let states = LfsrRecovery.lfsrCommonPrefix(pfx: nrFixed, rr: ar, ks: ks3x, par: parMatrix, noPar: par == 0)

        var keys: [UInt64] = []
        for state in states {
            if state.odd == 0 && state.even == 0 { continue }
            var st = state
            _ = LfsrRecovery.rollbackWord(&st, inWord: uid ^ nt, fb: 0)
            keys.append(Crypto1.getLFSR(st))
        }
        return keys
    }
}
