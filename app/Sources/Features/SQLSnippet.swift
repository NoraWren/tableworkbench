import Foundation
import Combine

public struct SQLSnippet: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var sql: String
    public var date: Date

    public init(id: UUID = UUID(), name: String, sql: String, date: Date = Date()) {
        self.id = id
        self.name = name
        self.sql = sql
        self.date = date
    }
}

public final class SQLSnippetStore: ObservableObject {
    @Published public private(set) var entries: [SQLSnippet] = []

    private let defaults: UserDefaults
    private let key: String
    private let limit = 200

    public init(defaults: UserDefaults = .standard, key: String = "sqlSnippets") {
        self.defaults = defaults
        self.key = key
        load()
    }

    public func save(name: String, sql: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSQL = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedSQL.isEmpty else { return }

        let normalized = trimmedName.lowercased()
        entries.removeAll { $0.name.lowercased() == normalized }
        entries.insert(SQLSnippet(name: trimmedName, sql: trimmedSQL), at: 0)
        if entries.count > limit {
            entries = Array(entries.prefix(limit))
        }
        saveDefaults()
    }

    public func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        saveDefaults()
    }

    public func clear() {
        entries.removeAll()
        defaults.removeObject(forKey: key)
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SQLSnippet].self, from: data) else {
            return
        }
        entries = Array(decoded.prefix(limit))
    }

    private func saveDefaults() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }
}
