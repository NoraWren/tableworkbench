import Foundation

/// 宽表显示哪些列。默认取前 200 列，用户启用的列追加在后面。
public enum ColumnVisibility {
    /// 列总数超过上限时，默认显示的列名集合。
    public static func defaultShown(_ columns: [ColumnInfo]) -> Set<String> {
        guard columns.count > QuerySessionDefaults.maxVisibleColumns else {
            return Set(columns.map(\.name))
        }
        return Set(columns.prefix(QuerySessionDefaults.defaultVisibleColumns).map(\.name))
    }

    /// 返回表格应当显示的列，保持原顺序。
    public static func shown(_ columns: [ColumnInfo], enabled: Set<String>?) -> [ColumnInfo] {
        guard columns.count > QuerySessionDefaults.maxVisibleColumns else {
            return columns
        }
        let names = enabled ?? defaultShown(columns)
        return columns.filter { names.contains($0.name) }
    }

    /// 切换一列的显示状态，返回新的集合。
    public static func toggled(_ columns: [ColumnInfo], enabled: Set<String>?, column: String) -> Set<String> {
        var set = enabled ?? defaultShown(columns)
        if set.contains(column) {
            set.remove(column)
        } else {
            set.insert(column)
        }
        return set
    }
}
