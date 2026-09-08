import SwiftUI

/// 我的页：应用信息、设置、说明
struct ProfileView: View {
    @EnvironmentObject var appState: AppState

    @State private var showAbout = false
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("设备") {
                    HStack {
                        Label("型号", systemImage: "cpu")
                        Spacer()
                        Text(appState.device.capabilities.modelName)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("固件版本", systemImage: "shippingbox")
                        Spacer()
                        Text(appState.device.capabilities.firmwareVersion)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("物理卡槽", systemImage: "square.grid.3x3")
                        Spacer()
                        Text("\(appState.device.capabilities.slotCount) 槽（\(appState.device.capabilities.slotCount >= 16 ? "32 卡位全可用" : "后 16 卡位需 16 槽固件")）")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("卡库") {
                    HStack {
                        Label("已保存卡片", systemImage: "books.vertical")
                        Spacer()
                        Text("\(appState.library.entries.count)")
                            .foregroundStyle(.secondary)
                    }
                    if !appState.library.entries.isEmpty {
                        Button("清空卡库", role: .destructive) {
                            showResetConfirm = true
                        }
                    }
                }

                Section("关于") {
                    LabeledContent("应用", value: "变色龙 Ultra")
                    LabeledContent("版本", value: "1.0.0")
                    LabeledContent("BLE 协议", value: "官方二进制帧 + 32 卡位映射")
                    Button("开源参考") {
                        showAbout = true
                    }
                }
            }
            .navigationTitle("我的")
            .alert("清空卡库？", isPresented: $showResetConfirm) {
                Button("清空", role: .destructive) {
                    for entry in appState.library.entries {
                        appState.library.remove(entry.id)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将删除全部已保存的卡片数据，不可恢复")
            }
            .sheet(isPresented: $showAbout) {
                aboutSheet
            }
        }
    }

    private var aboutSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("变色龙 Ultra (ChameleonUltra) iOS 控制端")
                        .font(.headline)
                    Text("""
                    支持：
                    · BLE 连接（Nordic UART 协议，二进制帧 + LRC 校验）
                    · 32 卡槽管理（16 IC + 16 ID 逻辑卡位）
                    · IC 卡：Mifare Classic 读写、值块、全卡导出
                    · ID 卡：EM410X 扫描、T5577 写入
                    · 密钥恢复：Nested / Darkside / mfkey64（算法与 proxmark3 参考实现逐项验证）
                    · HF/LF 嗅探、密钥字典攻击
                    · 电子围栏自动切换卡槽（CoreLocation）
                    · 轮询式连续出卡
                    """)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("算法参考：RfidResearchGroup/proxmark3 · GameTec-live/ChameleonUltraGUI")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showAbout = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
