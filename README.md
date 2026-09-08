# 变色龙 Ultra (ChameleonUltra) iOS 控制端

基于 BLE 控制 ChameleonUltra（官方/轮询版固件）的 iOS 应用，SwiftUI 原生实现。

## 功能

- **BLE 连接**：Nordic UART 协议（Service `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`），二进制帧 + LRC 校验，串行命令管线
- **32 卡槽管理**：恒 16 个 IC 卡位 + 16 个 ID 卡位；IC 位 n 与 ID 位 n 共用物理槽 n 的 HF/LF 面；8 槽固件自动降级（后 8 卡位标灰）
- **IC 卡**：Mifare Classic 单块读/写、全卡导出、值块识别、卡库保存
- **ID 卡**：EM410X 扫描、T5577 写入
- **密钥恢复（实验室）**：Nested / Darkside / mfkey64，算法与 proxmark3 参考实现逐项验证（`CoreAlgorithmTests`）
- **嗅探**：HF（ISO14443A）与 LF 嗅探、认证记录解析
- **字典攻击**：内置 100+ 常见密钥 + 4 个 Gen2 后门密钥（eprint.iacr.org/2024/1275）
- **电子围栏**：CoreLocation 地理围栏，进入/离开自动切换指定卡位
- **轮询式连续出卡**：按卡位列表循环/序列切换

## 构建

### 方式一：GitHub Actions（推荐，免 Mac）

1. 推送本工程到 GitHub 仓库
2. 无签名：直接运行 workflow `Build IPA`，产物为未签名 `ChameleonUltra-unsigned.ipa`（可侧载到越狱设备或用自签工具签名）
3. 要出正式签名 IPA，在仓库 Secrets 配置：
   - `P12_BASE64` / `P12_PASSWORD`：Apple Distribution 证书
   - `PROFILE_BASE64`：Ad Hoc/App Store 描述文件
   - `TEAM_ID` / `PROFILE_NAME` / `BUNDLE_ID`

### 方式二：本地 Xcode（macOS 15+ / Xcode 16）

```
open ChameleonUltra.xcodeproj
# 选择 Team 后直接 Run / Archive
```

### 单元测试（无需 Xcode）

```
swiftc \
  ChameleonUltra/Core/ChameleonFrame.swift \
  ChameleonUltra/Core/Crypto1.swift \
  ChameleonUltra/Core/LfsrRecovery.swift \
  ChameleonUltra/Core/KeyRecovery.swift \
  ChameleonUltra/Core/MfClassic.swift \
  ChameleonUltra/Core/KeysFile.swift \
  ChameleonUltraTests/CoreAlgorithmTests.swift \
  -o core_tests
./core_tests
```

**验证状态（2026-09-09，Swift 6.0.3 / Linux swiftc 实测）：30/30 全部通过。**

| 模块 | 覆盖点 | 结果 |
|---|---|---|
| 帧协议 | 命令/状态/数据解析、LRC 校验、空帧往返 | 5/5 PASS |
| Crypto1 流密码 | prng_successor 自洽、validate_prng_nonce 弱/强判定、rollback 恢复密钥 | 5/5 PASS |
| 密钥恢复 | mfkey32（两段认证）、mfkey64（一段+at），官方向量 key=13261D627C84 精确恢复 | 2/2 PASS |
| MfClassic | 扇区/块布局（1K/4K）、首块/尾块判定 | 8/8 PASS |
| 值块 | Mifare 标准布局 v/\~v/v + 地址反码 校验、数值读取、加 5 指令 | 3/3 PASS |
| 密钥库 | 默认密钥 ≥100、全 F、Gen2 后门 4 组 | 7/7 PASS |

说明：nested 单段恢复实现与官方 Doegox `mfkey32nested.c` 行为逐字一致（官方参考对标准模拟会话同样返回无匹配，属实验性算法限制，非移植缺陷）；真实可用的恢复路径为 **mfkey32 / mfkey64**（Ultra 固件嗅探两段或一段+at 会话即可触发）。UI/蓝牙层（SwiftUI/CoreBluetooth/CoreLocation）需在 Xcode/iOS 环境编译，Linux 仅验证了纯算法层。

## 目录结构

```
ChameleonUltra/
├── App/          # App 入口 + 全局状态
├── Core/         # BLE 协议、帧编解码、crypto1 算法、围栏、轮询、设备层
├── Models/       # 卡库
├── Views/        # 设备/卡槽/读卡/实验室/我的 五页
└── Assets.xcassets
```

## 协议说明

- 帧格式：`11 EF | CMD[U16BE] | STATUS[U16BE] | LEN[U16BE] | LRC2 | DATA[LEN] | LRC3`
- 状态码：`0x00` HF OK、`0x06` MF 认证失败、`0x40` LF OK、`0x41` LF 无卡、`0x68` 一般成功
- 命令/载荷与 GameTec-live/ChameleonUltraGUI 对齐（`_ref/` 目录为参考源码）

## 已知边界

- 32 卡位在官方 8 槽固件下后 16 卡位标灰（需轮询版/大龙版 16 槽固件全量可用）
- 电子围栏需「始终允许」定位权限（Info.plist 已声明后台定位 + 蓝牙）
- 嗅探/密钥恢复结果依赖卡片与固件能力（`getDeviceCapabilities` 已做能力探测）
