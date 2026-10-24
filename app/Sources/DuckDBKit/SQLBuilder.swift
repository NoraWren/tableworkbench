import Foundation

public enum SQLBuilder {
    public static func quoteIdentifier(_ name: String) -> String {
        "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    public static func escapeLiteral(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    /// 数字直接拼，其他值加引号。数字判断只接受完整的数字字符串，避免注入。
    public static func literal(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, Double(trimmed) != nil {
            return trimmed
        }
        return "'\(escapeLiteral(value))'"
    }

    public static func orderBy(_ sort: [SortSpec]) -> String {
        guard !sort.isEmpty else { return "" }
        let terms = sort.map { spec in
            "\(quoteIdentifier(spec.column)) \(spec.ascending ? "ASC" : "DESC")"
        }
        return "ORDER BY " + terms.joined(separator: ", ")
    }

    public static func whereClause(_ group: FilterGroup?) -> String {
        guard let group else { return "" }
        let parts = group.conditions.compactMap(conditionSQL)
        guard !parts.isEmpty else { return "" }
        let joined = parts.joined(separator: group.join == .and ? " AND " : " OR ")
        return "WHERE " + (parts.count > 1 ? "(\(joined))" : joined)
    }

    public static func conditionSQL(_ condition: FilterCondition) -> String? {
        let column = quoteIdentifier(condition.column)
        switch condition.op {
        case .isNull:
            return "\(column) IS NULL"
        case .isNotNull:
            return "\(column) IS NOT NULL"
        case .equal:
            return "\(column) = \(literal(condition.value))"
        case .notEqual:
            return "\(column) <> \(literal(condition.value))"
        case .contains:
            return "contains(CAST(\(column) AS VARCHAR), '\(escapeLiteral(condition.value))')"
        case .greaterThan:
            return "\(column) > \(literal(condition.value))"
        case .lessThan:
            return "\(column) < \(literal(condition.value))"
        case .between:
            guard let second = condition.secondValue, !second.isEmpty else { return nil }
            return "\(column) BETWEEN \(literal(condition.value)) AND \(literal(second))"
        }
    }

    public static func columnList(_ columns: [ColumnInfo]) -> String {
        columns.map { quoteIdentifier($0.name) }.joined(separator: ", ")
    }

    public static func selectList(_ columns: [ColumnInfo]) -> String {
        columns.map { "CAST(\(quoteIdentifier($0.name)) AS VARCHAR)" }.joined(separator: ", ")
    }
}
