import Foundation

/// 界面层只依赖这个协议，不直接依赖 DuckDB。
public protocol QuerySession: AnyObject, Sendable {
    var columns: [ColumnInfo] { get }
    var rowCount: Int { get }
    func block(offset: Int, size: Int) throws -> TableBlock
    func close()
}

public enum QuerySessionDefaults {
    public static let blockSize = 5000
}
