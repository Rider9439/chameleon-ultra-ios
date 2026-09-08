import Foundation

/// LFSR 密钥恢复与状态回滚
/// 移植自 proxmark3 common/crapto1/crapto1.c + bucketsort.c + client/src/mifare/mfkey.c
/// 已用官方参考 C 代码在自生成认证会话上逐项验证：recovery32/recovery64/rollback/prng/validate 输出 100% 一致。
enum LfsrRecovery {

    // MARK: - fastfwd 表（darkside 公共前缀攻击）

    private static let fastfwd: [[UInt32]] = [
        [0, 0x4BC53, 0xECB1, 0x450E2, 0x25E29, 0x6E27A, 0x2B298, 0x60ECB],
        [0, 0x1D962, 0x4BC53, 0x56531, 0xECB1, 0x135D3, 0x450E2, 0x58980],
    ]

    // MARK: - 回滚（位序 31→0 / 7→0 降序 —— 与 crypto1_word 的升序相反，参考实现硬约束）

    @discardableResult
    static func rollbackBit(_ s: inout Crypto1State, inBit: UInt32, fb: UInt32) -> UInt8 {
        // 对照 lfsr_rollback_bit（crapto1.c）：先交换 odd/even，再基于交换后的状态计算，不再换回
        s.odd &= 0xffffff
        let t = s.odd
        s.odd = s.even
        s.even = t

        var out = s.even & 1
        s.even >>= 1
        out ^= Crypto1.lfPolyEven & s.even
        out ^= Crypto1.lfPolyOdd & s.odd
        out ^= inBit & 1
        let ret = Crypto1.filter(s.odd)
        out ^= UInt32(ret) & fb
        s.even |= Crypto1.evenParity32(out) << 23
        return ret
    }

    @discardableResult
    static func rollbackWord(_ s: inout Crypto1State, inWord: UInt32, fb: UInt32) -> UInt32 {
        var ret: UInt32 = 0
        var n = 31
        while n >= 0 {
            ret |= UInt32(rollbackBit(&s, inBit: Crypto1.beBit(inWord, n), fb: fb)) << UInt32(24 ^ n)
            n -= 1
        }
        return ret
    }

    @discardableResult
    static func rollbackByte(_ s: inout Crypto1State, inByte: UInt32, fb: UInt32) -> UInt8 {
        var ret: UInt8 = 0
        var n = 7
        while n >= 0 {
            ret |= rollbackBit(&s, inBit: Crypto1.bit(inByte, n), fb: fb) << UInt8(n)
            n -= 1
        }
        return ret
    }

    // MARK: - 状态扩展（extend_table / extend_table_simple，指针语义 1:1）

    private static func updateContribution(_ item: UnsafeMutablePointer<UInt32>, _ m1: UInt32, _ m2: UInt32) {
        var p = item.pointee >> 25
        p = (p << 1) | Crypto1.evenParity32(item.pointee & m1)
        p = (p << 1) | Crypto1.evenParity32(item.pointee & m2)
        item.pointee = (p << 24) | (item.pointee & 0xffffff)
    }

    private static func extendTable(_ tbl: UnsafeMutablePointer<UInt32>, _ end: inout UnsafeMutablePointer<UInt32>, bit b: UInt32, m1: UInt32, m2: UInt32, in inv: UInt32) {
        let inShift = inv << 24
        tbl.pointee <<= 1
        var t = tbl
        while t <= end {
            let f0 = Crypto1.filter(t.pointee)
            let f1 = Crypto1.filter(t.pointee | 1)
            if f0 ^ f1 != 0 {
                // replace
                t.pointee |= UInt32(f0) ^ b
                updateContribution(t, m1, m2)
                t.pointee ^= inShift
                t += 1
                if t <= end { t.pointee <<= 1 }
            } else if f0 == b {
                // insert：*++*end = tbl[1]; tbl[1] = tbl[0] | 1
                end += 1
                end.pointee = t[1]
                t[1] = t[0] | 1
                updateContribution(t, m1, m2)
                t.pointee ^= inShift
                t += 1
                updateContribution(t, m1, m2)
                t.pointee ^= inShift
                t += 1
                if t <= end { t.pointee <<= 1 }
            } else {
                // drop：*tbl-- = *(*end)-- 后循环增量 *++tbl <<= 1 → 拷贝值被左移
                t.pointee = end.pointee
                end -= 1
                t.pointee <<= 1
            }
        }
    }

    private static func extendTableSimple(_ tbl: UnsafeMutablePointer<UInt32>, _ end: inout UnsafeMutablePointer<UInt32>, bit b: UInt32) {
        tbl.pointee <<= 1
        var t = tbl
        while t <= end {
            let f0 = Crypto1.filter(t.pointee)
            let f1 = Crypto1.filter(t.pointee | 1)
            if f0 ^ f1 != 0 {
                // replace
                t.pointee |= UInt32(f0) ^ b
                t += 1
                if t <= end { t.pointee <<= 1 }
            } else if f0 == b {
                // insert：*++*end = *++tbl; *tbl = tbl[-1] | 1
                end += 1
                t += 1
                end.pointee = t.pointee
                t.pointee = t[-1] | 1
                t += 1
                if t <= end { t.pointee <<= 1 }
            } else {
                // drop
                t.pointee = end.pointee
                end -= 1
                t.pointee <<= 1
            }
        }
    }

    // MARK: - 桶排序（bucketsort.c bucket_sort_intersect）

    private struct BucketInfo {
        var bi: [[(head: UnsafeMutablePointer<UInt32>, tail: UnsafeMutablePointer<UInt32>)]] = {
            let sentinel = UnsafeMutablePointer<UInt32>(bitPattern: 0x1)!
            var arr: [[(head: UnsafeMutablePointer<UInt32>, tail: UnsafeMutablePointer<UInt32>)]] = []
            for _ in 0..<2 {
                arr.append(Array(repeating: (head: sentinel, tail: sentinel), count: 0x100))
            }
            return arr
        }()
        var numbuckets: Int = 0
    }

    private static func bucketSortIntersect(_ estart: UnsafeMutablePointer<UInt32>, _ estop: UnsafeMutablePointer<UInt32>,
                                            _ ostart: UnsafeMutablePointer<UInt32>, _ ostop: UnsafeMutablePointer<UInt32>,
                                            _ binfo: inout BucketInfo,
                                            _ bucketHead: inout [[UnsafeMutablePointer<UInt32>]],
                                            _ bucketBP: inout [[UnsafeMutablePointer<UInt32>]]) {
        let starts: [UnsafeMutablePointer<UInt32>] = [estart, ostart]
        let stops: [UnsafeMutablePointer<UInt32>] = [estop, ostop]

        for i in 0..<2 {
            for j in 0..<0x100 {
                bucketBP[i][j] = bucketHead[i][j]
            }
        }

        for i in 0..<2 {
            var p1 = starts[i]
            while p1 <= stops[i] {
                let idx = Int((p1.pointee & 0xff000000) >> 24)
                bucketBP[i][idx].pointee = p1.pointee
                bucketBP[i][idx] += 1
                p1 += 1
            }
        }

        for i in 0..<2 {
            var p1 = starts[i]
            var nonempty = 0
            for j in 0..<0x100 {
                if bucketBP[0][j] != bucketHead[0][j] && bucketBP[1][j] != bucketHead[1][j] {
                    binfo.bi[i][nonempty].head = p1
                    var p2 = bucketHead[i][j]
                    while p2 < bucketBP[i][j] {
                        p1.pointee = p2.pointee
                        p1 += 1
                        p2 += 1
                    }
                    binfo.bi[i][nonempty].tail = p1 - 1
                    nonempty += 1
                }
            }
            binfo.numbuckets = nonempty
        }
    }

    // MARK: - recover 递归（rem-- 语义与 -1 展开，对照参考逐行）

    private static func recover(oHead: UnsafeMutablePointer<UInt32>, oTail: UnsafeMutablePointer<UInt32>, oks: UInt32,
                                eHead: UnsafeMutablePointer<UInt32>, eTail: UnsafeMutablePointer<UInt32>, eks: UInt32,
                                rem: Int, sl: UnsafeMutablePointer<Crypto1State>, in inv: UInt32,
                                bucketHead: inout [[UnsafeMutablePointer<UInt32>]], bucketBP: inout [[UnsafeMutablePointer<UInt32>]]) -> UnsafeMutablePointer<Crypto1State> {
        if rem == -1 {
            var e = eHead
            var s = sl
            while e <= eTail {
                e.pointee = e.pointee << 1 ^ Crypto1.evenParity32(e.pointee & Crypto1.lfPolyEven) ^ ((inv >> 2) & 1)
                var o = oHead
                while o <= oTail {
                    s.pointee.even = o.pointee
                    s.pointee.odd = e.pointee ^ Crypto1.evenParity32(o.pointee & Crypto1.lfPolyOdd)
                    s[1].odd = 0
                    s[1].even = 0
                    o += 1
                    s += 1
                }
                e += 1
            }
            return s
        }

        var oksV = oks, eksV = eks, inV = inv
        var oTailV = oTail, eTailV = eTail
        var remV = rem
        var i = 0
        // 精确模拟 `for (i = 0; i < 4 && rem--; i++)`：每次条件检查都 rem--，旧值非零才进入循环体
        while i < 4 {
            let oldRem = remV
            remV -= 1
            if oldRem <= 0 { break }

            oksV >>= 1
            extendTable(oHead, &oTailV, bit: oksV & 1, m1: Crypto1.lfPolyEven << 1 | 1, m2: Crypto1.lfPolyOdd << 1, in: 0)
            if oTailV < oHead { return sl }
            eksV >>= 1
            inV >>= 2
            extendTable(eHead, &eTailV, bit: eksV & 1, m1: Crypto1.lfPolyOdd, m2: Crypto1.lfPolyEven << 1 | 1, in: inV & 3)
            if eTailV < eHead { return sl }
            i += 1
        }

        var binfo = BucketInfo()
        bucketSortIntersect(eHead, eTailV, oHead, oTailV, &binfo, &bucketHead, &bucketBP)

        var s = sl
        var b = binfo.numbuckets - 1
        while b >= 0 {
            let oH = binfo.bi[1][b].head, oT = binfo.bi[1][b].tail
            let eH = binfo.bi[0][b].head, eT = binfo.bi[0][b].tail
            s = recover(oHead: oH, oTail: oT, oks: oksV, eHead: eH, eTail: eT, eks: eksV,
                         rem: remV, sl: s, in: inV, bucketHead: &bucketHead, bucketBP: &bucketBP)
            b -= 1
        }
        return s
    }

    // MARK: - recovery32

    /// lfsr_recovery32(ks2, in)：恢复 32 位密钥流对应的候选状态列表
    static func recovery32(ks2: UInt32, in inv: UInt32) -> [Crypto1State] {
        var oks: UInt32 = 0, eks: UInt32 = 0
        var idx = 31
        while idx >= 0 {
            oks = oks << 1 | Crypto1.beBit(ks2, idx)
            idx -= 2
        }
        idx = 30
        while idx >= 0 {
            eks = eks << 1 | Crypto1.beBit(ks2, idx)
            idx -= 2
        }

        let oddHead = UnsafeMutablePointer<UInt32>.allocate(capacity: 1 << 21)
        oddHead.initialize(repeating: 0, count: 1 << 21)
        let evenHead = UnsafeMutablePointer<UInt32>.allocate(capacity: 1 << 21)
        evenHead.initialize(repeating: 0, count: 1 << 21)
        let statelist = UnsafeMutablePointer<Crypto1State>.allocate(capacity: 1 << 18)
        statelist.initialize(repeating: Crypto1State(), count: 1 << 18)

        defer {
            oddHead.deallocate()
            evenHead.deallocate()
            statelist.deallocate()
        }

        var oddTail = oddHead - 1
        var evenTail = evenHead - 1
        statelist.pointee.odd = 0
        statelist.pointee.even = 0

        // 桶（2×256，每桶 2^14 个 uint32）
        var bucketHead: [[UnsafeMutablePointer<UInt32>]] = []
        var bucketBP: [[UnsafeMutablePointer<UInt32>]] = []
        for _ in 0..<2 {
            var ha: [UnsafeMutablePointer<UInt32>] = []
            var ba: [UnsafeMutablePointer<UInt32>] = []
            for _ in 0..<0x100 {
                let p = UnsafeMutablePointer<UInt32>.allocate(capacity: 1 << 14)
                p.initialize(repeating: 0, count: 1 << 14)
                ha.append(p)
                ba.append(p)
            }
            bucketHead.append(ha)
            bucketBP.append(ba)
        }
        defer {
            for arr in bucketHead { for p in arr { p.deallocate() } }
        }

        let oksB1 = oks & 1
        let eksB1 = eks & 1
        for v in stride(from: 1 << 20, through: 0, by: -1) {
            let f = Crypto1.filter(UInt32(v))
            if f == UInt8(oksB1) {
                oddTail += 1
                oddTail.pointee = UInt32(v)
            }
            if f == UInt8(eksB1) {
                evenTail += 1
                evenTail.pointee = UInt32(v)
            }
        }

        for _ in 0..<4 {
            oks >>= 1
            extendTableSimple(oddHead, &oddTail, bit: oks & 1)
            eks >>= 1
            extendTableSimple(evenHead, &evenTail, bit: eks & 1)
        }

        let rearranged = (inv >> 16 & 0xff) | (inv << 16) | (inv & 0xff00)

        _ = recover(oHead: oddHead, oTail: oddTail, oks: oks, eHead: evenHead, eTail: evenTail, eks: eks,
                    rem: 11, sl: statelist, in: rearranged << 1, bucketHead: &bucketHead, bucketBP: &bucketBP)

        var result: [Crypto1State] = []
        var t = statelist
        while (t.pointee.odd | t.pointee.even) != 0 {
            result.append(t.pointee)
            t += 1
        }
        return result
    }

    // MARK: - recovery64（表驱动算法，对照 pm3 lfsr_recovery64）

    private static let s1: [UInt32] = [0x62141, 0x310A0, 0x18850, 0x0C428, 0x06214, 0x0310A, 0x85E30, 0xC69AD,
                                       0x634D6, 0xB5CDE, 0xDE8DA, 0x6F46D, 0xB3C83, 0x59E41, 0xA8995, 0xD027F,
                                       0x6813F, 0x3409F, 0x9E6FA]
    private static let s2: [UInt32] = [0x3A557B00, 0x5D2ABD80, 0x2E955EC0, 0x174AAF60, 0x0BA557B0, 0x05D2ABD8,
                                       0x0449DE68, 0x048464B0, 0x42423258, 0x278192A8, 0x156042D0, 0x0AB02168,
                                       0x43F89B30, 0x61FC4D98, 0x765EAD48, 0x7D8FDD20, 0x7EC7EE90, 0x7F63F748,
                                       0x79117020]
    private static let t1: [UInt32] = [0x4F37D, 0x279BE, 0x97A6A, 0x4BD35, 0x25E9A, 0x12F4D, 0x097A6, 0x80D66,
                                       0xC4006, 0x62003, 0xB56B4, 0x5AB5A, 0xA9318, 0xD0F39, 0x6879C, 0xB057B,
                                       0x582BD, 0x2C15E, 0x160AF, 0x8F6E2, 0xC3DC4, 0xE5857, 0x72C2B, 0x39615,
                                       0x98DBF, 0xC806A, 0xE0680, 0x70340, 0x381A0, 0x98665, 0x4C332, 0xA272C]
    private static let t2: [UInt32] = [0x3C88B810, 0x5E445C08, 0x2982A580, 0x14C152C0, 0x4A60A960, 0x253054B0,
                                       0x52982A58, 0x2FEC9EA8, 0x1156C4D0, 0x08AB6268, 0x42F53AB0, 0x217A9D58,
                                       0x161DC528, 0x0DAE6910, 0x46D73488, 0x25CB11C0, 0x52E588E0, 0x6972C470,
                                       0x34B96238, 0x5CFC3A98, 0x28DE96C8, 0x12CFC0E0, 0x4967E070, 0x64B3F038,
                                       0x74F97398, 0x7CDC3248, 0x38CE92A0, 0x1C674950, 0x0E33A4A8, 0x01B959D0,
                                       0x40DCACE8, 0x26CEDDF0]
    private static let c1: [UInt32] = [0x846B5, 0x4235A, 0x211AD]
    private static let c2: [UInt32] = [0x1A822E0, 0x21A822E0, 0x21A822E0]

    /// lfsr_recovery64(ks2, ks3)：恢复 48 位密钥流对应的候选状态列表
    static func recovery64(ks2: UInt32, ks3: UInt32) -> [Crypto1State] {
        var oks = [UInt8](repeating: 0, count: 32)
        var eks = [UInt8](repeating: 0, count: 32)
        var hi = [UInt8](repeating: 0, count: 32)
        var low: UInt32 = 0
        var win: UInt32 = 0

        let statelist = UnsafeMutablePointer<Crypto1State>.allocate(capacity: 1 << 4)
        statelist.initialize(repeating: Crypto1State(), count: 1 << 4)
        let table = UnsafeMutablePointer<UInt32>.allocate(capacity: 1 << 16)
        defer {
            statelist.deallocate()
            table.deallocate()
        }

        var sl = statelist
        sl.pointee.odd = 0
        sl.pointee.even = 0

        var i = 30
        while i >= 0 {
            oks[i >> 1] = UInt8(Crypto1.beBit(ks2, i))
            oks[16 + (i >> 1)] = UInt8(Crypto1.beBit(ks3, i))
            i -= 2
        }
        i = 31
        while i >= 0 {
            eks[i >> 1] = UInt8(Crypto1.beBit(ks2, i))
            eks[16 + (i >> 1)] = UInt8(Crypto1.beBit(ks3, i))
            i -= 2
        }

        var iVal = 0xfffff
        while iVal >= 0 {
            let iv = UInt32(iVal)
            if Crypto1.filter(iv) != oks[0] {
                iVal -= 1
                continue
            }

            var tail = table
            tail.pointee = iv
            var j = 1
            while tail >= table && j < 29 {
                extendTableSimple(table, &tail, bit: UInt32(oks[j]))
                j += 1
            }
            if tail < table {
                iVal -= 1
                continue
            }

            low = 0
            for j in 0..<19 {
                low = low << 1 | Crypto1.evenParity32(iv & Self.s1[j])
            }
            for j in 0..<32 {
                hi[j] = UInt8(Crypto1.evenParity32(iv & Self.t1[j]))
            }

            var t = tail
            while t >= table {
                var valid = true
                var j2 = 0
                while j2 < 3 {
                    t.pointee = t.pointee << 1
                    t.pointee |= Crypto1.evenParity32((iv & Self.c1[j2]) ^ (t.pointee & Self.c2[j2]))
                    if Crypto1.filter(t.pointee) != oks[29 + j2] {
                        valid = false
                        break
                    }
                    j2 += 1
                }
                if valid {
                    win = 0
                    for j3 in 0..<19 {
                        win = win << 1 | Crypto1.evenParity32(t.pointee & Self.s2[j3])
                    }
                    win ^= low
                    var j4 = 0
                    while j4 < 32 {
                        win = win << 1 ^ UInt32(hi[j4]) ^ Crypto1.evenParity32(t.pointee & Self.t2[j4])
                        if Crypto1.filter(win) != eks[j4] {
                            valid = false
                            break
                        }
                        j4 += 1
                    }
                    if valid {
                        t.pointee = t.pointee << 1 | Crypto1.evenParity32(Crypto1.lfPolyEven & t.pointee)
                        sl.pointee.odd = t.pointee ^ Crypto1.evenParity32(Crypto1.lfPolyOdd & win)
                        sl.pointee.even = win
                        sl += 1
                        sl.pointee.odd = 0
                        sl.pointee.even = 0
                    }
                }
                t -= 1
            }
            iVal -= 1
        }

        var result: [Crypto1State] = []
        var sp = statelist
        while (sp.pointee.odd | sp.pointee.even) != 0 {
            result.append(sp.pointee)
            sp += 1
        }
        return result
    }

    // MARK: - darkside 公共前缀恢复（lfsr_prefix_ks / check_pfx_parity / lfsr_common_prefix）

    private static func lfsrPrefixKS(_ ks: [UInt8], isOdd: Int) -> [UInt32] {
        var candidates: [UInt32] = []
        for i in 0..<(1 << 21) {
            var good = true
            var c = 0
            while good && c < 8 {
                let entry = UInt32(i) ^ Self.fastfwd[isOdd][c]
                good = Crypto1.bit(UInt32(ks[c]), isOdd) == UInt32(Crypto1.filter(entry >> 1))
                    && Crypto1.bit(UInt32(ks[c]), isOdd + 2) == UInt32(Crypto1.filter(entry))
                c += 1
            }
            if good {
                candidates.append(UInt32(i))
            }
        }
        candidates.append(UInt32.max)
        return candidates
    }

    /// 返回 (good, 候选状态)；good 非 0 表示通过奇偶校验
    private static func checkPfxParity(prefix: UInt32, rresp: UInt32, parities: [[UInt8]], odd: UInt32, even: UInt32, noPar: Bool) -> (UInt32, Crypto1State) {
        var good: UInt32 = 1
        var lastC = 0
        var c = 0
        while good != 0 && c < 8 {
            var st = Crypto1State(odd: odd ^ Self.fastfwd[1][c], even: even ^ Self.fastfwd[0][c])
            _ = rollbackBit(&st, inBit: 0, fb: 0)
            _ = rollbackBit(&st, inBit: 0, fb: 0)
            let ks3 = UInt32(rollbackBit(&st, inBit: 0, fb: 0))
            let ks2 = rollbackWord(&st, inWord: 0, fb: 0)
            let ks1 = rollbackWord(&st, inWord: prefix | (UInt32(c) << 5), fb: 1)

            if noPar { break }

            let nr = ks1 ^ (prefix | (UInt32(c) << 5))
            let rr = ks2 ^ rresp

            if Crypto1.evenParity32(nr & 0x000000ff) ^ UInt32(parities[c][3]) ^ Crypto1.bit(ks2, 24) != 0 { good = 0 }
            if good != 0 && Crypto1.evenParity32(rr & 0xff000000) ^ UInt32(parities[c][4]) ^ Crypto1.bit(ks2, 16) != 0 { good = 0 }
            if good != 0 && Crypto1.evenParity32(rr & 0x00ff0000) ^ UInt32(parities[c][5]) ^ Crypto1.bit(ks2, 8) != 0 { good = 0 }
            if good != 0 && Crypto1.evenParity32(rr & 0x0000ff00) ^ UInt32(parities[c][6]) ^ Crypto1.bit(ks2, 0) != 0 { good = 0 }
            if good != 0 && Crypto1.evenParity32(rr & 0x000000ff) ^ UInt32(parities[c][7]) ^ ks3 != 0 { good = 0 }
            lastC = c
            c += 1
        }
        // 参考实现：状态在每次 c 迭代开头写入 sl，最终保留的是最后一次迭代的值
        let candidate = Crypto1State(odd: odd ^ Self.fastfwd[1][lastC], even: even ^ Self.fastfwd[0][lastC])
        return (good, candidate)
    }

    /// lfsr_common_prefix：darkside 公共前缀攻击（返回状态列表，含终止哨兵）
    static func lfsrCommonPrefix(pfx: UInt32, rr: UInt32, ks: [UInt8], par: [[UInt8]], noPar: Bool) -> [Crypto1State] {
        let oddList = lfsrPrefixKS(ks, isOdd: 1)
        let evenList = lfsrPrefixKS(ks, isOdd: 0)

        var states: [Crypto1State] = []
        var o = 0
        while oddList[o] != UInt32.max {
            // 参考语义：*o 在 top 循环内被持续累加（跨 e 迭代保留）
            var oddAccum = oddList[o]
            var e = 0
            while evenList[e] != UInt32.max {
                var evenAccum = evenList[e]
                var top: UInt32 = 0
                while top < 64 {
                    oddAccum += 1 << 21
                    evenAccum += (((top & 7) == 0) ? 2 : 1) << 21
                    let (good, candidate) = checkPfxParity(prefix: pfx, rresp: rr, parities: par, odd: oddAccum, even: evenAccum, noPar: noPar)
                    if good != 0 {
                        states.append(candidate)
                    }
                    top += 1
                }
                e += 1
            }
            o += 1
        }
        states.append(Crypto1State(odd: 0, even: 0))
        return states
    }

    // MARK: - nonce 距离

    /// nonce_distance(x, y)：prng_successor(x, d) = y 的距离；无效返回 -1
    static func nonceDistance(from: UInt32, to: UInt32) -> Int {
        for d in 1..<64 {
            if Crypto1.prngSuccessor(from, d) == to { return d }
        }
        return -1
    }
}
