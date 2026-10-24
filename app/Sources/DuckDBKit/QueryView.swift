import Foundation

public struct SortSpec: Hashable, Sendable {
    public let column: String
    public let ascending: Bool

    public init(column: String, ascending: Bool) {
        self.column = column
        self.ascending = ascending
    }
}

public enum FilterOperator: String, CaseIterable, Hashable, Sendable {
    case equal
    case notEqual
    case contains
    case greaterThan
    case lessThan
    case between
    case isNull
    case isNotNull

    public var title: String {
        switch self {
        case .equal: return "等于"
        case .notEqual: return "不等于"
        case .contains: return "包含"
        case .greaterThan: return "大于"
        case .lessThan: return "小于"
        case .between: return "介于"
        case .isNull: return "为空"
        case .isNotNull: return "不为空"
        }
    }

    public var needsValue: Bool {
        switch self {
        case .isNull, .isNotNull: return false
        default: return true
        }
    }

    public var needsSecondValue: Bool {
        self == .between
    }
}

public struct FilterCondition: Hashable, Sendable {
    public var column: String
    public var op: FilterOperator
    public var value: String
    public var secondValue: String?

    public init(column: String, op: FilterOperator, value: String = "", secondValue: String? = nil) {
        self.column = column
        self.op = op
        self.value = value
        self.secondValue = secondValue
    }
}

public enum FilterJoin: String, Hashable, Sendable {
    case and
    case or

    public var title: String {
        self == .and ? "同时满足" : "满足任一"
    }
}

public struct FilterGroup: Hashable, Sendable {
    public var join: FilterJoin
    public var conditions: [FilterCondition]

    public init(join: FilterJoin = .and, conditions: [FilterCondition] = []) {
        self.join = join
        self.conditions = conditions
    }
}

public struct QueryView: Hashable, Sendable {
    public var sort: [SortSpec]
    public var filter: FilterGroup?

    public init(sort: [SortSpec] = [], filter: FilterGroup? = nil) {
        self.sort = sort
        self.filter = filter
    }

    public static let empty = QueryView()
}
