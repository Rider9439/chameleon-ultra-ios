import SwiftUI

/// 读卡页：IC（Mifare）读卡 + ID（EM410X）读卡 + 卡库
struct ReaderView: View {
    @EnvironmentObject var appState: AppState
    @State private var keyHex = "FFFFFFFFFFFF"
    @State private var keyType: UInt8 = 0x60
    @State private var blockToRead = 0
    @State private var isReading = false
    @State private var resultText = ""
    @State private var lastIdUid: [UInt8] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    connectionHint
                    icReadCard
                    idReadCard
                    libraryCard
                }
                .padding()
            }
            .navigationTitle("读卡")
        }
    }

    private var connectionHint: some View {
        HStack {
            StatusBadge(text: appState.device.ble.isConnected ? "设备已连接" : "请先在「设备」页连接",
                        color: appState.device.ble.isConnected ? .green : .orange)
            Spacer()
        }
    }

    // MARK: IC 读卡

    private var icReadCard: some View {
        PanelCard(title: "IC 卡（Mifare Classic）", icon: "wave.3.right.circle") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Picker("密钥类型", selection: $keyType) {
                        Text("A").tag(UInt8(0x60))
                        Text("B").tag(UInt8(0x61))
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)

                    HexTextField(title: "密钥 (12位hex)", text: $keyHex, byteLimit: 6)
                }

                Stepper("块号: \(blockToRead)", value: $blockToRead, in: 0...63)

                HStack(spacing: 12) {
                    Button {
                        Task { await readSingleBlock() }
                    } label: {
                        Label("读单块", systemImage: "arrow.down.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isReading)

                    Button {
                        Task { await dumpAndSave() }
                    } label: {
                        Label("全卡导出", systemImage: "tray.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isReading)
                }

                if isReading {
                    LoadingRow(text: "读取中…")
                }
                if !resultText.isEmpty {
                    Text(resultText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func readSingleBlock() async {
        guard let key = parseKey(keyHex) else {
            appState.report("密钥需要 6 字节（12 位十六进制）")
            return
        }
        isReading = true
        resultText = ""
        defer { isReading = false }

        let scan = await appState.device.scan14A()
        let uid = scan?.uid ?? []
        // 等待固件切换/就绪
        try? await Task.sleep(nanoseconds: 200_000_000)
        let (data, ok) = await appState.device.readBlock(block: blockToRead, keyType: keyType, key: key)
        if ok {
            var lines = ["块 \(blockToRead) (密钥\(keyType == 0x60 ? "A" : "B")): \(data.hexPretty)"]
            if !uid.isEmpty {
                lines.append("UID: \(uid.hexPretty)")
                // 尝试识别值块
                if MfClassic.isValidValueBlock(data),
                   let v = MfClassic.valueBlockValue(data) {
                    lines.append("值块: \(v)")
                }
            }
            resultText = lines.joined(separator: "\n")
        } else {
            resultText = uid.isEmpty
                ? "未发现卡片：请将 IC 卡贴近设备背面天线"
                : "读取失败（认证失败或密钥错误）"
        }
    }

    private func dumpAndSave() async {
        guard let key = parseKey(keyHex) else {
            appState.report("密钥需要 6 字节（12 位十六进制）")
            return
        }
        isReading = true
        resultText = ""
        defer { isReading = false }

        guard let scan = await appState.device.scan14A(), !scan.uid.isEmpty else {
            resultText = "未发现卡片：请将 IC 卡贴近设备背面天线"
            return
        }
        var blocks: [Int: [UInt8]] = [:]
        var failed = 0
        for block in 0..<64 where MfClassic.isDataBlock(block: block) {
            // 每块之间留 80ms，避免固件连续读卡掉卡
            try? await Task.sleep(nanoseconds: 80_000_000)
            let (data, ok) = await appState.device.readBlock(block: block, keyType: keyType, key: key)
            if ok { blocks[block] = data } else { failed += 1 }
        }
        let entry = CardLibrary.makeIcEntry(
            name: "Mifare \(scan.uid.hexPretty)",
            tagTypeName: "Mifare 1K",
            uid: scan.uid,
            blocks: blocks,
            keyA: keyType == 0x60 ? key : nil,
            keyB: keyType == 0x61 ? key : nil
        )
        appState.library.add(entry)
        resultText = "已导出 \(blocks.count) 块，失败 \(failed) 块，已存入卡库"
    }

    // MARK: ID 读卡

    private var idReadCard: some View {
        PanelCard(title: "ID 卡（EM410X）", icon: "antenna.radiowaves.left.and.right.circle") {
            VStack(spacing: 12) {
                HStack {
                    Button {
                        Task { await scanId() }
                    } label: {
                        Label("扫描 ID 卡", systemImage: "wave.3.left")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isReading)

                    Button {
                        Task { await writeIdToT5577() }
                    } label: {
                        Label("写入 T5577", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isReading || lastIdUid.isEmpty)
                }

                if !lastIdUid.isEmpty {
                    Text("当前 ID: \(lastIdUid.hexPretty)")
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
    }


    private func scanId() async {
        isReading = true
        defer { isReading = false }
        let (uid, ok) = await appState.device.scanEM410X()
        if ok {
            lastIdUid = uid
            resultText = "ID 卡号: \(uid.hexPretty)"
            appState.library.add(CardLibrary.makeIdEntry(name: "EM410X \(uid.hexPretty)", tagTypeName: "EM410X", uid: uid))
        } else {
            resultText = "未发现 ID 卡"
        }
    }

    private func writeIdToT5577() async {
        guard !lastIdUid.isEmpty else { return }
        isReading = true
        defer { isReading = false }
        let ok = await appState.device.writeEM410XToT5577(uid: lastIdUid)
        resultText = ok ? "已写入 T5577" : "写入失败"
    }

    // MARK: 卡库

    private var libraryCard: some View {
        PanelCard(title: "卡库（\(appState.library.entries.count)）", icon: "books.vertical") {
            if appState.library.entries.isEmpty {
                Text("尚未保存卡片，读卡后自动入库")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.library.entries) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.name).font(.subheadline)
                            Text(entry.summary).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(entry.bank)
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(entry.isIc ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15),
                                        in: Capsule())
                            .foregroundStyle(entry.isIc ? .blue : .orange)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: 工具

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
}
