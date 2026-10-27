import Foundation

/// 多层表头里的一格。`level` 从 0 开始自上往下，`levelSpan` 是纵向跨几层
/// （行维度标题要贯穿全部层），`startColumn` 是结果列里的下标，`span` 是横向合并几列。
public struct PivotHeaderCell: Hashable, Sendable {
    public let title: String
    public let level: Int
    public let levelSpan: Int
    public let startColumn: Int
    public let span: Int

    public init(title: String, level: Int, levelSpan: Int = 1, startColumn: Int, span: Int = 1) {
        self.title = title
        self.level = level
        self.levelSpan = max(1, levelSpan)
        self.startColumn = startColumn
        self.span = max(1, span)
    }
}

/// 透视结果的表头层级。行维度列各占一层、纵向贯穿；列维度按“值 × 维度组合”展开。
public struct PivotHeader: Hashable, Sendable {
    public let levelCount: Int
    /// 左侧有几个行维度列，界面据此决定冻结几列、哪几格纵向贯穿。
    public let rowDimensionCount: Int
    public let cells: [PivotHeaderCell]

    public init(levelCount: Int, rowDimensionCount: Int, cells: [PivotHeaderCell]) {
        self.levelCount = max(1, levelCount)
        self.rowDimensionCount = max(0, rowDimensionCount)
        self.cells = cells
    }

    /// 某一层的格子，按列位置排好。
    public func cells(atLevel level: Int) -> [PivotHeaderCell] {
        cells.filter { $0.level == level }.sorted { $0.startColumn < $1.startColumn }
    }

    /// 单层表头的退化形态：每列一个标题，横向不合并。界面在没有层级信息时也走这份。
    public static func singleRow(titles: [String]) -> PivotHeader {
        PivotHeader(
            levelCount: 1,
            rowDimensionCount: 0,
            cells: titles.enumerated().map {
                PivotHeaderCell(title: $0.element, level: 0, startColumn: $0.offset, span: 1)
            }
        )
    }
}

/// 透视结果：查询结果加表头层级。层级只在透视这条路径上有，所以不塞进 SQLResult。
public struct PivotResult: Sendable {
    public let result: SQLResult
    public let header: PivotHeader

    public init(result: SQLResult, header: PivotHeader) {
        self.result = result
        self.header = header
    }

    public var columns: [ColumnInfo] { result.columns }
    public var rows: [[String?]] { result.rows }
    public var rowCount: Int { result.rowCount }
    public var elapsed: TimeInterval { result.elapsed }
    public var truncated: Bool { result.truncated }
}
