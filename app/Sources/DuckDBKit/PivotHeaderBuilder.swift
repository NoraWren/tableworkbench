import Foundation

extension PivotHeader {
    /// 按配置和列组合算表头层级。纯计算，不查库。
    ///
    /// 列按 `值 × 列组合` 展开，所以层级自上而下是：值标题（多于一个值才出现）、
    /// 第一个列维度、第二个列维度……。行维度列在左边，各占一列并纵向贯穿全部层。
    public static func build(spec: PivotSpec, combos: [[String]]) -> PivotHeader {
        let rowCount = spec.rows.count
        var cells: [PivotHeaderCell] = []

        // 没有列维度时表头只有一行：先排行维度，再排每个值。
        guard !spec.columns.isEmpty else {
            for (index, row) in spec.rows.enumerated() {
                cells.append(PivotHeaderCell(title: row, level: 0, startColumn: index))
            }
            for (index, value) in spec.values.enumerated() {
                cells.append(PivotHeaderCell(title: value.title, level: 0, startColumn: rowCount + index))
            }
            return PivotHeader(levelCount: 1, rowDimensionCount: rowCount, cells: cells)
        }

        let dimensionLevels = spec.columns.count
        let hasValueLevel = spec.values.count > 1
        let levelCount = dimensionLevels + (hasValueLevel ? 1 : 0)

        // 行维度：每列一格，纵向贯穿。
        for (index, row) in spec.rows.enumerated() {
            cells.append(PivotHeaderCell(
                title: row,
                level: 0,
                levelSpan: levelCount,
                startColumn: index
            ))
        }

        // 每个值各占一段连续的列，段内是全部列组合。
        let combosPerValue = combos.count
        for (valueIndex, value) in spec.values.enumerated() {
            let segmentStart = rowCount + valueIndex * combosPerValue

            if hasValueLevel, combosPerValue > 0 {
                cells.append(PivotHeaderCell(
                    title: value.title,
                    level: 0,
                    startColumn: segmentStart,
                    span: combosPerValue
                ))
            }

            // 逐级合并：第 depth 层看组合的前 depth+1 段是否相同，相同就横向并成一格。
            for depth in 0..<dimensionLevels {
                let level = depth + (hasValueLevel ? 1 : 0)
                var runStart = segmentStart
                var runSpan = 0
                var runKey: [String] = []
                var runTitle = ""

                for (offset, combo) in combos.enumerated() {
                    let key = Array(combo.prefix(depth + 1))
                    let title = combo.indices.contains(depth) ? combo[depth] : ""
                    if runSpan > 0, key == runKey {
                        runSpan += 1
                        continue
                    }
                    if runSpan > 0 {
                        cells.append(PivotHeaderCell(
                            title: runTitle,
                            level: level,
                            startColumn: runStart,
                            span: runSpan
                        ))
                    }
                    runKey = key
                    runTitle = title
                    runStart = segmentStart + offset
                    runSpan = 1
                }
                if runSpan > 0 {
                    cells.append(PivotHeaderCell(
                        title: runTitle,
                        level: level,
                        startColumn: runStart,
                        span: runSpan
                    ))
                }
            }
        }

        return PivotHeader(levelCount: levelCount, rowDimensionCount: rowCount, cells: cells)
    }
}
