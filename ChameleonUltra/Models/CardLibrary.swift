import Foundation

/// 卡库条目：保存已读/已克隆的卡片（IC 或 ID）
struct CardLibraryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var createdAt = Date()

    // 通用
    var bank: String           // "IC" / "ID"
    var tagTypeName: String    // "Mifare 1K" / "EM410X" ...
    var uidHex: String
    var uidBytes: [UInt8]      // 便于 14A 反冲突或 LF 卡号

    // IC（Mifare Classic）
    var blocks: [Int: [UInt8]] = [:]   // 块号 → 16 字节
    var keyA: [UInt8]?
    var keyB: [UInt8]?

    // LF
    var lfData: [UInt8] = []

    var isIc: Bool { bank == "IC" }

    var summary: String {
        isIc ? "\(tagTypeName) \(uidHex.prefix(8))…" : "\(tagTypeName) \(uidHex)"
    }
}

/// 卡库管理器（本地持久化）
final class CardLibrary: ObservableObject {
    @Published var entries: [CardLibraryEntry] = []

    private static let storageKey = "card_library_v1"

    init() {
        load()
    }

    func add(_ entry: CardLibraryEntry) {
        entries.insert(entry, at: 0)
        save()
    }

    func update(_ entry: CardLibraryEntry) {
        if let i = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[i] = entry
            save()
        }
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func duplicate(_ entry: CardLibraryEntry) {
        var copy = entry
        copy.id = UUID()
        copy.name = entry.name + " (副本)"
        entries.insert(copy, at: 0)
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([CardLibraryEntry].self, from: data)) ?? []
    }

    // MARK: - 常用构造

    static func makeIcEntry(name: String, tagTypeName: String, uid: [UInt8], blocks: [Int: [UInt8]], keyA: [UInt8]?, keyB: [UInt8]?) -> CardLibraryEntry {
        CardLibraryEntry(
            name: name,
            bank: "IC",
            tagTypeName: tagTypeName,
            uidHex: uid.map { String(format: "%02X", $0) }.joined(),
            uidBytes: uid,
            blocks: blocks,
            keyA: keyA,
            keyB: keyB
        )
    }

    static func makeIdEntry(name: String, tagTypeName: String, uid: [UInt8]) -> CardLibraryEntry {
        CardLibraryEntry(
            name: name,
            bank: "ID",
            tagTypeName: tagTypeName,
            uidHex: uid.map { String(format: "%02X", $0) }.joined(),
            uidBytes: uid,
            lfData: uid
        )
    }
}
