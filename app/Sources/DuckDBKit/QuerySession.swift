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
    /// 统计一列。源表跟随当前筛选。
    func columnStats(column: String) throws -> ColumnStats
    /// 导出当前视图，返回导出行数。
    func export(to url: URL, format: ExportFormat) throws -> Int
    /// 添加一个只存在于当前会话的计算列。
    func addComputedColumn(name: String, expression: String) throws
    func block(offset: Int, size: Int) throws -> TableBlock
    /// 只取指定列的块，顺序与传入的列一致。宽表只显示前若干列时靠它少查列。
    func block(offset: Int, size: Int, columns: [ColumnInfo]) throws -> TableBlock
    func close()
}

public extension QuerySession {
    /// 默认实现退回全量列，替身会话和测试用不上按列裁剪。
    func block(offset: Int, size: Int, columns: [ColumnInfo]) throws -> TableBlock {
        try block(offset: offset, size: size)
    }
}

public enum QuerySessionDefaults {
    public static let blockSize = 5000
}
