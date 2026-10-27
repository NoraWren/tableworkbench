import AppKit
import DuckDBKit

/// 冻结在左侧的行维度列。透视结果横向滚动时这几列不动，纵向跟着主表走。
///
/// 它是盖在滚动区左边的一块自绘视图，不参与表格布局：表格照常滚动，
/// 这一块按“滚到最左边时的样子”重画前几列，因此不会出现两个表格抢数据和选中状态。
/// 纵向位置用跨视图换算拿到，行高、行间距都不用自己算。
public final class FrozenColumnsView: NSView {
    private weak var tableView: NSTableView?
    private weak var scrollView: NSScrollView?

    /// 冻结几列。0 表示不冻结，视图隐藏。
    public var frozenColumnCount: Int = 0 {
        didSet {
            isHidden = frozenColumnCount == 0
            needsDisplay = true
        }
    }

    /// 宽度约束。宽度由前几列的右边界决定，布局时统一写进这条约束。
    public var widthConstraint: NSLayoutConstraint?

    /// 多层表头。冻结列的表头也按它画，行维度标题纵向贯穿。
    public var header: PivotHeader? {
        didSet { needsDisplay = true }
    }

    public override var isFlipped: Bool { true }

    public func attach(tableView: NSTableView, scrollView: NSScrollView) {
        self.tableView = tableView
        self.scrollView = scrollView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        // 拖列宽会改变冻结区宽度，表格没有对应的代理回调，只能听通知。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(columnDidResize),
            name: NSTableView.columnDidResizeNotification,
            object: tableView
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func contentDidScroll() {
        needsDisplay = true
    }

    @objc private func columnDidResize() {
        widthConstraint?.constant = frozenWidth
        needsDisplay = true
    }

    /// 冻结区宽度：前 N 列的右边界，含列间距，和表格里的实际宽度一致。
    public var frozenWidth: CGFloat {
        guard let tableView, let last = lastFrozenIndex(in: tableView) else { return 0 }
        return tableView.rect(ofColumn: last).maxX
    }

    private func lastFrozenIndex(in tableView: NSTableView) -> Int? {
        let count = min(frozenColumnCount, tableView.numberOfColumns)
        return count > 0 ? count - 1 : nil
    }

    public override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        guard let tableView, let scrollView, let lastIndex = lastFrozenIndex(in: tableView) else { return }

        let headerHeight = tableView.headerView?.frame.height ?? 0
        let levels = max(1, header?.levelCount ?? 1)
        let levelHeight = headerHeight / CGFloat(levels)
        let frozenRight = tableView.rect(ofColumn: lastIndex).maxX

        // 正文：纵向位置换算自表格，横向固定按最左边时的列位置排。
        let clip = scrollView.contentView.bounds
        let visible = tableView.rows(in: clip)
        if visible.length > 0 {
            let selected = tableView.selectedRowIndexes
            for row in visible.location..<(visible.location + visible.length) {
                let rowRect = tableView.rect(ofRow: row)
                let y = convert(rowRect.origin, from: tableView).y
                let height = rowRect.height
                if selected.contains(row) {
                    NSColor.selectedContentBackgroundColor.setFill()
                    NSRect(x: 0, y: y, width: bounds.width, height: height).fill()
                } else if row % 2 == 1,
                          let alternate = NSColor.alternatingContentBackgroundColors.last {
                    alternate.setFill()
                    NSRect(x: 0, y: y, width: bounds.width, height: height).fill()
                }
                for index in 0...lastIndex {
                    let columnRect = tableView.rect(ofColumn: index)
                    guard let text = cellText(tableView: tableView, row: row, column: index) else { continue }
                    let attributes = selected.contains(row)
                        ? textAttributes(color: .alternateSelectedControlTextColor)
                        : textAttributes()
                    let textRect = NSRect(
                        x: columnRect.minX + 6,
                        y: y + max(0, (height - 14) / 2),
                        width: max(1, columnRect.width - 12),
                        height: 14
                    )
                    (text as NSString).draw(in: textRect, withAttributes: attributes)
                }
            }
        }

        // 表头：行维度标题纵向贯穿，写法和主表头一致。
        if let header {
            for cell in header.cells where cell.startColumn <= lastIndex {
                let first = cell.startColumn
                let last = min(cell.startColumn + cell.span - 1, lastIndex)
                guard last >= first else { continue }
                let left = tableView.rect(ofColumn: first).minX
                let right = tableView.rect(ofColumn: last).maxX
                drawHeaderCell(
                    cell.title,
                    in: NSRect(
                        x: left,
                        y: CGFloat(cell.level) * levelHeight,
                        width: right - left,
                        height: levelHeight * CGFloat(cell.levelSpan)
                    )
                )
            }
            NSColor.separatorColor.setFill()
            for level in 1...levels {
                NSRect(x: 0, y: CGFloat(level) * levelHeight - 1, width: bounds.width, height: 1).fill()
            }
        } else if let first = tableView.tableColumns.first {
            drawHeaderCell(first.title, in: NSRect(x: 0, y: 0, width: frozenRight, height: headerHeight))
        }

        NSColor.separatorColor.setFill()
        NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
    }

    private func textAttributes(
        color: NSColor = .labelColor,
        weight: NSFont.Weight = .regular
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    }

    private func drawHeaderCell(_ title: String, in rect: NSRect) {
        guard rect.width > 1 else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
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

    /// 单元格文本从主表的数据源取，冻结区不另存一份数据。
    private func cellText(tableView: NSTableView, row: Int, column: Int) -> String? {
        guard column < tableView.tableColumns.count,
              let dataSource = tableView.dataSource as? GridDataSource else { return nil }
        let identifier = tableView.tableColumns[column].identifier.rawValue
        guard let columnIndex = dataSource.columns.firstIndex(where: { $0.displayName == identifier }) else {
            return nil
        }
        let kind = dataSource.columns[columnIndex].kind
        return dataSource.cellValue(row: row, columnIndex: columnIndex)
            .map { CellText.display($0, kind: kind) } ?? "NULL"
    }

    // MARK: - 交互

    /// 点在冻结区也要能选中行，双击要能进详情，所以按主表的行位置自己算一次。
    public override func mouseDown(with event: NSEvent) {
        guard let tableView, let scrollView else { return }
        let point = convert(event.locationInWindow, from: nil)
        let headerHeight = tableView.headerView?.frame.height ?? 0
        guard point.y >= headerHeight else { return }

        let tablePoint = convert(point, to: tableView)
        let row = tableView.row(at: tablePoint)
        guard row >= 0, row < tableView.numberOfRows else { return }

        let additive = event.modifierFlags.contains(.command)
            || event.modifierFlags.contains(.shift)
        if additive {
            var rows = tableView.selectedRowIndexes
            if rows.contains(row) { rows.remove(row) } else { rows.insert(row) }
            tableView.selectRowIndexes(rows, byExtendingSelection: false)
        } else {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        tableView.scrollRowToVisible(row)
        if event.clickCount == 2 {
            (tableView as? GridTableView)?.onRowActivate?(row)
        }
        _ = scrollView
    }

    /// 滚轮落在冻结区也要滚主表，否则鼠标停在左边就滚不动。
    public override func scrollWheel(with event: NSEvent) {
        guard let scrollView else {
            super.scrollWheel(with: event)
            return
        }
        scrollView.scrollWheel(with: event)
    }
}

