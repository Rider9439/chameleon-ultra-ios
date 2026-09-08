import SwiftUI

// MARK: - 通用工具

extension Array where Element == UInt8 {
    var hexPretty: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }
}

// MARK: - 状态徽章

struct StatusBadge: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - 卡片样式容器

struct PanelCard<Content: View>: View {
    var title: String
    var icon: String = "circle.lefthalf.filled"
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            content
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - 十六进制输入框

struct HexTextField: View {
    var title: String
    @Binding var text: String
    var byteLimit: Int?
    var onSubmit: (() -> Void)?

    var body: some View {
        TextField(title, text: $text)
            .font(.system(.body, design: .monospaced))
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .onChange(of: text) { newValue in
                let filtered = newValue.filter { $0.isHexDigit }.uppercased()
                if let limit = byteLimit, filtered.count > limit * 2 {
                    text = String(filtered.prefix(limit * 2))
                } else if filtered != newValue {
                    text = filtered
                }
            }
            .onSubmit { onSubmit?() }
    }
}

// MARK: - 加载指示行

struct LoadingRow: View {
    var text: String = "处理中…"
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(text).font(.footnote)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
