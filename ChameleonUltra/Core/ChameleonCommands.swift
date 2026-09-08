import Foundation

/// 命令枚举（对齐官方 GUI definitions.dart 全部取值）
enum ChameleonCmd: UInt16, CaseIterable {
    // 基础
    case getAppVersion = 1000
    case changeDeviceMode = 1001
    case getDeviceMode = 1002
    case getGitVersion = 1017
    case getBatteryCharge = 1025

    // 卡槽
    case setActiveSlot = 1003
    case setSlotTagType = 1004
    case setSlotDataDefault = 1005
    case setSlotEnable = 1006
    case setSlotTagNick = 1007
    case getSlotTagNick = 1008
    case saveSlotNicks = 1009
    case getActiveSlot = 1018
    case getSlotInfo = 1019
    case getEnabledSlots = 1023
    case deleteSlotInfo = 1024
    case getAllSlotNicks = 1038

    // Bootloader
    case enterBootloader = 1010

    // 设备信息
    case getDeviceChipID = 1011
    case getDeviceBLEAddress = 1012

    // 设置
    case saveSettings = 1013
    case resetSettings = 1014
    case setAnimationMode = 1015
    case getAnimationMode = 1016
    case factoryReset = 1020
    case getDeviceType = 1033
    case getDeviceSettings = 1034
    case getDeviceCapabilities = 1035
    case getSleepTimeout = 1039
    case setSleepTimeout = 1040

    // 按键
    case getButtonPressConfig = 1026
    case setButtonPressConfig = 1027
    case getLongButtonPressConfig = 1028
    case setLongButtonPressConfig = 1029

    // BLE
    case bleSetConnectKey = 1030
    case bleGetConnectKey = 1031
    case bleClearBondedDevices = 1032
    case bleGetPairEnable = 1036
    case bleSetPairEnable = 1037

    // HF 读卡器
    case scan14ATag = 2000
    case mf1SupportDetect = 2001
    case mf1NTLevelDetect = 2002
    case mf1StaticNestedAcquire = 2003
    case mf1DarksideAcquire = 2004
    case mf1NTDistanceDetect = 2005
    case mf1NestedAcquire = 2006
    case mf1CheckKey = 2007
    case mf1ReadBlock = 2008
    case mf1WriteBlock = 2009
    case mf1ManipulateValueBlock = 2011
    case mf1CheckKeysOfSectors = 2012
    case mf1HardNestedAcquire = 2013
    case mf1StaticEncryptedNestedAcquire = 2014
    case mf1CheckKeysOnBlock = 2015
    case hf14ARawCommand = 2010
    case hf14aSniff = 2020

    // LF 读卡器
    case scanEM410Xtag = 3000
    case writeEM410XtoT5577 = 3001
    case writeEM410XElectraToT5577 = 3006
    case scanHIDProxTag = 3002
    case writeHIDProxToT5577 = 3003
    case scanVikingTag = 3004
    case writeVikingToT5577 = 3005
    case scanIoProxTag = 3010
    case writeIoProxToT5577 = 3011
    case scanPacTag = 3014
    case writePacToT5577 = 3015
    case writeIdteckToT5577 = 3018
    case lfSniff = 3031

    // 数据加载/反冲突
    case mf1LoadBlockData = 4000
    case mf1SetAntiCollision = 4001

    // 检测（密钥恢复辅助）
    case mf1SetDetectionEnable = 4004
    case mf1GetDetectionCount = 4005
    case mf1GetDetectionResult = 4006
    case mf1GetDetectionStatus = 4007

    // 模拟器设置
    case mf1GetEmulatorConfig = 4009
    case mf1GetGen1aMode = 4010
    case mf1SetGen1aMode = 4011
    case mf1GetGen2Mode = 4012
    case mf1SetGen2Mode = 4013
    case mf1GetFirstBlockColl = 4014
    case mf1SetFirstBlockColl = 4015
    case mf1GetWriteMode = 4016
    case mf1SetWriteMode = 4017

    // NTAG
    case mf0NtagGetUidMagicMode = 4019
    case mf0NtagSetUidMagicMode = 4020
    case mf0NtagReadEmuPageData = 4021
    case mf0NtagWriteEmuPageData = 4022
    case mf0NtagGetVersionData = 4023
    case mf0NtagSetVersionData = 4024
    case mf0NtagGetSignatureData = 4025
    case mf0NtagSetSignatureData = 4026
    case mf0NtagGetCounterData = 4027
    case mf0NtagSetCounterData = 4028
    case mf0NtagResetAuthCount = 4029
    case mf0NtagGetPageCount = 4030
    case mf0NtagGetWriteMode = 4031
    case mf0NtagSetWriteMode = 4032
    case mf0NtagSetDetectionEnable = 4033
    case mf0NtagGetDetectionCount = 4034
    case mf0NtagGetDetectionLog = 4035
    case mf0NtagGetDetectionEnable = 4036
    case mf0NtagGetEmulatorConfig = 4037
    case mf1GetPrngType = 4040
    case mf1SetPrngType = 4041

    // 模拟器数据
    case mf1GetBlockData = 4008
    case mf1GetAntiCollData = 4018

    // LF 模拟器
    case setEM410XemulatorID = 5000
    case getEM410XemulatorID = 5001
    case setHIDProxEmulatorID = 5002
    case getHIDProxEmulatorID = 5003
    case setVikingEmulatorID = 5004
    case getVikingEmulatorID = 5005
    case setPacEmulatorID = 5006
    case getPacEmulatorID = 5007
    case setIoProxEmulatorID = 5008
    case getIoProxEmulatorID = 5009
    case setIdteckEmulatorID = 5012
    case getIdteckEmulatorID = 5013
}

typealias ChameleonCommands = ChameleonCmd

// MARK: - 标签类型

enum TagType: UInt16 {
    case unknown = 0
    case em410X = 100
    case em410X16 = 101
    case em410X32 = 102
    case em410X64 = 103
    case em410XElectra = 104
    case pac = 150
    case viking = 170
    case hidProx = 200
    case ioProx = 201
    case idteck = 310
    case mifareMini = 1000
    case mifare1K = 1001
    case mifare2K = 1002
    case mifare4K = 1003
    case ntag210 = 1107
    case ntag212 = 1108
    case ntag213 = 1100
    case ntag215 = 1101
    case ntag216 = 1102
    case ultralight = 1103
    case ultralightC = 1104
    case ultralight11 = 1105
    case ultralight21 = 1106

    var isHf: Bool { rawValue >= 1000 }
    var isLf: Bool { rawValue > 0 && rawValue < 1000 }

    var displayName: String {
        switch self {
        case .unknown: return "未知"
        case .em410X, .em410X16, .em410X32, .em410X64: return "EM410X"
        case .em410XElectra: return "EM410X Electra"
        case .pac: return "PAC"
        case .viking: return "Viking"
        case .hidProx: return "HID Prox"
        case .ioProx: return "ioProx"
        case .idteck: return "Idteck"
        case .mifareMini: return "Mifare Mini"
        case .mifare1K: return "Mifare 1K"
        case .mifare2K: return "Mifare 2K"
        case .mifare4K: return "Mifare 4K"
        case .ntag210: return "NTAG210"
        case .ntag212: return "NTAG212"
        case .ntag213: return "NTAG213"
        case .ntag215: return "NTAG215"
        case .ntag216: return "NTAG216"
        case .ultralight: return "Ultralight"
        case .ultralightC: return "Ultralight-C"
        case .ultralight11: return "Ultralight 11"
        case .ultralight21: return "Ultralight 21"
        }
    }
}

enum TagFrequency: UInt8 {
    case unknown = 0
    case lf = 1
    case hf = 2
}

extension TagType {
    /// LF 标签 UID 长度（字节）
    var lfUidSize: Int {
        switch self {
        case .em410X, .em410X16, .em410X32, .em410X64: return 5
        case .em410XElectra: return 13
        case .hidProx: return 3
        case .viking: return 4
        case .pac: return 4
        case .ioProx: return 4
        case .idteck: return 4
        default: return 0
        }
    }
}

// MARK: - 载荷构造（对齐 GUI 的 Uint8List.fromList 格式）

enum Payload {
    /// 设备模式切换
    static func changeDeviceMode(readerMode: Bool) -> [UInt8] { [readerMode ? 1 : 0] }

    /// 激活卡槽（0..<槽数）
    static func setActiveSlot(_ slot: Int) -> [UInt8] { [UInt8(slot & 0xFF)] }

    /// 设置槽类型 [slot, type U16BE]
    static func setSlotTagType(slot: Int, type: TagType) -> [UInt8] { [UInt8(slot & 0xFF)] + type.rawValue.beBytes }

    /// 槽写入默认数据 [slot, type U16BE]
    static func setSlotDataDefault(slot: Int, type: TagType) -> [UInt8] { [UInt8(slot & 0xFF)] + type.rawValue.beBytes }

    /// 启用/停用槽频率面 [slot, frequency, 0/1]
    static func setSlotEnable(slot: Int, frequency: TagFrequency, enable: Bool) -> [UInt8] {
        [UInt8(slot & 0xFF), frequency.rawValue, enable ? 1 : 0]
    }

    /// 槽昵称 [index, frequency, utf8(name)]
    static func setSlotTagNick(index: Int, frequency: TagFrequency, name: String) -> [UInt8] {
        [UInt8(index & 0xFF), frequency.rawValue] + Array(name.utf8)
    }

    /// 读取槽昵称 [index, frequency]
    static func getSlotTagNick(index: Int, frequency: TagFrequency) -> [UInt8] {
        [UInt8(index & 0xFF), frequency.rawValue]
    }

    /// 删除槽信息 [index, frequency]
    static func deleteSlotInfo(index: Int, frequency: TagFrequency) -> [UInt8] {
        [UInt8(index & 0xFF), frequency.rawValue]
    }

    /// 扫描 ISO14443A 卡片
    static let scan14ATag: [UInt8] = []

    /// Mifare 认证 [keyType(0x60/0x61), block, key[6]]
    static func mf1CheckKey(block: Int, keyType: UInt8, key: [UInt8]) -> [UInt8] {
        [keyType, UInt8(block & 0xFF)] + key
    }

    /// 多密钥尝试 [block, keyType, count, keys...]
    static func mf1CheckKeysOnBlock(block: Int, keyType: UInt8, keys: [[UInt8]]) -> [UInt8] {
        var p: [UInt8] = [UInt8(block & 0xFF), keyType, UInt8(keys.count)]
        for k in keys { p += k.prefix(6) }
        return p
    }

    /// 读块 [keyType, block, key[6]]
    static func mf1ReadBlock(block: Int, keyType: UInt8, key: [UInt8]) -> [UInt8] {
        [keyType, UInt8(block & 0xFF)] + key.prefix(6)
    }

    /// 写块 [keyType, block, key[6], data[16]]
    static func mf1WriteBlock(block: Int, keyType: UInt8, key: [UInt8], data: [UInt8]) -> [UInt8] {
        var p = [keyType, UInt8(block & 0xFF)] + key.prefix(6)
        var d = Array(data.prefix(16))
        while d.count < 16 { d.append(0) }
        p += d
        return p
    }

    /// NT 距离检测 [keyType, block, key[6]]
    static func mf1NTDistanceDetect(block: Int, keyType: UInt8, key: [UInt8]) -> [UInt8] {
        [keyType, UInt8(block & 0xFF)] + key.prefix(6)
    }

    /// Darkside 采集 [keyType, block, firstRecover, syncMax]
    static func mf1DarksideAcquire(keyType: UInt8, block: Int, firstRecover: Bool, syncMax: Int) -> [UInt8] {
        [keyType, UInt8(block & 0xFF), firstRecover ? 1 : 0, UInt8(syncMax & 0xFF)]
    }

    /// Nested 采集 [keyType, block, key[6], targetKeyType, targetBlock]
    static func mf1NestedAcquire(block: Int, keyType: UInt8, key: [UInt8], targetBlock: Int, targetKeyType: UInt8) -> [UInt8] {
        [keyType, UInt8(block & 0xFF)] + key.prefix(6) + [targetKeyType, UInt8(targetBlock & 0xFF)]
    }

    /// Static Nested 采集（载荷与 Nested 相同）
    static func mf1StaticNestedAcquire(block: Int, keyType: UInt8, key: [UInt8], targetBlock: Int, targetKeyType: UInt8) -> [UInt8] {
        mf1NestedAcquire(block: block, keyType: keyType, key: key, targetBlock: targetBlock, targetKeyType: targetKeyType)
    }

    /// Hard Nested 采集 [slow, keyType, block, key[6], targetKeyType, targetBlock]
    static func mf1HardNestedAcquire(block: Int, keyType: UInt8, key: [UInt8], targetBlock: Int, targetKeyType: UInt8, slow: Bool) -> [UInt8] {
        [slow ? 1 : 0, keyType, UInt8(block & 0xFF)] + key.prefix(6) + [targetKeyType, UInt8(targetBlock & 0xFF)]
    }

    /// 嗅探超时 [timeoutMs U16BE]
    static func sniffTimeout(_ timeoutMs: Int) -> [UInt8] { UInt16(timeoutMs).beBytes }

    /// 加载模拟数据 [startBlock, blocks...]
    static func mf1LoadBlockData(startBlock: Int, blocks: [UInt8]) -> [UInt8] {
        [UInt8(startBlock & 0xFF)] + blocks
    }

    /// 设置反冲突数据 [uidLen, uid..., atqa[2] reversed, sak, atsLen, ats...]
    static func mf1SetAntiCollision(uid: [UInt8], atqa: [UInt8], sak: UInt8, ats: [UInt8]) -> [UInt8] {
        var p: [UInt8] = [UInt8(uid.count)]
        p += uid
        p += atqa.reversed().prefix(2)
        p.append(sak)
        p.append(UInt8(ats.count))
        p += ats
        return p
    }

    /// 模拟块数据读取 [startBlock, blockCount]
    static func mf1GetEmulatorBlock(startBlock: Int, blockCount: Int) -> [UInt8] {
        [UInt8(startBlock & 0xFF), UInt8(blockCount & 0xFF)]
    }

    /// 值块操作 [srcKeyType, srcBlock, srcKey[6], op, value I32BE, dstKeyType, dstBlock, dstKey[6]]
    static func mf1ManipulateValueBlock(srcBlock: Int, srcKeyType: UInt8, srcKey: [UInt8], op: UInt8, value: Int32, dstBlock: Int, dstKeyType: UInt8, dstKey: [UInt8]) -> [UInt8] {
        var p: [UInt8] = [srcKeyType, UInt8(srcBlock & 0xFF)] + srcKey.prefix(6)
        p.append(op)
        p += value.beBytes
        p += [dstKeyType, UInt8(dstBlock & 0xFF)] + dstKey.prefix(6)
        return p
    }

    /// 按键配置 [buttonType, mode]
    static func buttonConfig(type: UInt8, mode: UInt8) -> [UInt8] { [type, mode] }

    /// 睡眠超时（秒）
    static func sleepTimeout(_ seconds: Int) -> [UInt8] { [UInt8(seconds & 0xFF)] }

    /// 动画模式
    static func animationMode(_ mode: UInt8) -> [UInt8] { [mode] }
}

extension Int32 {
    var beBytes: [UInt8] {
        [UInt8((UInt32(bitPattern: self) >> 24) & 0xFF), UInt8((UInt32(bitPattern: self) >> 16) & 0xFF),
         UInt8((UInt32(bitPattern: self) >> 8) & 0xFF), UInt8(UInt32(bitPattern: self) & 0xFF)]
    }
}
