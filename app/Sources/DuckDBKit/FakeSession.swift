import Foundation

/// 没有真实 DuckDB 时使用的内存实现。只用于预览、单元测试和依赖不可用时的兜底。
public final class FakeSession: QuerySession, @unchecked Sendable {
    public let columns: [ColumnInfo]
    public let rowCount: Int
    public private(set) var resultCount: Int
    public private(set) var generation: Int = 0
    private let lock = NSLock()
    private var closed = false

    public init(columns: [ColumnInfo]? = nil, rowCount: Int = 100_000) {
        self.columns = columns ?? [
            ColumnInfo(name: "id", displayName: "id", typeName: "BIGINT", kind: .integer),
            ColumnInfo(name: "customer", displayName: "customer", typeName: "VARCHAR", kind: .text),
            ColumnInfo(name: "amount", displayName: "amount", typeName: "DOUBLE", kind: .double),
            ColumnInfo(name: "created_at", displayName: "created_at", typeName: "TIMESTAMP", kind: .timestamp)
        ]
        self.rowCount = rowCount
        self.resultCount = rowCount
    }

    public var displayColumns: [ColumnInfo] { columns }

    public func addComputedColumn(name: String, expression: String) throws {
        // 预览实现忽略计算列。
    }

    public func columnStats(column: String) throws -> ColumnStats {
        ColumnStats(
            column: column,
            typeName: "VARCHAR",
            kind: .text,
            totalRows: rowCount,
            nullCount: 0,
            distinctCount: 1,
            minValue: nil,
            maxValue: nil,
            mean: nil,
            median: nil,
            standardDeviation: nil
        )
    }

    public func export(to url: URL, format: ExportFormat) throws -> Int {
        0
    }

    public func pivot(spec: PivotSpec) throws -> SQLResult {
        SQLResult.empty
    }

    public func runSQL(_ sql: String) throws -> SQLResult {
        SQLResult(
            columns: [ColumnInfo(name: "answer", displayName: "answer", typeName: "BIGINT", kind: .integer)],
            rows: [["42"]],
            rowCount: 1,
            elapsed: 0,
            truncated: false
        )
    }

    public func apply(view: QueryView) throws {
        generation += 1
        resultCount = rowCount
    }

    public func block(offset: Int, size: Int) throws -> TableBlock {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else {
            throw ImportError(userMessage: "数据源已关闭", technicalDetail: nil, recoverySuggestion: "重新打开文件。")
        }
        let start = max(0, min(offset, rowCount))
        let end = max(start, min(offset + size, rowCount))
        var rows: [[String?]] = []
        rows.reserveCapacity(end - start)
        for index in start..<end {
            rows.append([
                String(index + 1),
                "客户 \(index % 97)",
                String(format: "%.2f", Double(index % 1000) + 0.5),
                index % 11 == 0 ? nil : "2026-10-\(String(format: "%02d", index % 28 + 1)) 10:00:00"
            ])
        }
        return TableBlock(offset: start, rows: rows)
    }

    public func close() {
        lock.lock()
        closed = true
        lock.unlock()
    }
}
