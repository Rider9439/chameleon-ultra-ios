import SwiftUI

/// 卡槽页：32 卡位（16 IC + 16 ID）管理，支持手动添加/清空卡片
struct SlotsView: View {
    @EnvironmentObject var appState: AppState

    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header

                    // IC 卡位
                    bankSection(bank: .ic, title: "IC 卡位（HF · Mifare/NTAG）", icon: "wave.3.right")
                    // ID 卡位
                    bankSection(bank: .id, title: "ID 卡位（LF · EM410X 等）", icon: "antenna.radiowaves.left.and.right")
                }
                .padding()
            }
            .navigationTitle("卡槽")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        guard appState.device.ble.isConnected else {
                            appState.report("请先连接设备")
                            return
                        }
                        showAddSheet = true
                    } label: {
                        Label("添加卡片", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddCardSheet(onDone: { msg in
                    appState.report(msg)
                })
            }
        }
    }

    private var header: some View {
        PanelCard(title: "32 卡槽概览", icon: "square.grid.3x3") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    StatusBadge(text: appState.device.ble.isConnected ? "已连接" : "未连接",
                                color: appState.device.ble.isConnected ? .green : .red)
                    Spacer()
                    if appState.device.ble.isConnected {
                        Button("刷新") {
                            Task { _ = await appState.device.refreshSlots() }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Text("16 个 IC 卡位 + 16 个 ID 卡位：IC 位 i 与 ID 位 i 共用物理槽 i 的 HF/LF 面（\(appState.device.capabilities.slotCount) 槽固件）。长按卡位可清空该卡。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bankSection(bank: LogicalSlot.Bank, title: String, icon: String) -> some View {
        PanelCard(title: title, icon: icon) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(appState.device.logicalSlots.filter { $0.bank == bank }) { slot in
                    slotCell(slot)
                }
            }
        }
    }

    private func slotCell(_ slot: LogicalSlot) -> some View {
        let isActive = appState.device.activeSlot == slot.physicalSlot
        let enabled = slot.available && (appState.device.enabledSlots.indices.contains(slot.physicalSlot)
                                         ? appState.device.enabledSlots[slot.physicalSlot] : false)
        let typeName = slot.available && appState.device.slotTypes.indices.contains(slot.physicalSlot)
            ? appState.device.slotTypes[slot.physicalSlot].displayName : "空"

        return Button {
            guard slot.available else { return }
            Task {
                _ = await appState.device.activateSlot(bank: slot.bank, number: slot.number)
            }
        } label: {
            VStack(spacing: 4) {
                Text("\(slot.bank.rawValue)\(slot.number + 1)")
                    .font(.subheadline.bold())
                Text(typeName)
                    .font(.caption2)
                    .lineLimit(1)
                if let nick = slotNick(slot), !nick.isEmpty {
                    Text(nick)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(.teal)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(backgroundFor(slot: slot, isActive: isActive, enabled: enabled))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(borderFor(slot: slot, isActive: isActive), lineWidth: isActive ? 2 : 1)
            )
            .opacity(slot.available ? 1 : 0.35)
            .foregroundStyle(slot.available ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(!slot.available)
        .contextMenu {
            if slot.available && enabled {
                Button(role: .destructive) {
                    Task {
                        let freq: TagFrequency = slot.bank == .ic ? .hf : .lf
                        let ok = await appState.device.clearSlot(physicalSlot: slot.physicalSlot, frequency: freq)
                        appState.report(ok ? "已清空 \(slot.displayName)" : "清空失败")
                    }
                } label: {
                    Label("清空此卡", systemImage: "trash")
                }
            }
        }
    }

    private func slotNick(_ slot: LogicalSlot) -> String? {
        guard slot.available, appState.device.slotNicks.indices.contains(slot.physicalSlot) else { return nil }
        return appState.device.slotNicks[slot.physicalSlot]
    }

    private func backgroundFor(slot: LogicalSlot, isActive: Bool, enabled: Bool) -> Color {
        if isActive { return Color.accentColor.opacity(0.25) }
        if enabled { return Color(.tertiarySystemBackground) }
        return Color(.secondarySystemBackground)
    }

    private func borderFor(slot: LogicalSlot, isActive: Bool) -> Color {
        isActive ? .accentColor : (slot.available ? .gray.opacity(0.3) : .gray.opacity(0.15))
    }
}

// MARK: - 添加卡片表单

private struct AddCardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    var onDone: (String) -> Void

    @State private var bank: LogicalSlot.Bank = .ic
    @State private var slotNumber = 1
    @State private var icType: TagType = .mifare1K
    @State private var uidHex = ""
    @State private var saving = false

    private let icTypes: [TagType] = [.mifareMini, .mifare1K, .mifare2K, .mifare4K, .ntag213, .ntag215, .ntag216]
    private let idTypes: [TagType] = [.em410X, .em410X16, .em410X32, .hidProx]

    var body: some View {
        NavigationStack {
            Form {
                Section("卡片类型") {
                    Picker("IC / ID", selection: $bank) {
                        Text("IC 卡（高频）").tag(LogicalSlot.Bank.ic)
                        Text("ID 卡（低频）").tag(LogicalSlot.Bank.id)
                    }
                    .pickerStyle(.segmented)

                    Picker("卡类型", selection: $icType) {
                        ForEach(bank == .ic ? icTypes : idTypes, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                }

                Section("放置位置") {
                    Picker("卡位", selection: $slotNumber) {
                        ForEach(1...16, id: \.self) { n in
                            Text("\(bank.rawValue)卡位 \(n)").tag(n)
                        }
                    }
                }

                if bank == .ic {
                    Section("UID（可选）") {
                        HexTextField(title: "自定义 UID（4/7/10 字节 hex，留空用默认）",
                                     text: $uidHex, byteLimit: 10)
                    }
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        } else {
                            Text("保存到卡槽").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(saving)
                } footer: {
                    Text("添加后该卡位即启用，靠近读卡器即可模拟。IC 卡默认使用该类型的默认 UID；ID 卡默认使用 EM410X 全零序列。")
                }
            }
            .navigationTitle("添加卡片")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let number = slotNumber - 1
        if bank == .ic {
            let ok = await appState.device.addIcCard(number: number, type: icType, uidHex: uidHex)
            onDone(ok ? "已添加 \(icType.displayName) 到 IC卡位 \(slotNumber)" : (appState.device.lastError ?? "添加失败"))
        } else {
            let ok = await appState.device.addIdCard(number: number, uidHex: nil)
            onDone(ok ? "已添加 ID 卡到 ID卡位 \(slotNumber)" : (appState.device.lastError ?? "添加失败"))
        }
        dismiss()
    }
}
