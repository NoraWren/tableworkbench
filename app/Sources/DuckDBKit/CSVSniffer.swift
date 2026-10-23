import Foundation

public struct CSVFormat: Sendable, Equatable {
    public let delimiter: Character
    public let hasHeader: Bool

    public init(delimiter: Character, hasHeader: Bool) {
        self.delimiter = delimiter
        self.hasHeader = hasHeader
    }
}

public enum CSVSniffer {
    /// 用前几行判断分隔符：逗号、制表符、分号里选每行列数最一致的那个。
    public static func sniff(sample: String, fileExtension: String) -> CSVFormat {
        let lines = sample
            .split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(8)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let first = lines.first else {
            return CSVFormat(delimiter: fileExtension.lowercased() == "tsv" ? "\t" : ",", hasHeader: true)
        }

        let candidates: [Character] = fileExtension.lowercased() == "tsv" ? ["\t", ",", ";"] : [",", "\t", ";"]
        var best: (Character, Int) = (candidates[0], -1)
        for candidate in candidates {
            let counts = lines.prefix(5).map { split($0, delimiter: candidate).count }
            guard let head = counts.first, head > 1 else { continue }
            let consistent = counts.allSatisfy { $0 == head }
            let score = (consistent ? 1000 : 0) + head
            if score > best.1 { best = (candidate, score) }
        }

        let delimiter = best.0
        return CSVFormat(delimiter: delimiter, hasHeader: detectHeader(first, delimiter: delimiter))
    }

    public static func detectHeader(_ line: String, delimiter: Character) -> Bool {
        let fields = split(line, delimiter: delimiter)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !fields.isEmpty else { return true }
        let numeric = fields.filter { Double($0) != nil || Int64($0) != nil }.count
        return numeric < fields.count
    }

    /// 处理双引号包裹的字段，用于表头判断，不做完整 CSV 解析。
    public static func split(_ line: String, delimiter: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        while let char = iterator.next() {
            if char == "\"" {
                if inQuotes {
                    if let next = iterator.next() {
                        if next == "\"" {
                            current.append("\"")
                        } else {
                            inQuotes = false
                            if next == delimiter {
                                fields.append(current)
                                current = ""
                            } else {
                                current.append(next)
                            }
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            } else if char == delimiter && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }

    public static func sanitizeColumnNames(_ rawNames: [String]) -> [String] {
        var seen: [String: Int] = [:]
        var result: [String] = []
        for (index, raw) in rawNames.enumerated() {
            var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            while name.contains("  ") {
                name = name.replacingOccurrences(of: "  ", with: " ")
            }
            name = name.replacingOccurrences(of: " ", with: "_")
            name = String(name.map { char -> Character in
                if char.isLetter || char.isNumber || char == "_" {
                    return char
                }
                return "_"
            })
            while name.contains("__") {
                name = name.replacingOccurrences(of: "__", with: "_")
            }
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            if name.isEmpty { name = "column_\(index + 1)" }
            if let count = seen[name] {
                seen[name] = count + 1
                name = "\(name)_\(count + 1)"
            } else {
                seen[name] = 1
            }
            result.append(name)
        }
        return result
    }
}
