import Foundation

/// Crypto1 流密码核心（Mifare Classic 认证流密码）
/// 移植自 proxmark3 主线 common/crapto1/crypto1.c，全部位运算约定已用官方参考代码逐项验证。
struct Crypto1State: Equatable {
    var odd: UInt32 = 0
    var even: UInt32 = 0
}

enum Crypto1 {
    /// LF 多项式（crapto1.h LF_POLY_ODD / LF_POLY_EVEN）
    static let lfPolyOdd: UInt32 = 0x29CE5C
    static let lfPolyEven: UInt32 = 0x870804

    // MARK: - 位工具

    /// BIT(x, n)
    static func bit(_ x: UInt32, _ n: Int) -> UInt32 { (x >> n) & 1 }
    /// BEBIT(x, n) = BIT(x, n ^ 24)
    static func beBit(_ x: UInt32, _ n: Int) -> UInt32 { bit(x, n ^ 24) }

    /// 偶校验（evenparity32，32 位整体校验）
    static func evenParity32(_ x: UInt32) -> UInt32 {
        var v = x
        v ^= v >> 16; v ^= v >> 8; v ^= v >> 4; v ^= v >> 2; v ^= v >> 1
        return v & 1
    }

    /// 奇校验（8 位）
    static func oddParity8(_ x: UInt8) -> UInt8 {
        UInt8(evenParity32(UInt32(x)) ^ 1)
    }

    // MARK: - 滤波函数

    /// filter(x)（对照 crapto1.h filterlut 构建式，含末尾 0xEC57E80A 查表）
    static func filter(_ x: UInt32) -> UInt8 {
        var f: UInt32 = 0
        f |= (0xf22c0 >> (x & 0xf)) & 16
        f |= (0x6c9c0 >> ((x >> 4) & 0xf)) & 8
        f |= (0x3c8b0 >> ((x >> 8) & 0xf)) & 4
        f |= (0x1e458 >> ((x >> 12) & 0xf)) & 2
        f |= (0x0d938 >> ((x >> 16) & 0xf)) & 1
        return UInt8((0xEC57E80A >> f) & 1)
    }

    // MARK: - 状态机

    /// 用 48 位密钥初始化 LFSR（状态为 odd/even 两半；位序对齐 crypto1_init 的 ^7 约定）
    static func initState(_ key: UInt64) -> Crypto1State {
        var s = Crypto1State()
        for i in stride(from: 47, through: 1, by: -2) {
            s.odd = (s.odd << 1) | UInt32((key >> UInt64((i - 1) ^ 7)) & 1)
            s.even = (s.even << 1) | UInt32((key >> UInt64(i ^ 7)) & 1)
        }
        return s
    }

    /// 单 bit 前向（对照 crypto1_bit：先清 odd 高位，最后交换）
    @discardableResult
    static func bitForward(_ s: inout Crypto1State, inbit: UInt32, isEncrypted: UInt32) -> UInt8 {
        s.odd &= 0xffffff
        let ret = filter(s.odd)
        var feedin = UInt32(ret) & isEncrypted
        feedin ^= (inbit & 1)
        feedin ^= lfPolyOdd & s.odd
        feedin ^= lfPolyEven & s.even
        s.even = (s.even << 1) | evenParity32(feedin)
        let t = s.odd
        s.odd = s.even
        s.even = t
        return ret
    }

    /// 32 位前向（参考 crypto1_word：位序 0→31 升序，输出按 (24^n) 移位）
    @discardableResult
    static func wordForward(_ s: inout Crypto1State, inWord: UInt32, isEncrypted: UInt32) -> UInt32 {
        var ret: UInt32 = 0
        for n in 0..<32 {
            ret |= UInt32(bitForward(&s, inbit: beBit(inWord, n), isEncrypted: isEncrypted)) << UInt32(24 ^ n)
        }
        return ret
    }

    /// 获取 48 位 LFSR 状态（即候选密钥）
    static func getLFSR(_ s: Crypto1State) -> UInt64 {
        var lfsr: UInt64 = 0
        for i in stride(from: 23, through: 0, by: -1) {
            lfsr = (lfsr << 1) | UInt64(bit(s.odd, i ^ 3))
            lfsr = (lfsr << 1) | UInt64(bit(s.even, i ^ 3))
        }
        return lfsr
    }

    // MARK: - PRNG（Mifare 弱随机数生成器）

    /// SWAPENDIAN：先交换每半字的字节序，再交换两个半字（两步顺序执行，缺一不可）
    static func swapEndian(_ x: UInt32) -> UInt32 {
        var v = (x >> 8 & 0x00ff00ff) | (x & 0x00ff00ff) << 8
        v = (v >> 16) | (v << 16)
        return v
    }

    /// prng_successor(x, n)
    static func prngSuccessor(_ x: UInt32, _ n: Int) -> UInt32 {
        var v = swapEndian(x)
        var remaining = n
        while remaining > 0 {
            v = (v >> 1) | ((v >> 16 ^ v >> 18 ^ v >> 19 ^ v >> 21) << 31)
            remaining -= 1
        }
        return swapEndian(v)
    }

    /// 验证 nonce 是否由弱 PRNG 生成（对照 pm3 validate_prng_nonce：1=弱，0=强）
    static func validatePrngNonce(_ nonce: UInt32) -> Int {
        var x: UInt16 = UInt16(nonce >> 16)
        x = (x & 0xff) << 8 | x >> 8
        for _ in 0..<16 {
            let t = UInt32(x) ^ (UInt32(x) >> 2) ^ (UInt32(x) >> 3) ^ (UInt32(x) >> 5)
            x = (x >> 1) | UInt16(truncatingIfNeeded: t << 15)
        }
        x = (x & 0xff) << 8 | x >> 8
        return x == UInt16(nonce & 0xFFFF) ? 1 : 0
    }

    /// 完整 32 位 NT 重建：(nt16 << 16) | prng_successor(nt16, 16)
    static func reconstructFullNt(_ nt16: UInt32) -> UInt32 {
        (nt16 << 16) | prngSuccessor(nt16, 16)
    }
}
