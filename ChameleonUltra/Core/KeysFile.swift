import Foundation

/// 默认密钥库与 Gen2 后门密钥
/// 来源：proxmark3 客户端默认密钥 + 官方 GUI helpers_mifare_classic_general.dart
enum KeysFile {

    /// 常见默认密钥（来自 pm3 客户端 + 官方 GUI 列表）
    static let defaultKeys: [[UInt8]] = [
        // pm3 首推：DEFAULT / NFCFORUM MAD / NDEF PUBLIC / EV1 签名
        hex("FFFFFFFFFFFF"),   // DEFAULT KEY
        hex("A0A1A2A3A4A5"),   // NFCFORUM MAD KEY
        hex("D3F7D3F7D3F7"),   // NDEF PUBLIC KEY
        hex("4B791BEA7BCC"),   // MFC EV1 SIGNATURE 17 B
        hex("5C8FF9990DA2"),   // MFC EV1 SIGNATURE 16 A
        hex("D01AFEEB890A"),   // MFC EV1 SIGNATURE 16 B
        hex("75CCB59C9BED"),   // MFC EV1 SIGNATURE 17 A
        hex("6471A5EF2D1A"),   // SIMONSVOSS
        hex("4E3552426B32"),   // ID06
        hex("EF1232AB18A0"),   // SCHLAGE
        hex("B7BF0C13066E"),   // GALLAGHER
        hex("135B88A94B8B"),   // SAFLOK
        hex("2A2C13CC242A"),   // DORMA KABA
        hex("5A7A52D5E20D"),   // BOSCH
        hex("314B49474956"),   // VIGIK1 A
        hex("564C505F4D41"),   // VIGIK1 B
        hex("021209197591"),   // BTCINO
        hex("484558414354"),   // INTRATONE
        hex("EC0A9B1A9E06"),   // VINGCARD
        hex("66B31E64CA4B"),   // VINGCARD
        hex("E00000000000"),   // ICOPY
        hex("199404281970"),   // NSP A
        hex("199404281998"),   // NSP B
        hex("6A1987C40A21"),   // SALTO
        hex("7F33625BC129"),   // SALTO
        hex("484944204953"),   // HID
        hex("204752454154"),   // HID
        hex("3B7E4FD575AD"),   // HID
        hex("11496F97752A"),   // HID
        hex("000000000000"),   // BLANK KEY
        hex("B0B1B2B3B4B5"),
        hex("AABBCCDDEEFF"),
        hex("1A2B3C4D5E6F"),
        hex("123456789ABC"),
        hex("010203040506"),
        hex("123456ABCDEF"),
        hex("ABCDEF123456"),
        hex("4D3A99C351DD"),
        hex("1A982C7E459A"),
        hex("714C5C886E97"),
        hex("587EE5F9350F"),
        hex("A0478CC39091"),
        hex("533CB6C723F6"),
        hex("8FD0A4F256E9"),
        hex("0000014B5C31"),
        hex("B578F38A5C61"),
        hex("96A301BCE267"),
        hex("112233445566"),
        hex("102030405060"),
        hex("ABCDEFABCDEF"),
        hex("4B0B20107B7C"),
        hex("BBC0A2B38F5E"),
        hex("9F3C7C14B9D5"),
        hex("BF59ACD51C2D"),
        hex("D36D74F4224B"),
        hex("C5515BCE4B30"),
        hex("52EAC48927D3"),
        hex("F4D00B4CE212"),
        hex("3E3B44E867C6"),
        hex("D9DFB03B7E54"),
        hex("B26F5E1A1847"),
        hex("7A9E93E6F73A"),
        hex("2D3D5E6F7A8B"),
        hex("1F3E5D7C9BA0"),
        hex("A5A6A7A8A9AA"),
        hex("4A4B4C4D4E4F"),
        hex("1E2F3A4B5C6D"),
        hex("0E1F2A3B4C5D"),
        hex("A1A2A3A4A5A6"),
        hex("E1E2E3E4E5E6"),
        hex("F0F1F2F3F4F5"),
        hex("010101010101"),
        hex("020202020202"),
        hex("030303030303"),
        hex("040404040404"),
        hex("050505050505"),
        hex("060606060606"),
        hex("070707070707"),
        hex("080808080808"),
        hex("090909090909"),
        hex("0A0A0A0A0A0A"),
        hex("0B0B0B0B0B0B"),
        hex("0C0C0C0C0C0C"),
        hex("0D0D0D0D0D0D"),
        hex("0E0E0E0E0E0E"),
        hex("0F0F0F0F0F0F"),
        hex("101010101010"),
        hex("111111111111"),
        hex("121212121212"),
        hex("131313131313"),
        hex("141414141414"),
        hex("151515151515"),
        hex("161616161616"),
        hex("171717171717"),
        hex("181818181818"),
        hex("191919191919"),
        hex("1A1A1A1A1A1A"),
        hex("1B1B1B1B1B1B"),
        hex("1C1C1C1C1C1C"),
        hex("1D1D1D1D1D1D"),
        hex("1E1E1E1E1E1E"),
        hex("1F1F1F1F1F1F"),
        hex("202020202020"),
        hex("222222222222"),
        hex("242424242424"),
        hex("262626262626"),
        hex("282828282828"),
        hex("2A2A2A2A2A2A"),
        hex("2C2C2C2C2C2C"),
        hex("2E2E2E2E2E2E"),
        hex("303030303030"),
        hex("333333333333"),
        hex("363636363636"),
        hex("393939393939"),
        hex("3C3C3C3C3C3C"),
        hex("3F3F3F3F3F3F"),
        hex("404040404040"),
        hex("444444444444"),
        hex("484848484848"),
        hex("4C4C4C4C4C4C"),
        hex("505050505050"),
        hex("555555555555"),
        hex("5A5A5A5A5A5A"),
        hex("5E5E5E5E5E5E"),
        hex("606060606060"),
        hex("666666666666"),
        hex("6A6A6A6A6A6A"),
        hex("6C6C6C6C6C6C"),
        hex("707070707070"),
        hex("777777777777"),
        hex("7A7A7A7A7A7A"),
        hex("7E7E7E7E7E7E"),
        hex("7F7F7F7F7F7F"),
        hex("808080808080"),
        hex("888888888888"),
        hex("8A8A8A8A8A8A"),
        hex("8E8E8E8E8E8E"),
        hex("909090909090"),
        hex("999999999999"),
        hex("9A9A9A9A9A9A"),
        hex("9E9E9E9E9E9E"),
        hex("A5A5A5A5A5A5"),
        hex("A6A6A6A6A6A6"),
        hex("AAAAAAAABBBB"),
        hex("B0B0B0B0B0B0"),
        hex("BBBBBBBBBBBB"),
        hex("CCCCCCCCCCCC"),
        hex("DDDDDDDDDDDD"),
        hex("EEEEEEEEEEEE"),
        hex("0A0B0C0D0E0F"),
        hex("1A1B1C1D1E1F"),
        hex("2A2B2C2D2E2F"),
        hex("3A3B3C3D3E3F"),
        hex("4A4B4C4D4E4F"),
        hex("5A5B5C5D5E5F"),
        hex("6A6B6C6D6E6F"),
        hex("7A7B7C7D7E7F"),
        hex("8A8B8C8D8E8F"),
        hex("9A9B9C9D9E9F"),
        hex("AAABACADAEAF"),
        hex("BABBBCBDBEBF"),
        hex("CACBCCCDCECF"),
        hex("DADBDCDDDEDF"),
        hex("EAEBECEDEEEF"),
        hex("FAFBFCFDFEFF"),
        hex("504D33584745"),
    ].filter { $0.count == 6 }

    /// Gen2 后门密钥（https://eprint.iacr.org/2024/1275）
    static let backdoorKeys: [[UInt8]] = [
        hex("A396EFA4E24F"),
        hex("A31667A8CEC1"),
        hex("518B3354E760"),
        hex("73B9836CF168"),
    ].filter { $0.count == 6 }

    /// 从十六进制字符串解析 6 字节密钥（忽略非十六进制字符）
    static func hex(_ s: String) -> [UInt8] {
        let clean = s.filter { $0.isHexDigit }
        guard clean.count >= 12 else { return [] }
        var out: [UInt8] = []
        var idx = clean.startIndex
        for _ in 0..<6 {
            let end = clean.index(idx, offsetBy: 2)
            if let v = UInt8(clean[idx..<end], radix: 16) { out.append(v) }
            idx = end
        }
        return out
    }
}
