import AppKit
import DuckDBKit

/// 多层表头。NSTableView 自带的表头只有一行，装不下透视的维度层级，
/// 这里用自绘表头按 PivotHeader 画格子，同层相同标签横向合并。
///
/// 横向位置取自 convert(tableView.rect(ofColumn:), from: tableView)：表头视图所在的
/// 裁剪视图自己不跟着横向滚动（实测 bounds 恒为 0），但跨视图换算出来的坐标会带上
/// 滚动偏移，所以表头能和数据列对齐，不用另外监听滚动。
public final class GridHeaderView: NSTableHeaderView {
    /// 一格表头的画法。nil 表示按单行表头画，即每列一个标题。
    public var header: PivotHeader? {
        didSet { needsDisplay = true }
    }

    /// 每一层的行高。层数乘以它得到表头总高。
    public static let levelHeight: CGFloat = 22

    public static func height(forLevels levels: Int) -> CGFloat {
        levelHeight * CGFloat(max(1, levels))
    }

    public override var isFlipped: Bool { true }

    public override func draw(_ dirtyRect: NSRect) {
        guard let tableView else { return }

        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        let levels = max(1, header?.levelCount ?? 1)
        let levelHeight = bounds.height / CGFloat(levels)

        if let header {
            for cell in header.cells {
                let rect = rect(for: cell, in: tableView, levelHeight: levelHeight)
                guard rect.width > 1, rect.intersects(dirtyRect) else { continue }
                drawCell(cell.title, in: rect, isMerged: cell.span > 1 || cell.levelSpan > 1)
            }
        } else {
            for index in 0..<tableView.numberOfColumns {
                let column = tableView.tableColumns[index]
                let rect = columnRect(of: index, in: tableView, height: bounds.height, y: 0)
                guard rect.width > 1, rect.intersects(dirtyRect) else { continue }
                drawCell(column.title, in: rect, isMerged: false)
            }
        }

        drawSeparators(levels: levels, levelHeight: levelHeight, tableView: tableView)
    }

    /// 一列在表头坐标系里的位置，横向偏移由跨视图换算带上。
    private func columnRect(of index: Int, in tableView: NSTableView, height: CGFloat, y: CGFloat) -> NSRect {
        let inTable = tableView.rect(ofColumn: index)
        let origin = convert(inTable.origin, from: tableView)
        return NSRect(x: origin.x, y: y, width: inTable.width, height: height)
    }

    private func rect(for cell: PivotHeaderCell, in tableView: NSTableView, levelHeight: CGFloat) -> NSRect {
        let first = cell.startColumn
        let last = min(cell.startColumn + cell.span - 1, tableView.numberOfColumns - 1)
        guard first >= 0, first < tableView.numberOfColumns, last >= first else { return .zero }
        let leftRect = tableView.rect(ofColumn: first)
        let rightRect = tableView.rect(ofColumn: last)
        let left = convert(leftRect.origin, from: tableView).x
        let right = convert(rightRect.origin, from: tableView).x + rightRect.width
        return NSRect(
            x: left,
            y: CGFloat(cell.level) * levelHeight,
            width: right - left,
            height: levelHeight * CGFloat(cell.levelSpan)
        )
    }

    private func drawCell(_ title: String, in rect: NSRect, isMerged: Bool) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: isMerged ? .semibold : .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let textRect = NSRect(
            x: rect.minX + 6,
            y: rect.minY + max(0, (rect.height - 14) / 2),
            width: max(1, rect.width - 12),
            height: 14
        )
        (title as NSString).draw(in: textRect, withAttributes: attributes)
    }

    private func drawSeparators(levels: Int, levelHeight: CGFloat, tableView: NSTableView) {
        NSColor.separatorColor.setFill()
        // 层与层之间一条横线，最底一条把表头和正文分开。
        for level in 1...levels {
            let y = CGFloat(level) * levelHeight - 1
            NSRect(x: 0, y: y, width: bounds.width, height: 1).fill()
        }
        // 列边界上的竖线，合并格内部的竖线也能看出列宽。
        for index in 0..<tableView.numberOfColumns {
            let inTable = tableView.rect(ofColumn: index)
            let x = convert(inTable.origin, from: tableView).x + inTable.width - 1
            guard x >= -1, x <= bounds.width else { continue }
            NSRect(x: x, y: 0, width: 1, height: bounds.height).fill()
        }
    }
}

