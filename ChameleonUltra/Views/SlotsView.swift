import SwiftUI

/// 卡槽页：32 卡位（16 IC + 16 ID）管理
struct SlotsView: View {
    @EnvironmentObject var appState: AppState

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
                Text("16 个 IC 卡位 + 16 个 ID 卡位：IC 位 i 与 ID 位 i 共用物理槽 i 的 HF/LF 面（\(appState.device.capabilities.slotCount) 槽固件）。")
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
