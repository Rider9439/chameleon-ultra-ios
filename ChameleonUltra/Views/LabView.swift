import SwiftUI

/// 实验室页：密钥恢复（nested/darkside/mfkey64）、嗅探、字典攻击、轮询出卡
struct LabView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTool = 0
    @State private var logText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Menu {
                    Picker("工具", selection: $selectedTool) {
                        Text("密钥恢复").tag(0)
                        Text("嗅探").tag(1)
                        Text("字典").tag(2)
                        Text("轮询出卡").tag(3)
                        Text("电子围栏").tag(4)
                    }
                } label: {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                        Text(toolTitle)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .padding(10)
                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                }

                ScrollView {
                    switch selectedTool {
                    case 0: recoverySection
                    case 1: sniffSection
                    case 2: dictionarySection
                    case 3: pollingSection
                    default: FenceView()
                    }
                }
            }
            .navigationTitle("实验室")
        }
    }

    private var toolTitle: String {
        switch selectedTool {
        case 0: return "密钥恢复"
        case 1: return "嗅探"
        case 2: return "字典攻击"
        case 3: return "轮询出卡"
        default: return "电子围栏"
        }
    }

    private var logBox: some View {
        Text(logText.isEmpty ? "日志区" : logText)
            .font(.system(.caption, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func appendLog(_ s: String) {
        logText = logText.isEmpty ? s : logText + "\n" + s
    }

    // MARK: - 密钥恢复

    @State private var attackKeyHex = "FFFFFFFFFFFF"
    @State private var attackTargetKeyHex = "FFFFFFFFFFFF"
    @State private var attackKeyType: UInt8 = 0x60
    @State private var isRecovering = false

    private var recoverySection: some View {
        VStack(spacing: 16) {
            PanelCard(title: "Nested 攻击（已知密钥 → 恢复目标密钥）", icon: "key.fill") {
                VStack(spacing: 12) {
                    HexTextField(title: "已知密钥 (12位hex)", text: $attackKeyHex, byteLimit: 6)
                    HexTextField(title: "目标密钥类型 A=60/B=61", text: $attackTargetKeyHex, byteLimit: 6)
                    Picker("目标密钥类型", selection: $attackKeyType) {
                        Text("A").tag(UInt8(0x60))
                        Text("B").tag(UInt8(0x61))
                    }
                    .pickerStyle(.segmented)
                    Button {
                        Task { await runNested() }
                    } label: {
                        Label("开始 Nested 恢复", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRecovering)
                }
            }

            PanelCard(title: "Darkside 攻击（无已知密钥）", icon: "bolt.fill") {
                VStack(spacing: 12) {
                    HexTextField(title: "目标块号", text: $darksideBlockText, byteLimit: 2)
                    Button {
                        Task { await runDarkside() }
                    } label: {
                        Label("开始 Darkside 恢复", systemImage: "bolt.badge.a.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRecovering)
                }
            }

            if isRecovering { LoadingRow(text: "正在收集并破解认证…") }
            logBox
        }
        .padding()
    }

    @State private var darksideBlockText = "0"

    private func runNested() async {
        guard let knownKey = parseKey(attackKeyHex) else {
            appState.report("已知密钥格式错误")
            return
        }
        isRecovering = true
        logText = ""
        defer { isRecovering = false }

        // 1) 先扫描获取 UID
        guard let scan = await appState.device.scan14A(), scan.uid.count >= 4 else {
            appendLog("未发现卡片")
            return
        }
        let uid = beU32(scan.uid)
        appendLog("UID: \(scan.uid.hexPretty)")

        // 2) 发起 nested 采集（需固件支持 mf1NestedAcquire）
        let payload = Payload.mf1NestedAcquire(
            block: 0, keyType: attackKeyType, key: knownKey,
            targetBlock: 0, targetKeyType: attackKeyType
        )
        guard let r = await appState.device.ble.send(.mf1NestedAcquire, data: payload, timeout: 30) else {
            appendLog("采集失败（命令无响应）")
            return
        }
        appendLog("采集状态: \(r.status) 数据 \(r.data.count)B")
        appendLog("（需 3~5 组 nt 记录，固件侧自动采集）")

        // 3) 解析记录并恢复（每组 8B 或 9B：nt[4]|ntEnc[4]|par?）
        let strideLen = r.data.count % 9 == 0 ? 9 : 8
        var recovered: UInt64?
        for i in stride(from: 0, to: r.data.count - strideLen + 1, by: strideLen) {
            let nt = beU32(Array(r.data[i..<i + 4]))
            let ntEnc = beU32(Array(r.data[i + 4..<i + 8]))
            // 弱 nonce：高 16 位可重建完整 nt
            let ntFull = Crypto1.reconstructFullNt(nt & 0xFFFF0000) // 以高 16 位重建
            if let key = KeyRecovery.nested(uid: uid, nt: ntFull, ntEnc: ntEnc, nrEnc: 0, arEnc: 0) {
                recovered = key
                break
            }
        }
        if let key = recovered {
            appendLog("✅ 恢复成功: \(String(format: "%012X", key))")
        } else {
            appendLog("未恢复出密钥（可能需要更多 nt 记录或更换攻击方式）")
        }
    }

    private func runDarkside() async {
        isRecovering = true
        logText = ""
        defer { isRecovering = false }

        guard let scan = await appState.device.scan14A(), scan.uid.count >= 4 else {
            appendLog("未发现卡片")
            return
        }
        let uid = beU32(scan.uid)
        appendLog("UID: \(scan.uid.hexPretty)")

        let block = Int(darksideBlockText) ?? 0
        // darkside 采集：keyType|block|firstRecover|syncMax
        let payload: [UInt8] = [attackKeyType, UInt8(block), 0, 0]
        guard let r = await appState.device.ble.send(.mf1DarksideAcquire, data: payload, timeout: 30) else {
            appendLog("采集失败")
            return
        }
        var data = r.data
        if !data.isEmpty, data[0] == 0 { data.removeFirst() }
        guard data.count >= 32 else {
            appendLog("Darkside 数据不足（错误码 \(r.status)）")
            return
        }
        // 32B: uid[4] | nt1[4] | par[8] | ks1[8] | nr[4] | ar[4]
        let nt1 = beU32(Array(data[4..<8]))
        var par: UInt64 = 0
        for i in 0..<8 { par |= UInt64(data[8 + i]) << (i * 8) }
        var ks: UInt64 = 0
        for i in 0..<8 { ks |= UInt64(data[16 + i]) << (i * 8) }
        let nr = beU32(Array(data[24..<28]))
        let ar = beU32(Array(data[28..<32]))

        appendLog("nt=\(String(format: "%08X", nt1)) nr=\(String(format: "%08X", nr)) ar=\(String(format: "%08X", ar))")
        let keys = KeyRecovery.darkside(uid: uid, nt: nt1, nr: nr, ar: ar, par: par, ks: ks)
        if keys.isEmpty {
            appendLog("未恢复出候选密钥")
        } else {
            for k in keys {
                appendLog("候选密钥: \(String(format: "%012X", k))")
            }
        }
    }

    // MARK: - 嗅探

    @State private var sniffTimeout = 5000
    @State private var isSniffing = false

    private var sniffSection: some View {
        VStack(spacing: 16) {
            PanelCard(title: "HF 嗅探（ISO14443A）", icon: "waveform.path.ecg") {
                VStack(spacing: 12) {
                    Stepper("超时 \(sniffTimeout)ms", value: $sniffTimeout, in: 1000...60000, step: 500)
                    Button {
                        Task { await runHfSniff() }
                    } label: {
                        Label("开始嗅探", systemImage: "record.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSniffing)
                }
            }
            PanelCard(title: "LF 嗅探", icon: "wave.3.left") {
                Button {
                    Task { await runLfSniff() }
                } label: {
                    Label("开始 LF 嗅探", systemImage: "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isSniffing)
            }
            if isSniffing { LoadingRow(text: "嗅探中… 请刷卡") }
            logBox
        }
        .padding()
    }

    private func runHfSniff() async {
        isSniffing = true
        logText = ""
        defer { isSniffing = false }
        let (data, ok) = await appState.device.startHfSniff(timeoutMs: UInt16(sniffTimeout))
        if ok {
            let result = HfSniff.parse(data)
            appendLog("嗅探 \(data.count) 字节")
            if !result.uid.isEmpty { appendLog("UID: \(result.uid.hexPretty)") }
            for auth in result.auths {
                appendLog(auth.isNested ? "嵌套认证: nt=\(String(format: "%08X", auth.nt))" : "认证: nt=\(String(format: "%08X", auth.nt))")
            }
            if result.auths.count >= 2 {
                appendLog("可用 mfkey32 恢复（两段会话）")
            }
        } else {
            appendLog("嗅探超时或无数据")
        }
    }

    private func runLfSniff() async {
        isSniffing = true
        logText = ""
        defer { isSniffing = false }
        let (data, ok) = await appState.device.startLfSniff(timeoutMs: UInt16(sniffTimeout))
        if ok {
            appendLog("LF 嗅探 \(data.count) 字节")
            if data.count >= 5 { appendLog("EM410X 候选: \(Array(data.prefix(5)).hexPretty)") }
        } else {
            appendLog("LF 嗅探超时或无数据")
        }
    }

    // MARK: - 字典

    @State private var dictResult = ""

    private var dictionarySection: some View {
        VStack(spacing: 16) {
            PanelCard(title: "密钥字典攻击", icon: "character.book.closed") {
                VStack(spacing: 12) {
                    Text("内置 \(KeysFile.defaultKeys.count) 个常见密钥 + \(KeysFile.backdoorKeys.count) 个 Gen2 后门密钥")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await runDictionary() }
                    } label: {
                        Label("逐密钥尝试认证", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRecovering)
                }
            }
            if isRecovering { LoadingRow(text: "字典攻击中…") }
            Text(dictResult).font(.footnote)
        }
        .padding()
    }

    private func runDictionary() async {
        isRecovering = true
        dictResult = ""
        defer { isRecovering = false }

        guard let scan = await appState.device.scan14A(), !scan.uid.isEmpty else {
            dictResult = "未发现卡片"
            return
        }
        var allKeys = KeysFile.defaultKeys
        allKeys.append(contentsOf: KeysFile.backdoorKeys)
        for (i, key) in allKeys.enumerated() {
            let (_, ok) = await appState.device.readBlock(block: 0, keyType: 0x60, key: key)
            if ok {
                dictResult = "✅ 第 \(i + 1) 个密钥命中: \(key.hexPretty)"
                return
            }
            if i % 20 == 19 { dictResult = "已尝试 \(i + 1)/\(allKeys.count)…" }
        }
        dictResult = "字典未命中（\(allKeys.count) 个密钥全部尝试）"
    }

    // MARK: - 轮询

    @State private var pollSlotsText = "1,3,5,7"
    @State private var pollHoldText = "1.0"

    private var pollingSection: some View {
        VStack(spacing: 16) {
            PanelCard(title: "轮询式连续出卡", icon: "arrow.triangle.2.circlepath") {
                VStack(spacing: 12) {
                    TextField("卡位列表（逗号分隔，如 1,3,5,7）", text: $pollSlotsText)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("每张卡驻留秒数", text: $pollHoldText)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                    Picker("模式", selection: $pollMode) {
                        Text("循环").tag(PollingManager.Mode.cycle)
                        Text("序列").tag(PollingManager.Mode.sequence)
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Button {
                            startPolling()
                        } label: {
                            Label("开始", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appState.polling.isRunning)

                        Button {
                            appState.polling.stop()
                        } label: {
                            Label("停止", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!appState.polling.isRunning)
                    }
                    if appState.polling.isRunning {
                        Text("当前: 卡位 \(appState.polling.slotList.isEmpty ? "—" : "\(appState.polling.slotList[appState.polling.currentIndex])")")
                            .font(.headline)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding()
    }

    @State private var pollMode: PollingManager.Mode = .cycle

    private func startPolling() {
        let slots = pollSlotsText.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.map { max(0, $0 - 1) }
        guard !slots.isEmpty else {
            appState.report("请输入有效的卡位列表")
            return
        }
        let hold = Double(pollHoldText) ?? 1.0
        appState.polling.mode = pollMode
        appState.polling.configure(slots: slots, hold: hold)
        appState.polling.start()
    }

    // MARK: - 工具

    private func parseKey(_ s: String) -> [UInt8]? {
        let clean = s.filter { $0.isHexDigit }
        guard clean.count == 12 else { return nil }
        var out: [UInt8] = []
        var i = clean.startIndex
        for _ in 0..<6 {
            let end = clean.index(i, offsetBy: 2)
            guard let v = UInt8(clean[i..<end], radix: 16) else { return nil }
            out.append(v)
            i = end
        }
        return out
    }

    private func beU32(_ d: [UInt8]) -> UInt32 {
        guard d.count >= 4 else { return 0 }
        return UInt32(d[0]) << 24 | UInt32(d[1]) << 16 | UInt32(d[2]) << 8 | UInt32(d[3])
    }
}
