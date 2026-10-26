import Foundation
import DuckDBKit

/// 透视面板里“正在摆的这张表”。把落位规则从视图里拆出来，才好断言。
public final class PivotDraft {
    public enum Area: String, CaseIterable, Sendable {
        case rows = "行"
        case columns = "列"
        case values = "值"
        case filter = "筛选"
    }

    public private(set) var rows: [String] = []
    public private(set) var columns: [String] = []
    public private(set) var values: [PivotValue] = []
    public private(set) var filters: [FilterCondition] = []

    public init() {}

    public var spec: PivotSpec {
        PivotSpec(
            rows: rows,
            columns: columns,
            values: values,
            filter: filters.isEmpty ? nil : FilterGroup(join: .and, conditions: filters)
        )
    }

    /// 行和值都填了才能生成，列维度可以不填。
    public var canRun: Bool {
        !rows.isEmpty && !values.isEmpty && incompleteFilters.isEmpty
    }

    /// 生成按钮下方那行提示，空着就说明可以生成了。
    public var blockedHint: String? {
        if rows.isEmpty && values.isEmpty { return "至少放一个字段到行或值" }
        if rows.isEmpty { return "把字段拖到行" }
        if values.isEmpty { return "至少放一个字段到值" }
        if let field = incompleteFilters.first { return "筛选条件「\(field)」还没填值" }
        return nil
    }

    /// 填了运算符但没填值的筛选，生成前先拦下来，免得出来一张空表。
    public var incompleteFilters: [String] {
        filters.filter { $0.op.needsValue && $0.value.isEmpty }.map(\.column)
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
        case .filter:
            if !filters.contains(where: { $0.column == field }) {
                filters.append(FilterCondition(column: field, op: .equal))
            }
        }
    }

    public func remove(_ field: String, from area: Area) {
        switch area {
        case .rows: rows.removeAll { $0 == field }
        case .columns: columns.removeAll { $0 == field }
        case .values: values.removeAll { $0.column == field }
        case .filter: filters.removeAll { $0.column == field }
        }
    }

    public func setFilter(_ condition: FilterCondition) {
        guard let index = filters.firstIndex(where: { $0.column == condition.column }) else { return }
        filters[index] = condition
    }

    public func removeFilter(at index: Int) {
        guard filters.indices.contains(index) else { return }
        filters.remove(at: index)
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
