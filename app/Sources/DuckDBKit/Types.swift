import Foundation

/// 列的语义类型，只影响对齐和后续格式化，不参与查询。
public enum ColumnKind: String, Sendable {
    case text
    case integer
    case double
    case boolean
    case date
    case timestamp

    public static func infer(fromTypeName typeName: String) -> ColumnKind {
        let t = typeName.uppercased()
        if t.contains("TIMESTAMP") { return .timestamp }
        if t == "DATE" { return .date }
        if t.contains("BOOL") { return .boolean }
        if t.contains("DECIMAL") || t.contains("DOUBLE") || t.contains("FLOAT") || t.contains("REAL") {
            return .double
        }
        if t.contains("INT") || t.contains("HUGEINT") { return .integer }
        return .text
    }

    public var isNumeric: Bool {
        self == .integer || self == .double
    }
}

/// 一列的元信息。name 是查询用的原始名，displayName 是清洗后的显示名。
public struct ColumnInfo: Hashable, Sendable {
    public let name: String
    public let displayName: String
    public let typeName: String
    public let kind: ColumnKind
    public let isComputed: Bool

    public init(
        name: String,
        displayName: String,
        typeName: String,
        kind: ColumnKind,
        isComputed: Bool = false
    ) {
        self.name = name
        self.displayName = displayName
        self.typeName = typeName
        self.kind = kind
        self.isComputed = isComputed
    }
}

/// 一块数据。rows 里 nil 表示 SQL NULL，空字符串表示真的空串。
public struct TableBlock: Sendable, Equatable {
    public let offset: Int
    public let rows: [[String?]]

    public init(offset: Int, rows: [[String?]]) {
        self.offset = offset
        self.rows = rows
    }

    public var isEmpty: Bool { rows.isEmpty }
}

/// 统一错误模型：用户看的、技术细节、下一步建议。
public struct ImportError: Error, Sendable {
    public let userMessage: String
    public let technicalDetail: String?
    public let recoverySuggestion: String?

    public init(userMessage: String, technicalDetail: String? = nil, recoverySuggestion: String? = nil) {
        self.userMessage = userMessage
        self.technicalDetail = technicalDetail
        self.recoverySuggestion = recoverySuggestion
    }

    public static func wrap(_ error: Error, step: String) -> ImportError {
        let detail = (error as? ImportError)?.technicalDetail ?? String(describing: error)
        return ImportError(
            userMessage: "\(step)失败",
            technicalDetail: detail,
            recoverySuggestion: "确认文件没有被其他程序占用，然后重试。"
        )
    }
}
