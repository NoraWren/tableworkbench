import Foundation

public enum TSVBuilder {
    public static func escape(_ value: String) -> String {
        if value.contains("\t") || value.contains("\n") || value.contains("\r") || value.contains("\"") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    public static func build(rows: [[String?]], columns: [String], includeHeader: Bool) -> String {
        var lines: [String] = []
        if includeHeader {
            lines.append(columns.map(escape).joined(separator: "\t"))
        }
        for row in rows {
            lines.append(row.map { escape($0 ?? "") }.joined(separator: "\t"))
        }
        return lines.joined(separator: "\n")
    }
}
