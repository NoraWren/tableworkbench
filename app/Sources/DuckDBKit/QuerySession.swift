import Foundation

/// 界面层只依赖这个协议，不直接依赖 DuckDB。
public protocol QuerySession: AnyObject, Sendable {
    var columns: [ColumnInfo] { get }
    /// 网格显示的列，包含计算列。
    var displayColumns: [ColumnInfo] { get }
    /// 文件总行数，不受筛选影响。
    var rowCount: Int { get }
    /// 当前排序和筛选后的结果行数。
    var resultCount: Int { get }
    /// 查询代次，排序或筛选变化时自增，用于让块缓存失效。
    var generation: Int { get }
    func apply(view: QueryView) throws
    /// 执行一条用户 SQL，结果最多 100000 行。
    func runSQL(_ sql: String) throws -> SQLResult
    /// 按透视配置生成交叉表。
    func pivot(spec: PivotSpec) throws -> SQLResult
    /// 透视结果连表头层级一起返回。界面靠它画多层表头。
    func pivotWithHeader(spec: PivotSpec) throws -> PivotResult
    /// 只把透视配置翻译成 SQL，不执行。给“在 SQL 抽屉复现”用。
    func pivotSQL(spec: PivotSpec) throws -> String
    /// 统计一列。源表跟随当前筛选。
    func columnStats(column: String) throws -> ColumnStats
    /// 检查器累计发出的 SQL 条数，缓存命中不增加。替身会话不需要，默认 0。
    var statsQueryCount: Int { get }
    /// 一列有多少个不同取值，用于挑分组维度。
    func distinctCount(column: String) throws -> Int
    /// 导出当前视图，返回导出行数。
    func export(to url: URL, format: ExportFormat) throws -> Int
    /// 按范围导出，返回导出行数。
    func export(to url: URL, format: ExportFormat, scope: ExportScope) throws -> Int
    /// 添加一个只存在于当前会话的计算列。
    func addComputedColumn(name: String, expression: String) throws
    func block(offset: Int, size: Int) throws -> TableBlock
    /// 只取排序与筛选后的前若干行。大表靠它先出首屏，物化在后台继续。
    /// 会话不支持或视图里没有排序筛选时返回 nil，调用方退回原路径。
    func previewBlock(view: QueryView, columns: [ColumnInfo], limit: Int) throws -> TableBlock?
    /// 只取指定列的块，顺序与传入的列一致。宽表只显示前若干列时靠它少查列。
    func block(offset: Int, size: Int, columns: [ColumnInfo]) throws -> TableBlock
    func close()
}

public extension QuerySession {
    var statsQueryCount: Int { 0 }

    /// 默认实现退回全量列，替身会话和测试用不上按列裁剪。
    func block(offset: Int, size: Int, columns: [ColumnInfo]) throws -> TableBlock {
        try block(offset: offset, size: size)
    }

    /// 默认忽略范围，替身会话用不到三种口径。
    func export(to url: URL, format: ExportFormat, scope: ExportScope) throws -> Int {
        try export(to: url, format: format)
    }

    /// 替身会话没有真实数据，返回一个大数，让挑列逻辑跳过它。
    func distinctCount(column: String) throws -> Int {
        Int.max
    }
}

/// 导出范围。行号是网格里的位置，从 0 开始。
public enum ExportScope: Sendable, Equatable {
    /// 当前筛选与排序结果。
    case view
    /// 源表全部行，忽略筛选和排序。
    case all
    /// 指定行，顺序按网格显示顺序。
    case rows(IndexSet)
}

public extension QuerySession {
    /// 默认不提供首屏预览。替身会话与不支持预览的实现走这条，界面按老路径一次出全量。
    func previewBlock(view: QueryView, columns: [ColumnInfo], limit: Int) throws -> TableBlock? { nil }
}

public enum QuerySessionDefaults {
    public static let blockSize = 5000
    /// 超过这个列数就只默认显示前 200 列，其余由用户启用。
    public static let maxVisibleColumns = 2000
    public static let defaultVisibleColumns = 200
}
