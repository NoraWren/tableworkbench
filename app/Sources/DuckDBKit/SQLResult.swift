import Foundation

public struct SQLResult: Sendable {
    public let columns: [ColumnInfo]
    public let rows: [[String?]]
    public let rowCount: Int
    public let elapsed: TimeInterval
    public let truncated: Bool

    public init(columns: [ColumnInfo], rows: [[String?]], rowCount: Int, elapsed: TimeInterval, truncated: Bool) {
        self.columns = columns
        self.rows = rows
        self.rowCount = rowCount
        self.elapsed = elapsed
        self.truncated = truncated
    }

    public static let empty = SQLResult(columns: [], rows: [], rowCount: 0, elapsed: 0, truncated: false)
}
