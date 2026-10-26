import Foundation

/// SQL 编辑器的补全引擎。只做前缀匹配，理解"当前位置该补表名还是列名"，不做语法分析。
/// 需求见 R-SQL-05。
public enum SQLCompletion {
    /// 上下文关键字。全部大写，插入时按原样给出。
    public static let keywords: [String] = [
        "SELECT", "FROM", "WHERE", "GROUP BY", "ORDER BY", "HAVING", "LIMIT", "OFFSET",
        "JOIN", "LEFT JOIN", "RIGHT JOIN", "INNER JOIN", "FULL JOIN", "ON", "AS", "AND", "OR", "NOT",
        "IN", "IS", "NULL", "LIKE", "BETWEEN", "CASE", "WHEN", "THEN", "ELSE", "END", "DISTINCT",
        "COUNT", "SUM", "AVG", "MIN", "MAX", "ROUND", "CAST", "COALESCE", "NULLIF",
        "ASC", "DESC", "UNION", "ALL", "WITH", "EXISTS", "UNNEST", "PIVOT", "QUALIFY",
        "DATE_TRUNC", "STRFTIME", "EXTRACT", "RANK", "ROW_NUMBER", "OVER", "PARTITION BY",
        "DESCRIBE", "SUMMARIZE", "SHOW", "TABLES"
    ]

    /// 这些词之后该补表名。
    private static let tableLeadIns: Set<String> = [
        "FROM", "JOIN", "INTO", "TABLE", "USING", "UPDATE"
    ]

    /// 现场：光标前界的词前缀，以及它属于哪种补全。
    public struct Context: Equatable, Sendable {
        /// 已经敲出来的前缀，不含表名部分。
        public let prefix: String
        /// 表名限定符。`data.金额` 里就是 "data"。
        public let qualifier: String?
        /// 补全类别。
        public let kind: Kind

        public enum Kind: Equatable, Sendable {
            case table
            case column
        }

        public init(prefix: String, qualifier: String?, kind: Kind) {
            self.prefix = prefix
            self.qualifier = qualifier
            self.kind = kind
        }
    }

    /// 从光标位置往前读，判断该补什么。光标在字符串字面量或注释里时返回 nil，表示不弹候选。
    public static func context(in text: String, caret: Int, tables: [String]) -> Context? {
        let characters = Array(text)
        guard caret >= 0, caret <= characters.count else { return nil }
        if insideLiteralOrComment(characters, caret: caret) { return nil }

        // 往前吃掉当前的词。字母、数字、下划线、点都算词的一部分。
        var start = caret
        while start > 0, isWordCharacter(characters[start - 1]) {
            start -= 1
        }
        let word = String(characters[start..<caret])
        if word.isEmpty { return nil }

        var prefix = word
        var qualifier: String?
        if let dot = word.lastIndex(of: ".") {
            qualifier = String(word[word.startIndex..<dot])
            prefix = String(word[word.index(after: dot)...])
            // 点后面还没敲字母时，把整张表的所有列都给出来。
            if let qualifier, !tables.contains(qualifier) { return nil }
            return Context(prefix: prefix, qualifier: qualifier, kind: .column)
        }

        // 往前找上一个词，判断是不是 FROM / JOIN 这类位置。
        var index = start
        while index > 0, characters[index - 1].isWhitespace || characters[index - 1] == "(" || characters[index - 1] == "," {
            index -= 1
        }
        let previous = previousWord(characters, end: index)
        if tableLeadIns.contains(previous) {
            return Context(prefix: prefix, qualifier: nil, kind: .table)
        }
        // 列名与关键字都给，让用户自己挑。
        return Context(prefix: prefix, qualifier: nil, kind: .column)
    }

    /// 按前缀算候选。前缀为空时返回空，避免刚敲一个点就刷一屏。
    public static func candidates(
        context: Context,
        columns: [String],
        tables: [String],
        limit: Int = 50
    ) -> [String] {
        guard !context.prefix.isEmpty else { return [] }
        let pool: [String]
        switch context.kind {
        case .table:
            pool = tables
        case .column:
            // 有表名限定时只补这一张表的列。
            pool = context.qualifier == nil ? keywords + columns : columns
        }
        let lowered = context.prefix.lowercased()
        var seen = Set<String>()
        var starts: [String] = []
        var contains: [String] = []
        for item in pool {
            let key = item.lowercased()
            guard !seen.contains(key) else { continue }
            // 已经完整敲出来的词不再作为候选：否则接受补全后弹窗会立刻重开，Tab 也被挡住。
            guard key != lowered else { continue }
            guard key.hasPrefix(lowered) else {
                if key.contains(lowered) { contains.append(item) }
                continue
            }
            seen.insert(key)
            starts.append(item)
        }
        // 前缀命中的排在包含命中的前面，同类保持原有顺序（关键字在前，列名在后）。
        return Array((starts + contains).prefix(limit))
    }

    /// 接受候选时把词前缀替换掉，返回新的文本和新的光标位置。
    public static func apply(
        candidate: String,
        to text: String,
        caret: Int
    ) -> (text: String, caret: Int)? {
        let characters = Array(text)
        guard caret >= 0, caret <= characters.count else { return nil }
        var start = caret
        while start > 0, isWordCharacter(characters[start - 1]) {
            // 表名限定符保留，只替换点后面的部分。
            if characters[start - 1] == "." { break }
            start -= 1
        }
        // 候选里带空格的关键字（GROUP BY）插进去后补一个空格，省得再敲。
        let insertion = candidate.contains(" ") ? candidate + " " : candidate
        var result = String(characters[0..<start]) + insertion
        let newCaret = result.count
        result += String(characters[caret...])
        return (result, newCaret)
    }

    /// 光标是否在 '...'、"..." 或 -- 注释里。
    static func insideLiteralOrComment(_ characters: [Character], caret: Int) -> Bool {
        var single = false
        var double = false
        var index = 0
        while index < caret {
            let character = characters[index]
            if character == "'" && !double { single.toggle() }
            if character == "\"" && !single { double.toggle() }
            if !single && !double && character == "-" && index + 1 < caret && characters[index + 1] == "-" {
                // 行注释一直到行尾。
                var scan = index
                while scan < caret {
                    if characters[scan] == "\n" { break }
                    scan += 1
                }
                if scan >= caret { return true }
                index = scan
                continue
            }
            index += 1
        }
        return single || double
    }

    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "."
    }

    /// 从 end 往前读一个词，返回大写形式。读不到返回空串。
    static func previousWord(_ characters: [Character], end: Int) -> String {
        var index = end
        while index > 0, characters[index - 1].isWhitespace { index -= 1 }
        var start = index
        while start > 0, characters[start - 1].isLetter { start -= 1 }
        return String(characters[start..<index]).uppercased()
    }
}

