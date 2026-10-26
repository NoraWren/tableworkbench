import AppKit
import DuckDBKit


public final class GridDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var columns: [ColumnInfo] = []
    var rowCount: Int = 0
    var blockSize: Int = QuerySessionDefaults.blockSize
    var provider: ((Int, Int) throws -> TableBlock)?
    var onError: ((Error) -> Void)?
    var onSortClick: ((String, Bool) -> Void)?
    var onSelectionChange: ((IndexSet) -> Void)?
    var sorts: [SortSpec] = []
    var computedColumnNames: Set<String> = []
    weak var contentTableView: NSTableView?
    weak var rowNumbersView: NSView?

    private let cache = BlockCache(capacity: 8)
    private let cellIdentifier = NSUserInterfaceItemIdentifier("data-cell")
    /// 查失败的块记下来，别让同一块的每个单元格各跑一遍同样的坏查询。
    private var failedBlocks: Set<Int> = []

    public func configure(
        columns: [ColumnInfo],
        rowCount: Int,
        provider: @escaping (Int, Int) throws -> TableBlock
    ) {
        self.columns = columns
        self.rowCount = rowCount
        self.provider = provider
    }

    public func numberOfRows(in tableView: NSTableView) -> Int {
        rowCount
    }

    public func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        guard !computedColumnNames.contains(tableColumn.identifier.rawValue) else { return }
        // 测试进程里没有 NSApplication，NSApp 是 nil，这里不能直接解包。
        let additive = NSApp?.currentEvent?.modifierFlags.contains(.shift) ?? false
        onSortClick?(tableColumn.identifier.rawValue, additive)
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else { return }
        onSelectionChange?(tableView.selectedRowIndexes)
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn else { return nil }

        if tableColumn.identifier.rawValue == "row-number" {
            let cell = reusableCell(in: tableView)
            cell.configure(text: String(row + 1), alignment: .right, color: .secondaryLabelColor)
            return cell
        }

        guard let columnIndex = columns.firstIndex(where: { $0.displayName == tableColumn.identifier.rawValue }) else {
            return nil
        }
        let info = columns[columnIndex]
        let value = cellValue(row: row, columnIndex: columnIndex)

        let cell = reusableCell(in: tableView)
        cell.configure(
            text: value ?? "NULL",
            alignment: info.kind.isNumeric ? .right : .left,
            color: value == nil ? .tertiaryLabelColor : .labelColor
        )
        return cell
    }

    private func reusableCell(in tableView: NSTableView) -> GridTextCellView {
        if let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? GridTextCellView {
            return cell
        }
        let cell = GridTextCellView()
        cell.identifier = cellIdentifier
        return cell
    }

    public func tsv(for rows: IndexSet, includeHeader: Bool) -> String {
        var selected: [[String?]] = []
        selected.reserveCapacity(rows.count)
        for row in rows.sorted() {
            var values: [String?] = []
            values.reserveCapacity(columns.count)
            for index in columns.indices {
                values.append(cellValue(row: row, columnIndex: index))
            }
            selected.append(values)
        }
        return TSVBuilder.build(
            rows: selected,
            columns: columns.map(\.displayName),
            includeHeader: includeHeader
        )
    }

    func cellValue(row: Int, columnIndex: Int) -> String? {
        guard row >= 0, row < rowCount else { return nil }
        let blockIndex = row / blockSize
        let block = cache.value(for: blockIndex) ?? loadBlock(blockIndex)
        guard let block else { return nil }
        let local = row - blockIndex * blockSize
        guard local >= 0, local < block.rows.count else { return nil }
        let values = block.rows[local]
        guard columnIndex < values.count else { return nil }
        return values[columnIndex]
    }

    func resetFailedBlocks() {
        failedBlocks.removeAll()
    }

    private func loadBlock(_ blockIndex: Int) -> TableBlock? {
        guard let provider else { return nil }
        guard !failedBlocks.contains(blockIndex) else { return nil }
        do {
            let block = try provider(blockIndex * blockSize, blockSize)
            cache.insert(block, for: blockIndex)
            return block
        } catch {
            failedBlocks.insert(blockIndex)
            // 视图正在布局时改 SwiftUI 状态会触发重入，放到下一轮主线程再报。
            DispatchQueue.main.async { [weak self] in
                self?.onError?(error)
            }
            return nil
        }
    }
}
