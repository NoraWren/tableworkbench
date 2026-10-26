import Foundation
import DuckDBKit

/// 透视面板里“正在摆的这张表”。把落位规则从视图里拆出来，才好断言。
public final class PivotDraft {
    public enum Area: String, CaseIterable, Sendable {
        case rows = "行"
        case columns = "列"
        case values = "值"
    }

    public private(set) var rows: [String] = []
    public private(set) var columns: [String] = []
    public private(set) var values: [PivotValue] = []

    public init() {}

    public var spec: PivotSpec {
        PivotSpec(rows: rows, columns: columns, values: values)
    }

    /// 行和值都填了才能生成，列维度可以不填。
    public var canRun: Bool {
        !rows.isEmpty && !values.isEmpty
    }

    /// 同一个字段重复拖进来只留一份。
    public func add(_ field: String, to area: Area) {
        switch area {
        case .rows:
            if !rows.contains(field) { rows.append(field) }
        case .columns:
            if !columns.contains(field) { columns.append(field) }
        case .values:
            if !values.contains(where: { $0.column == field }) {
                values.append(PivotValue(column: field))
            }
        }
    }

    public func remove(_ field: String, from area: Area) {
        switch area {
        case .rows: rows.removeAll { $0 == field }
        case .columns: columns.removeAll { $0 == field }
        case .values: values.removeAll { $0.column == field }
        }
    }

    /// 换聚合方式，位置保持不变，别让用户选完又跳到别的行。
    public func setAggregate(_ aggregate: PivotAggregate, for field: String) {
        guard let index = values.firstIndex(where: { $0.column == field }) else { return }
        values[index] = PivotValue(column: field, aggregate: aggregate)
    }

    public func removeValue(at index: Int) {
        guard values.indices.contains(index) else { return }
        values.remove(at: index)
    }
}
