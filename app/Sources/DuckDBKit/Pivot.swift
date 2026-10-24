import Foundation

public enum PivotAggregate: String, CaseIterable, Hashable, Sendable {
    case sum
    case count
    case countDistinct
    case average
    case minimum
    case maximum

    public var title: String {
        switch self {
        case .sum: return "求和"
        case .count: return "计数"
        case .countDistinct: return "去重计数"
        case .average: return "平均"
        case .minimum: return "最小"
        case .maximum: return "最大"
        }
    }
}

public struct PivotValue: Hashable, Sendable {
    public var column: String
    public var aggregate: PivotAggregate

    public init(column: String, aggregate: PivotAggregate = .sum) {
        self.column = column
        self.aggregate = aggregate
    }

    public var title: String { "\(column) \(aggregate.title)" }
}

public struct PivotSpec: Hashable, Sendable {
    public var rows: [String]
    public var columns: [String]
    public var values: [PivotValue]

    public init(rows: [String] = [], columns: [String] = [], values: [PivotValue] = []) {
        self.rows = rows
        self.columns = columns
        self.values = values
    }

    public var isValid: Bool {
        !rows.isEmpty && !values.isEmpty
    }
}
