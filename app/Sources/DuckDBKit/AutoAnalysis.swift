import Foundation

/// 一键分析的挑列规则：先看名字，再看基数。
public enum AutoAnalysis {
    public static let groupKeywords = ["区域", "地区", "城市", "省份", "渠道", "产品", "状态", "类型", "类别", "分类", "等级", "分组", "部门", "行业"]
    public static let measureKeywords = ["金额", "销售额", "收入", "数量", "单价", "成本", "毛利", "利润", "费用"]

    /// 候选分组列：先是名字命中分类词的，再是其余文本列，保持原顺序。
    public static func groupCandidates(_ columns: [ColumnInfo]) -> [ColumnInfo] {
        let textColumns = columns.filter { !$0.kind.isNumeric && $0.kind != .date && $0.kind != .timestamp }
        let named = textColumns.filter { column in
            groupKeywords.contains { column.displayName.contains($0) }
        }
        let others = textColumns.filter { column in
            !groupKeywords.contains { column.displayName.contains($0) }
        }
        return named + others
    }

    /// 度量列：名字命中金额/数量这类词优先，否则取第一个数值列。
    public static func measureColumn(_ columns: [ColumnInfo]) -> ColumnInfo? {
        let numeric = columns.filter { $0.kind.isNumeric }
        // 按关键词的优先级找，而不是按列顺序：金额比数量更该当度量。
        for keyword in measureKeywords {
            if let hit = numeric.first(where: { $0.displayName.contains(keyword) }) {
                return hit
            }
        }
        return numeric.first
    }

    /// 生成图表配置。cardinality 返回某列的取值个数，超过上限的列会被跳过。
    public static func plan(
        columns: [ColumnInfo],
        cardinality: (String) -> Int,
        maxCharts: Int = 5,
        maxGroups: Int = 50
    ) -> [ChartSpec] {
        guard let measure = measureColumn(columns) else { return [] }
        var specs: [ChartSpec] = []
        for candidate in groupCandidates(columns) {
            if specs.count >= maxCharts { break }
            let distinct = cardinality(candidate.name)
            guard distinct > 0, distinct <= maxGroups else { continue }
            specs.append(
                ChartSpec(
                    kind: .bar,
                    groupColumn: candidate.name,
                    value: PivotValue(column: measure.name, aggregate: .sum)
                )
            )
        }
        return specs
    }
}
