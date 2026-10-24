import Foundation
import Combine

public struct SQLHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let sql: String
    public let date: Date

    public init(id: UUID = UUID(), sql: String, date: Date = Date()) {
        self.id = id
        self.sql = sql
        self.date = date
    }
}

public final class SQLHistoryStore: ObservableObject {
    @Published public private(set) var entries: [SQLHistoryEntry] = []

    private let defaults: UserDefaults
    private let key: String
    private let limit = 200

    public init(defaults: UserDefaults = .standard, key: String = "sqlHistory") {
        self.defaults = defaults
        self.key = key
        load()
    }

    public func record(_ sql: String) {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if entries.first?.sql == trimmed { return }

        entries.removeAll { $0.sql == trimmed }
        entries.insert(SQLHistoryEntry(sql: trimmed), at: 0)
        if entries.count > limit {
            entries = Array(entries.prefix(limit))
        }
        save()
    }

    public func search(_ query: String) -> [SQLHistoryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { $0.sql.localizedCaseInsensitiveContains(trimmed) }
    }

    public func clear() {
        entries.removeAll()
        defaults.removeObject(forKey: key)
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SQLHistoryEntry].self, from: data) else {
            return
        }
        entries = Array(decoded.prefix(limit))
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }
}
