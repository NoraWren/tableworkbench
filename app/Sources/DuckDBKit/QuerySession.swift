import Foundation

/// 界面层只依赖这个协议，不直接依赖 DuckDB。
public protocol QuerySession: AnyObject, Sendable {
    var columns: [ColumnInfo] { get }
    /// 文件总行数，不受筛选影响。
    var rowCount: Int { get }
    /// 当前排序和筛选后的结果行数。
    var resultCount: Int { get }
    /// 查询代次，排序或筛选变化时自增，用于让块缓存失效。
    var generation: Int { get }
    func apply(view: QueryView) throws
    /// 执行一条用户 SQL，结果最多 100000 行。
    func runSQL(_ sql: String) throws -> SQLResult
    func block(offset: Int, size: Int) throws -> TableBlock
    func close()
}

public enum QuerySessionDefaults {
    public static let blockSize = 5000
}
